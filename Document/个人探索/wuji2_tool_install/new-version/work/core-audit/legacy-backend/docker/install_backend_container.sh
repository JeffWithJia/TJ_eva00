#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACTION="${1:-smoke}"
IMAGE="${APEX_BACKEND_IMAGE:-kernelmind/apex-backend:humble-arm64}"
ROS_DISTRO_NAME="${APEX_ROS_DISTRO:-humble}"
MANAGEMENT_DIR="${APEX_BACKEND_MANAGEMENT_DIR:-/usr/local/share/apex/backend-docker}"
HOST_HELPER=/usr/local/libexec/apex/apex_backend_host_control.py
HOST_UNIT=/etc/systemd/system/apex-backend-host-control.service
BACKEND_UNIT=/etc/systemd/system/apex-backend.service
CONTAINER_ENV=/etc/apex/backend-container.env

set -a
if [[ -r /etc/apex/apex.env ]]; then
  # shellcheck disable=SC1091
  source /etc/apex/apex.env
fi
set +a

resolve_run_user() {
  if [[ -n "${APEX_RUN_USER:-}" ]]; then
    printf '%s\n' "${APEX_RUN_USER}"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "${SUDO_USER}"
  elif [[ -n "${HOME:-}" && "${HOME}" == /home/* ]]; then
    basename "${HOME}"
  else
    getent passwd 1000 | cut -d: -f1
  fi
}

RUN_USER="$(resolve_run_user)"
if [[ -z "${RUN_USER}" ]] || ! id "${RUN_USER}" >/dev/null 2>&1; then
  echo "ERROR: cannot determine Apex run user; set APEX_RUN_USER." >&2
  exit 2
fi
RUN_UID="$(id -u "${RUN_USER}")"
RUN_GID="$(id -g "${RUN_USER}")"
BAG_ROOT="${BAG_STORAGE_ROOT:-/media/${RUN_USER}/BAG_STORAGE}"

if [[ "${IMAGE}" == *[[:space:]]* || "${IMAGE}" != */*:* ]]; then
  echo "ERROR: invalid Backend image reference: ${IMAGE}" >&2
  exit 2
fi

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    as_root docker "$@"
  fi
}

load_image_if_requested() {
  if [[ -n "${APEX_BACKEND_IMAGE_TAR:-}" ]]; then
    if [[ ! -r "${APEX_BACKEND_IMAGE_TAR}" ]]; then
      echo "ERROR: bundled Backend image is unreadable: ${APEX_BACKEND_IMAGE_TAR}" >&2
      exit 2
    fi
    echo "Loading offline Backend image ${IMAGE} ..."
    docker_cmd load --input "${APEX_BACKEND_IMAGE_TAR}"
  fi
  docker_cmd image inspect "${IMAGE}" >/dev/null
  local architecture
  architecture="$(docker_cmd image inspect "${IMAGE}" --format '{{.Architecture}}')"
  if [[ "${architecture}" != "arm64" ]]; then
    echo "ERROR: Backend image ${IMAGE} is ${architecture}, expected arm64." >&2
    exit 2
  fi
}

