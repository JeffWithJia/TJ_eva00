#!/usr/bin/env bash
# Shared helpers for the Apex install scripts. Sourced by
# install_systemd_services.sh; expects ENV_FILE to point at apex.env.

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

existing_env_value() {
  local key="$1"
  if [[ -r "${ENV_FILE}" ]]; then
    grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2- || true
  fi
}

detect_ros_setup() {
  if [[ -n "${ROS_DISTRO:-}" && -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    printf '%s\n' "/opt/ros/${ROS_DISTRO}/setup.bash"
    return 0
  fi
  local setup
  for setup in /opt/ros/jazzy/setup.bash /opt/ros/humble/setup.bash /opt/ros/*/setup.bash; do
    if [[ -f "${setup}" ]]; then
      printf '%s\n' "${setup}"
      return 0
    fi
  done
  return 1
}

strip_cidr() {
  local value="$1"
  echo "${value%/*}"
}

validate_ipv4() {
  local ip="$1"
  local o1 o2 o3 o4
  IFS=. read -r o1 o2 o3 o4 <<<"${ip}"
  for octet in "${o1}" "${o2}" "${o3}" "${o4}"; do
    if [[ ! "${octet}" =~ ^[0-9]+$ ]] || ((10#${octet} > 255)); then
      return 1
    fi
  done
  [[ -n "${o1}" && -n "${o2}" && -n "${o3}" && -n "${o4}" ]]
}

resolve_robot_config_file() {
  local config_dir="$1"
  local robot_platform="${2,,}"
  local robot_model="${3,,}"

  case "${robot_platform}:${robot_model}" in
    gento:luna)
      echo "${config_dir}/robot_param_luna.yaml"
      ;;
    gento:luna_v3|gento:lunav3)
      echo "${config_dir}/robot_param_luna_v3.yaml"
      ;;
    gento:skye_v2_920|gento:skye_v2|gento:skyev2|gento:skye920|gento:gento_skye_v2|gento:gento_skye_v2_920)
      echo "${config_dir}/robot_param_skye_v2_920.yaml"
      ;;
    gento:sky|gento:skye)
      echo "${config_dir}/robot_param_skye.yaml"
      ;;
    pro:*)
      echo "${config_dir}/robot_param_common.yaml"
      ;;
    *)
      echo "Unsupported robot platform/model for robot_ip config: ${robot_platform}/${robot_model}" >&2
      return 2
      ;;
  esac
}

write_robot_ip_yaml() {
  local config_file="$1"
  local robot_ip="$2"
  if [[ ! -f "${config_file}" ]]; then
    echo "Robot control config not found: ${config_file}" >&2
    return 2
  fi
  if ! validate_ipv4 "${robot_ip}"; then
    echo "Invalid robot IP: ${robot_ip}." >&2
    return 2
  fi
  if ! grep -q -E "^[[:space:]]*robot_ip:" "${config_file}"; then
    echo "robot_ip key not found in robot control config: ${config_file}" >&2
    return 2
  fi
  as_root sed -i -E \
    "s|^([[:space:]]*robot_ip:[[:space:]]*).*|\\1${robot_ip}|" \
    "${config_file}"
}

write_camera_platform_yaml() {
  local config_file="$1"
  local compute_platform="${2,,}"
  local robot_platform="${3,,}"
  local wrist_camera="${4,,}"

  if [[ ! -f "${config_file}" ]]; then
    echo "GMSL camera config not found: ${config_file}" >&2
    return 2
  fi

  case "${compute_platform}" in
    orin|thor)
      ;;
    *)
      echo "Unsupported compute platform for GMSL camera config: ${compute_platform}." >&2
      return 2
      ;;
  esac

  case "${robot_platform}" in
    pro|gento)
      ;;
    *)
      echo "Unsupported robot platform for GMSL camera config: ${robot_platform}." >&2
      return 2
      ;;
  esac

  case "${wrist_camera}" in
    d405|d405ga)
      wrist_camera="d405ga"
      ;;
    sh5|shw5g)
      wrist_camera="shw5g"
      ;;
    *)
      echo "Unsupported wrist camera: ${wrist_camera}. Valid values: d405ga, shw5g." >&2
      return 2
      ;;
  esac

  # Keep comments and unrelated tuning in the deployment YAML.  Only the four
  # slot bindings, profiles and platform-dependent mounting flips are changed.
  as_root python3 - \
    "${config_file}" "${compute_platform}" "${robot_platform}" "${wrist_camera}" <<'PY'
import os
import re
import sys
import tempfile

import yaml


path, compute, robot, wrist = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    lines = stream.readlines()

if wrist == "d405ga":
    if compute == "orin":
        wrist_slots = {
            "wrist_left": ("d405", "/dev/video5", "/dev/video4"),
            "wrist_right": ("d405", "/dev/video7", "/dev/video6"),
        }
    else:
        wrist_slots = {
            "wrist_left": ("d405", "/dev/video4", "/dev/video2"),
            "wrist_right": ("d405", "/dev/video11", "/dev/video9"),
        }
elif compute == "orin":
    wrist_slots = {
        "wrist_left": ("sh5", "csi://4", None),
        "wrist_right": ("sh5", "csi://5", None),
    }
else:
    wrist_slots = {
        "wrist_left": ("sh5", "csi://2", None),
        "wrist_right": ("sh5", "csi://3", None),
    }

if robot == "pro" and wrist == "shw5g":
    # Tianzhun Pro with four SH5 cameras requires all four streams rotated.
    flips = {"head_left": True, "head_right": True,
             "wrist_left": True, "wrist_right": True}
elif robot == "pro":
    flips = {"head_left": False, "head_right": False,
             "wrist_left": False, "wrist_right": False}
else:
    flips = {"head_left": False, "head_right": False,
             "wrist_left": True, "wrist_right": True}
slots = {
    "head_left": ("sh5", "csi://0", None),
    "head_right": ("sh5", "csi://1", None),
    **wrist_slots,
}

slot_header = re.compile(r"^      (head_left|head_right|wrist_left|wrist_right):\s*(?:#.*)?$")
field_line = re.compile(r"^        (profile|source|depth_source|flip_method):")
starts = [(index, slot_header.match(line.rstrip("\n")).group(1))
          for index, line in enumerate(lines)
          if slot_header.match(line.rstrip("\n"))]
if {slot for _, slot in starts} != set(slots):
    raise SystemExit(f"camera slots not found in {path}")

for position in range(len(starts) - 1, -1, -1):
    start, slot = starts[position]
    end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
    # Stop before the next sibling of camera: (for example mosaic:).
    for index in range(start + 1, end):
        stripped = lines[index].strip()
        indent = len(lines[index]) - len(lines[index].lstrip(" "))
        if stripped and not stripped.startswith("#") and indent <= 4:
            end = index
            break

    profile, source, depth_source = slots[slot]
    desired = {
        "profile": f'        profile: "{profile}"\n',
        "source": f'        source: "{source}"\n',
        "flip_method": f'        flip_method: {str(flips[slot]).lower()}\n',
    }
    if depth_source is not None:
        desired["depth_source"] = f'        depth_source: "{depth_source}"\n'

    seen = set()
    rewritten = [lines[start]]
    for line in lines[start + 1:end]:
        match = field_line.match(line)
        if not match:
            rewritten.append(line)
            continue
        field = match.group(1)
        if field == "depth_source" and depth_source is None:
            continue
        if field in desired:
            rewritten.append(desired[field])
            seen.add(field)
        else:
            rewritten.append(line)
    for field in ("profile", "source", "depth_source", "flip_method"):
        if field in desired and field not in seen:
            rewritten.append(desired[field])
    lines[start:end] = rewritten

document = yaml.safe_load("".join(lines))
camera = document["quad_csi_quickview"]["ros__parameters"]["camera"]
for slot, (profile, source, depth_source) in slots.items():
    assert camera[slot]["profile"] == profile
    assert camera[slot]["source"] == source
    assert camera[slot]["flip_method"] is flips[slot]
    if depth_source is None:
        assert "depth_source" not in camera[slot]
    else:
        assert camera[slot]["depth_source"] == depth_source

directory = os.path.dirname(os.path.abspath(path))
fd, temporary = tempfile.mkstemp(prefix=".quad_quickview.", dir=directory, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.writelines(lines)
    os.chmod(temporary, os.stat(path).st_mode & 0o777)
    os.replace(temporary, path)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
}

derive_dnsmasq_network() {
  local host_ip="$1"
  local o1 o2 o3 o4
  IFS=. read -r o1 o2 o3 o4 <<<"${host_ip}"
  if ! validate_ipv4 "${host_ip}"; then
    echo "Invalid dnsmasq host IP: ${host_ip}. Use a /24 host IP with last octet 1..253." >&2
    exit 2
  fi

  o1=$((10#${o1}))
  o2=$((10#${o2}))
  o3=$((10#${o3}))
  o4=$((10#${o4}))
  if ((o4 <= 0 || o4 >= 254)); then
    echo "Invalid dnsmasq host IP: ${host_ip}. Use a /24 host IP with last octet 1..253." >&2
    exit 2
  fi

  DNSMASQ_HOST_CIDR_VALUE="${host_ip}/24"
  DNSMASQ_DHCP_START_VALUE="${o1}.${o2}.${o3}.$((o4 + 1))"
  local dhcp_end_octet=$((o4 + 21))
  if ((dhcp_end_octet > 254)); then
    dhcp_end_octet=254
  fi
  DNSMASQ_DHCP_END_VALUE="${o1}.${o2}.${o3}.${dhcp_end_octet}"
}

derive_robot_ip() {
  local host_ip="$1"
  local o1 o2 o3 o4
  IFS=. read -r o1 o2 o3 o4 <<<"${host_ip}"
  if ! validate_ipv4 "${host_ip}"; then
    echo "Invalid host IP for robot IP derivation: ${host_ip}." >&2
    exit 2
  fi
  echo "$((10#${o1})).$((10#${o2})).$((10#${o3})).190"
}

# ── apex.env generation ───────────────────────────────────────────────────────
# The installer resolves every key to its final value with set_env_value, then
# write_apex_env regenerates the file from a fixed, commented template. Keys
# found in an existing apex.env that are not part of the template survive in a
# trailing "Custom" section, so manual additions are never lost.

declare -A _APEX_ENV_VALUES=()
declare -A _APEX_ENV_MANIFEST=()

set_env_value() {
  _APEX_ENV_VALUES["$1"]="$2"
}

_emit_env_section() {
  local title="$1"
  shift
  printf '\n## %s\n' "${title}"
  local key
  for key in "$@"; do
    _APEX_ENV_MANIFEST["${key}"]=1
    if [[ -v "_APEX_ENV_VALUES[${key}]" ]]; then
      printf '%s=%s\n' "${key}" "${_APEX_ENV_VALUES[${key}]}"
    fi
  done
}

_emit_custom_section() {
  local env_file="$1"
  [[ -r "${env_file}" ]] || return 0
  local header_printed=0 line key
  declare -A seen=()
  while IFS= read -r line; do
    [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    [[ -v "_APEX_ENV_MANIFEST[${key}]" ]] && continue
    [[ -v "seen[${key}]" ]] && continue
    seen["${key}"]=1
    if ((header_printed == 0)); then
      printf '\n## Custom (preserved from previous apex.env)\n'
      header_printed=1
    fi
    # Keep the last occurrence, matching existing_env_value semantics.
    grep -E "^${key}=" "${env_file}" | tail -n 1
  done <"${env_file}"
}

write_apex_env() {
  local env_file="$1"
  local tmp
  tmp="$(mktemp)"
  {
    printf '# Apex runtime environment. Generated by install_systemd_services.sh.\n'
    printf '# Values here survive reinstalls; defaults live in apex_env_defaults.sh.\n'
    printf '# Edit and restart the apex-* services (or re-run the installer).\n'
    _emit_env_section "Run user" \
      HOME BAG_STORAGE_ROOT
    _emit_env_section "ROS / workspace" \
      APEX_ROS_SETUP APEX_WS_SETUP APEX_ROS_NAMESPACE ROS_DOMAIN_ID ROS_LOCALHOST_ONLY ROS_LOG_DIR \
      APEX_DDS
    _emit_env_section "Backend" \
      APEX_BACKEND_HOST APEX_BACKEND_PORT
    _emit_env_section "Robot" \
      APEX_ROBOT_PLATFORM APEX_COMPUTE_PLATFORM APEX_ROBOT_MODEL APEX_WRIST_CAMERA \
      APEX_TOOL_TYPE APEX_ROBOT_IP APEX_STAND_SHOULDER_WIDTH_M APEX_STAND_HEIGHT_M
    _emit_env_section "Teleop" \
      APEX_TELEOP_MODE
    _emit_env_section "Python" \
      PYTHONPATH PYTHONNOUSERSITE
    _emit_env_section "DNSMasq" \
      APEX_ENABLE_DNSMASQ APEX_DNSMASQ_INTERFACE APEX_DNSMASQ_HOST_IP \
      APEX_DNSMASQ_HOST_CIDR APEX_DNSMASQ_DHCP_START APEX_DNSMASQ_DHCP_END \
      APEX_DNSMASQ_LEASE_TIME
    _emit_custom_section "${env_file}"
  } >"${tmp}"
  as_root install -m 0644 "${tmp}" "${env_file}"
  rm -f "${tmp}"
}

write_dnsmasq_conf() {
  local conf_file="$1" interface="$2" host_cidr="$3"
  local dhcp_start="$4" dhcp_end="$5" lease_time="$6"
  as_root tee "${conf_file}" >/dev/null <<EOF
# Generated by Apex install_systemd_services.sh
interface=${interface}
bind-interfaces
port=0
dhcp-authoritative
dhcp-range=${dhcp_start},${dhcp_end},${lease_time}
dhcp-option=3,${host_cidr%/*}
log-dhcp
EOF
}
