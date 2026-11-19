#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ROS_DISTRO_NAME="${APEX_ROS_DISTRO:-humble}"
case "${ROS_DISTRO_NAME}" in
  humble)
    DEFAULT_BASE_IMAGE="ros:humble-ros-base-jammy"
    ;;
  jazzy)
    DEFAULT_BASE_IMAGE="ros:jazzy-ros-base-noble"
    ;;
  *)
    echo "ERROR: unsupported Backend ROS distro: ${ROS_DISTRO_NAME}" >&2
    exit 2
    ;;
esac
DOCKERFILE="${SCRIPT_DIR}/Dockerfile.${ROS_DISTRO_NAME}"
IMAGE="${APEX_BACKEND_IMAGE:-kernelmind/apex-backend:${ROS_DISTRO_NAME}-arm64}"
BASE_IMAGE="${APEX_ROS_BASE_IMAGE:-${DEFAULT_BASE_IMAGE}}"
PIP_INDEX_URL="${APEX_PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"

if [[ ! -r "${DOCKERFILE}" ]]; then
  echo "ERROR: Backend Dockerfile not found: ${DOCKERFILE}" >&2
  exit 2
fi

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

save_image() {
  local archive="$1"
  if docker_cmd image save --help 2>&1 | grep -q -- '--platform'; then
    docker_cmd image save --platform linux/arm64 --output "${archive}" "${IMAGE}"
  else
    docker_cmd save --output "${archive}" "${IMAGE}"
  fi
}

if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "ERROR: this image must be built on ARM64 or with an explicitly configured buildx builder." >&2
  exit 2
fi

if ! docker_cmd image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
  if [[ -n "${APEX_ROS_BASE_IMAGE_TAR:-}" ]]; then
    docker_cmd load --input "${APEX_ROS_BASE_IMAGE_TAR}"
  else
    echo "Base image ${BASE_IMAGE} is not cached; pulling it now."
    if ! docker_cmd pull "${BASE_IMAGE}"; then
      echo "ERROR: base image pull failed." >&2
      echo "For an offline deployment, copy a docker-save archive to this host and set:" >&2
      echo "  APEX_ROS_BASE_IMAGE_TAR=/path/ros-humble-arm64.tar $0" >&2
      exit 3
    fi
  fi
fi

docker_cmd build \
  --progress plain \
  --network "${APEX_DOCKER_BUILD_NETWORK:-default}" \
  --file "${DOCKERFILE}" \
  --build-arg "ROS_BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg "APEX_PIP_INDEX_URL=${PIP_INDEX_URL}" \
  --tag "${IMAGE}" \
  "${REPO_DIR}"

docker_cmd image inspect "${IMAGE}" --format 'Built {{.RepoTags}} arch={{.Architecture}} size={{.Size}}'

if [[ -n "${APEX_BACKEND_IMAGE_TAR_OUT:-}" ]]; then
  save_image "${APEX_BACKEND_IMAGE_TAR_OUT}"
  echo "Saved image archive: ${APEX_BACKEND_IMAGE_TAR_OUT}"
fi