bag_mount_args() {
  if [[ "${BAG_ROOT}" == /media || "${BAG_ROOT}" == /media/* ]]; then
    printf '%s\n' --mount type=bind,source=/media,target=/media,bind-propagation=rslave
  else
    as_root install -d -m 0775 -o "${RUN_UID}" -g "${RUN_GID}" "${BAG_ROOT}"
    printf '%s\n' --mount "type=bind,source=${BAG_ROOT},target=${BAG_ROOT}"
  fi
}

install_host_proxy() {
  as_root install -d -m 0755 /usr/local/libexec/apex
  as_root install -m 0755 "${BACKEND_DIR}/scripts/apex_backend_host_control.py" "${HOST_HELPER}"
  sed \
    -e "s/APEX_HOST_CONTROL_UID=1000/APEX_HOST_CONTROL_UID=${RUN_UID}/" \
    -e "s/APEX_HOST_CONTROL_GID=1000/APEX_HOST_CONTROL_GID=${RUN_GID}/" \
    "${BACKEND_DIR}/systemd/apex-backend-host-control.service" \
    | as_root tee "${HOST_UNIT}" >/dev/null
  as_root systemctl daemon-reload
  as_root systemctl enable --now apex-backend-host-control.service

  for _ in $(seq 1 50); do
    [[ -S /run/apex-host-control/backend.sock ]] && return
    sleep 0.1
  done
  as_root systemctl status apex-backend-host-control.service --no-pager -l || true
  echo "ERROR: host control socket was not created." >&2
  exit 1
}

install_management_bundle() {
  as_root install -d -m 0755 \
    "${MANAGEMENT_DIR}/docker" \
    "${MANAGEMENT_DIR}/scripts" \
    "${MANAGEMENT_DIR}/systemd"
  as_root install -m 0755 \
    "${BACKEND_DIR}/docker/install_backend_container.sh" \
    "${MANAGEMENT_DIR}/docker/install_backend_container.sh"
  as_root install -m 0755 \
    "${BACKEND_DIR}/scripts/apex_backend_host_control.py" \
    "${MANAGEMENT_DIR}/scripts/apex_backend_host_control.py"
  as_root install -m 0644 \
    "${BACKEND_DIR}/systemd/apex-backend-container.service" \
    "${MANAGEMENT_DIR}/systemd/apex-backend-container.service"
  as_root install -m 0644 \
    "${BACKEND_DIR}/systemd/apex-backend-host-control.service" \
    "${MANAGEMENT_DIR}/systemd/apex-backend-host-control.service"
}

health_ready() {
  local port="$1"
  python3 - "${port}" <<'PY' >/dev/null 2>&1
import sys
import urllib.request

with urllib.request.urlopen(
    f"http://127.0.0.1:{sys.argv[1]}/api/v1/system/health", timeout=2
) as response:
    if response.status != 200:
        raise RuntimeError(response.status)
PY
}

smoke_test() {
  load_image_if_requested
  install_host_proxy
  docker_cmd rm --force apex-backend-smoke >/dev/null 2>&1 || true
  local -a mounts
  mapfile -t mounts < <(bag_mount_args)
  docker_cmd run --detach \
    --name apex-backend-smoke \
    --network host \
    --ipc host \
    --read-only \
    --user "${RUN_UID}:${RUN_GID}" \
    --env-file /etc/apex/apex.env \
    --env HOME=/home/apex \
    --env APEX_CONTAINER_ENV_LOADED=1 \
    --env APEX_BACKEND_PORT=18080 \
    --env APEX_HOST_CONTROL_SOCKET=/run/apex-host-control/backend.sock \
    --mount type=bind,source=/etc/apex,target=/etc/apex,readonly \
    --mount type=bind,source=/run/apex-host-control/backend.sock,target=/run/apex-host-control/backend.sock \
    "${mounts[@]}" \
    --mount type=bind,source=/var/log/apex,target=/var/log/apex \
    --tmpfs /tmp:rw,size=64m,mode=1777 \
    --tmpfs /home/apex/.ros:rw,size=16m,uid="${RUN_UID}",gid="${RUN_GID}" \
    "${IMAGE}" >/dev/null

  cleanup_smoke() {
    docker_cmd rm --force apex-backend-smoke >/dev/null 2>&1 || true
  }

  for _ in $(seq 1 30); do
    if health_ready 18080; then
      if ! docker_cmd exec apex-backend-smoke bash -lc \
        "source /opt/ros/${ROS_DISTRO_NAME}/setup.bash && source /opt/apex_ws/install/setup.bash && ros2 pkg prefix apex_backend && ros2 pkg prefix marvin_msgs && ros2 pkg prefix move"; then
        docker_cmd logs apex-backend-smoke >&2 || true
        cleanup_smoke
        echo "ERROR: Backend image ROS package smoke check failed." >&2
        return 1
      fi
      echo "Backend container smoke test passed on port 18080."
      cleanup_smoke
      return
    fi
    sleep 1
  done
  docker_cmd logs apex-backend-smoke >&2 || true
  cleanup_smoke
  echo "ERROR: Backend container did not become healthy." >&2
  return 1
}

render_container_unit() {
  local output="$1"
  local bag_mount
  if [[ "${BAG_ROOT}" == /media || "${BAG_ROOT}" == /media/* ]]; then
    bag_mount="--mount type=bind,source=/media,target=/media,bind-propagation=rslave"
  else
    bag_mount="--mount type=bind,source=${BAG_ROOT},target=${BAG_ROOT}"
  fi
  sed \
    -e "s|@APEX_BACKEND_IMAGE@|${IMAGE}|g" \
    -e "s|@RUN_UID@|${RUN_UID}|g" \
    -e "s|@RUN_GID@|${RUN_GID}|g" \
    -e "s|@BAG_MOUNT@|${bag_mount}|g" \
    "${BACKEND_DIR}/systemd/apex-backend-container.service" >"${output}"
}

restore_previous_unit() {
  local previous_unit="$1"
  local had_previous="$2"
  as_root systemctl stop apex-backend.service >/dev/null 2>&1 || true
  docker_cmd rm --force apex-backend >/dev/null 2>&1 || true
  if [[ "${had_previous}" == "1" ]]; then
    as_root install -m 0644 "${previous_unit}" "${BACKEND_UNIT}"
    as_root systemctl daemon-reload
    as_root systemctl enable --now apex-backend.service || true
  else
    as_root rm -f "${BACKEND_UNIT}"
    as_root systemctl daemon-reload
  fi
}

cleanup_previous_image() {
  local previous_image="$1"
  if [[ -n "${previous_image}" && "${previous_image}" != "${IMAGE}" && \
        "${previous_image}" == kernelmind/apex-backend:* ]]; then
    docker_cmd image rm "${previous_image}" >/dev/null 2>&1 || true
  fi
}

install_container_service() {
  smoke_test
  install_management_bundle

  local previous_image=""
  if [[ -r "${CONTAINER_ENV}" ]]; then
    previous_image="$(sed -n 's/^APEX_BACKEND_IMAGE=//p' "${CONTAINER_ENV}" | tail -n 1)"
  fi

  local rendered_unit previous_unit had_previous=0
  rendered_unit="$(mktemp)"
  previous_unit="$(mktemp)"
  render_container_unit "${rendered_unit}"
  if [[ -f "${BACKEND_UNIT}" ]]; then
    cp -a "${BACKEND_UNIT}" "${previous_unit}"
    had_previous=1
  fi

  as_root systemctl stop apex-backend.service >/dev/null 2>&1 || true
  docker_cmd rm --force apex-backend >/dev/null 2>&1 || true
  as_root install -m 0644 "${rendered_unit}" "${BACKEND_UNIT}"
  as_root systemctl daemon-reload
  as_root systemctl enable apex-backend-host-control.service apex-backend.service
  if ! as_root systemctl start apex-backend.service; then
    as_root systemctl status apex-backend.service --no-pager -l || true
    restore_previous_unit "${previous_unit}" "${had_previous}"
    rm -f "${rendered_unit}" "${previous_unit}"
    echo "ERROR: failed to start containerized Backend; previous unit restored." >&2
    exit 1
  fi

  for _ in $(seq 1 45); do
    if health_ready 8080; then
      printf 'APEX_BACKEND_IMAGE=%s\n' "${IMAGE}" \
        | as_root tee "${CONTAINER_ENV}" >/dev/null
      as_root chmod 0644 "${CONTAINER_ENV}"
      cleanup_previous_image "${previous_image}"
      rm -f "${rendered_unit}" "${previous_unit}"
      echo "Containerized Backend ${IMAGE} is healthy on port 8080."
      return
    fi
    sleep 1
  done

  as_root systemctl status apex-backend.service --no-pager -l || true
  as_root journalctl -u apex-backend.service -n 100 --no-pager || true
  restore_previous_unit "${previous_unit}" "${had_previous}"
  rm -f "${rendered_unit}" "${previous_unit}"
  echo "ERROR: production health check failed; previous unit restored." >&2
  exit 1
}

uninstall_container_service() {
  local installed_image="${IMAGE}"
  if [[ -r "${CONTAINER_ENV}" ]]; then
    installed_image="$(sed -n 's/^APEX_BACKEND_IMAGE=//p' "${CONTAINER_ENV}" | tail -n 1)"
  fi
  as_root systemctl disable --now apex-backend.service apex-backend-host-control.service \
    >/dev/null 2>&1 || true
  docker_cmd rm --force apex-backend apex-backend-smoke >/dev/null 2>&1 || true
  as_root rm -f "${BACKEND_UNIT}" "${HOST_UNIT}" "${HOST_HELPER}" "${CONTAINER_ENV}"
  as_root rm -rf "${MANAGEMENT_DIR}"
  as_root systemctl daemon-reload
  if [[ "${APEX_KEEP_BACKEND_IMAGE:-0}" != "1" && \
        "${installed_image}" == kernelmind/apex-backend:* ]]; then
    docker_cmd image rm "${installed_image}" >/dev/null 2>&1 || true
  fi
}

case "${ACTION}" in
  proxy) install_host_proxy ;;
  smoke) smoke_test ;;
  install) install_container_service ;;
  uninstall) uninstall_container_service ;;
  *)
    echo "Usage: $0 [proxy|smoke|install|uninstall]" >&2
    exit 2
    ;;
esac
