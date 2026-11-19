#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "${SCRIPT_DIR}/../systemd" && pwd)"
ENV_DIR="${APEX_ETC_DIR:-/etc/apex}"
ENV_FILE="${ENV_DIR}/apex.env"

# Shared helpers (as_root, existing_env_value, derive_*, write_apex_env, ...)
# and the central default values. Change a default in apex_env_defaults.sh,
# not here.
# shellcheck source=apex_env_lib.sh
source "${SCRIPT_DIR}/apex_env_lib.sh"
# shellcheck source=apex_env_defaults.sh
source "${SCRIPT_DIR}/apex_env_defaults.sh"

if [[ -n "${APEX_RUN_USER:-}" ]]; then
  RUN_USER="${APEX_RUN_USER}"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  RUN_USER="${SUDO_USER}"
elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
  RUN_USER="${USER}"
else
  # Unattended install as plain root: fall back to the primary login user
  # (uid 1000) instead of assuming a hardcoded username.
  RUN_USER="$(getent passwd 1000 | cut -d: -f1)"
  if [[ -z "${RUN_USER}" ]]; then
    echo "Cannot determine run user; set APEX_RUN_USER and retry." >&2
    exit 2
  fi
fi
if ! id "${RUN_USER}" >/dev/null 2>&1; then
  echo "Run user does not exist: ${RUN_USER}" >&2
  exit 2
fi
RUN_GROUP="$(id -gn "${RUN_USER}")"
RUN_HOME="$(getent passwd "${RUN_USER}" | cut -d: -f6)"
RUN_HOME="${RUN_HOME:-/home/${RUN_USER}}"
ROS_LOG_DIR_VALUE="${DEFAULT_ROS_LOG_DIR}"
SUDOERS_FILE="/etc/sudoers.d/apex-${RUN_USER}"
ROBOT_PLATFORM_FROM_ARG=0
COMPUTE_PLATFORM_FROM_ARG=0
ROBOT_MODEL_FROM_ARG=0
STAND_SHOULDER_WIDTH_FROM_ARG=0
STAND_HEIGHT_FROM_ARG=0
WRIST_CAMERA_FROM_ARG=0
ROBOT_IP_FROM_ARG=0
ROBOT_IP_FROM_ENV=0
TOOL_TYPE_FROM_ARG=0
TELEOP_MODE_FROM_ARG=0
DDS_FROM_ARG=0
ROS_DOMAIN_ID_FROM_ARG=0
ROS_LOCALHOST_ONLY_FROM_ARG=0
DNSMASQ_INTERFACE_FROM_ARG=0
DNSMASQ_HOST_IP_FROM_ARG=0
DNSMASQ_LEASE_TIME_FROM_ARG=0

robot_config_file() {
  local config_dir="${APEX_MARVIN_ROS_CONTROL_CONFIG_DIR:-/opt/kernelmind/apex/install/marvin_ros_control/share/marvin_ros_control/config}"
  resolve_robot_config_file \
    "${config_dir}" "${ROBOT_PLATFORM_VALUE}" "${ROBOT_MODEL_VALUE}"
}

update_robot_ip_yaml() {
  local config_file
  config_file="$(robot_config_file)"
  write_robot_ip_yaml "${config_file}" "${ROBOT_IP_VALUE}"
}

camera_config_file() {
  echo "${APEX_GMSL_CAMERA_CONFIG:-/opt/kernelmind/apex/install/gmsl_quadcam/share/gmsl_quadcam/config/quad_quickview.yaml}"
}

update_camera_platform_yaml() {
  local config_file
  config_file="$(camera_config_file)"
  write_camera_platform_yaml \
    "${config_file}" "${COMPUTE_PLATFORM_VALUE}" "${ROBOT_PLATFORM_VALUE}" \
    "${WRIST_CAMERA_VALUE}"
}

find_apex_tool_share_dir() {
  local candidate
  local candidates=(
    "${APEX_TOOL_SHARE_DIR:-}"
    "/home/${SUDO_USER:-${USER:-marvin}}/apex_tool/src/Apex_Tools/apex_tool"
    "${SCRIPT_DIR}/../../../../apex_tool/share/apex_tool"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
      cd "${candidate}" && pwd
      return 0
    fi
  done

  echo "Cannot find apex_tool share directory. Build apex_tool or set APEX_TOOL_SHARE_DIR." >&2
  return 1
}

# Prints a numbered menu of $options and stores the chosen option in $__resultvar.
# Usage: prompt_select RESULT_VAR "Prompt title" "current_value" opt1 opt2 ...
prompt_select() {
  local __resultvar="$1"
  local prompt_label="$2"
  local current_value="$3"
  shift 3
  local options=("$@")
  local default_index=1
  local i
  echo "${prompt_label}"
  for i in "${!options[@]}"; do
    local marker=""
    if [[ "${options[$i]}" == "${current_value}" ]]; then
      default_index=$((i + 1))
      marker="  (current)"
    fi
    echo "  $((i + 1))) ${options[$i]}${marker}"
  done
  local choice
  read -r -p "Enter choice [${default_index}]: " choice
  choice="${choice:-${default_index}}"
  if [[ ! "${choice}" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#options[@]})); then
    echo "Invalid selection: ${choice}. Enter a number between 1 and ${#options[@]}." >&2
    exit 2
  fi
  printf -v "${__resultvar}" '%s' "${options[$((choice - 1))]}"
}

# Resolve every value as: explicit override > existing apex.env value > default.
ROS_DOMAIN_ID_VALUE="${ROS_DOMAIN_ID:-$(existing_env_value ROS_DOMAIN_ID)}"
ROS_DOMAIN_ID_VALUE="${ROS_DOMAIN_ID_VALUE:-${DEFAULT_ROS_DOMAIN_ID}}"
ROS_LOCALHOST_ONLY_VALUE="${ROS_LOCALHOST_ONLY:-$(existing_env_value ROS_LOCALHOST_ONLY)}"
ROS_LOCALHOST_ONLY_VALUE="${ROS_LOCALHOST_ONLY_VALUE:-${DEFAULT_ROS_LOCALHOST_ONLY}}"
ROS_NAMESPACE_VALUE="${APEX_ROS_NAMESPACE:-$(existing_env_value APEX_ROS_NAMESPACE)}"
ROS_NAMESPACE_VALUE="${ROS_NAMESPACE_VALUE:-${DEFAULT_APEX_ROS_NAMESPACE}}"
ROBOT_PLATFORM_VALUE="${APEX_ROBOT_PLATFORM:-$(existing_env_value APEX_ROBOT_PLATFORM)}"
ROBOT_PLATFORM_VALUE="${ROBOT_PLATFORM_VALUE:-${DEFAULT_APEX_ROBOT_PLATFORM}}"
COMPUTE_PLATFORM_VALUE="${APEX_COMPUTE_PLATFORM:-$(existing_env_value APEX_COMPUTE_PLATFORM)}"
COMPUTE_PLATFORM_VALUE="${COMPUTE_PLATFORM_VALUE:-}"
ROBOT_MODEL_VALUE="${APEX_ROBOT_MODEL:-$(existing_env_value APEX_ROBOT_MODEL)}"
ROBOT_MODEL_VALUE="${ROBOT_MODEL_VALUE:-}"
STAND_SHOULDER_WIDTH_VALUE="${APEX_STAND_SHOULDER_WIDTH_M:-$(existing_env_value APEX_STAND_SHOULDER_WIDTH_M)}"
STAND_HEIGHT_VALUE="${APEX_STAND_HEIGHT_M:-$(existing_env_value APEX_STAND_HEIGHT_M)}"
WRIST_CAMERA_VALUE="${APEX_WRIST_CAMERA:-$(existing_env_value APEX_WRIST_CAMERA)}"
WRIST_CAMERA_VALUE="${WRIST_CAMERA_VALUE:-${DEFAULT_APEX_WRIST_CAMERA}}"
ROBOT_IP_VALUE="${APEX_ROBOT_IP:-$(existing_env_value APEX_ROBOT_IP)}"
if [[ -n "${APEX_ROBOT_IP:-}" ]]; then
  ROBOT_IP_FROM_ENV=1
fi
TOOL_TYPE_VALUE="${APEX_TOOL_TYPE:-$(existing_env_value APEX_TOOL_TYPE)}"
TOOL_TYPE_VALUE="${TOOL_TYPE_VALUE:-none}"
TELEOP_MODE_VALUE="${APEX_TELEOP_MODE:-$(existing_env_value APEX_TELEOP_MODE)}"
TELEOP_MODE_VALUE="${TELEOP_MODE_VALUE:-${DEFAULT_APEX_TELEOP_MODE}}"
DDS_VALUE="${APEX_DDS:-$(existing_env_value APEX_DDS)}"
DDS_VALUE="${DDS_VALUE:-${DEFAULT_APEX_DDS}}"
DNSMASQ_INTERFACE_VALUE="${APEX_DNSMASQ_INTERFACE:-$(existing_env_value APEX_DNSMASQ_INTERFACE)}"
DNSMASQ_INTERFACE_VALUE="${DNSMASQ_INTERFACE_VALUE:-${DEFAULT_APEX_DNSMASQ_INTERFACE}}"
DNSMASQ_HOST_IP_VALUE="${APEX_DNSMASQ_HOST_IP:-$(existing_env_value APEX_DNSMASQ_HOST_IP)}"
DNSMASQ_HOST_IP_VALUE="${DNSMASQ_HOST_IP_VALUE:-$(strip_cidr "${APEX_DNSMASQ_HOST_CIDR:-$(existing_env_value APEX_DNSMASQ_HOST_CIDR)}")}"
DNSMASQ_HOST_IP_VALUE="${DNSMASQ_HOST_IP_VALUE:-${DEFAULT_APEX_DNSMASQ_HOST_IP}}"
DNSMASQ_LEASE_TIME_VALUE="${APEX_DNSMASQ_LEASE_TIME:-$(existing_env_value APEX_DNSMASQ_LEASE_TIME)}"
DNSMASQ_LEASE_TIME_VALUE="${DNSMASQ_LEASE_TIME_VALUE:-${DEFAULT_APEX_DNSMASQ_LEASE_TIME}}"
ENABLE_DNSMASQ_VALUE="${APEX_ENABLE_DNSMASQ:-$(existing_env_value APEX_ENABLE_DNSMASQ)}"
ENABLE_DNSMASQ_VALUE="${ENABLE_DNSMASQ_VALUE:-${DEFAULT_APEX_ENABLE_DNSMASQ}}"
ROS_SETUP_VALUE="${APEX_ROS_SETUP:-$(existing_env_value APEX_ROS_SETUP)}"
ROS_SETUP_VALUE="${ROS_SETUP_VALUE:-$(detect_ros_setup || true)}"
ROS_SETUP_VALUE="${ROS_SETUP_VALUE:-${DEFAULT_APEX_ROS_SETUP}}"
WS_SETUP_VALUE="${APEX_WS_SETUP:-$(existing_env_value APEX_WS_SETUP)}"
WS_SETUP_VALUE="${WS_SETUP_VALUE:-${DEFAULT_APEX_WS_SETUP}}"
BACKEND_HOST_VALUE="$(existing_env_value APEX_BACKEND_HOST)"
BACKEND_HOST_VALUE="${BACKEND_HOST_VALUE:-${DEFAULT_APEX_BACKEND_HOST}}"
BACKEND_PORT_VALUE="$(existing_env_value APEX_BACKEND_PORT)"
BACKEND_PORT_VALUE="${BACKEND_PORT_VALUE:-${DEFAULT_APEX_BACKEND_PORT}}"
# Bag storage lives on the removable drive mounted under the run user's /media,
# so pin the root to the actual install user (not a hardcoded marvin). Override
# with APEX_BAG_STORAGE_ROOT to point elsewhere.
BAG_STORAGE_ROOT_VALUE="${APEX_BAG_STORAGE_ROOT:-/media/${RUN_USER}/BAG_STORAGE}"

usage() {
  cat <<'EOF'
Usage: install_systemd_services.sh [options]

Options:
  --robot-platform gento|pro
                          Select systemd launch platform written to /etc/apex/apex.env.
  --compute-platform orin|thor
                          Select compute platform written to /etc/apex/apex.env.
  --robot-model MODEL      Set robot model written to /etc/apex/apex.env.
                          For Gento: luna|luna_v3|skye|skye_v2_920. For pro: pro_arm_base, e.g. pro_m6s_696_new.
                          base: legacy|new|m6stand|m6litestand|user. arm: m6s_696|m3s_615|m6s_lite_615|m6s_lite_680|m6s_lite_750|m6s_809.
                          m6stand/m6litestand are fixed CAD stand profiles; user uses customer dimensions.
  --stand-shoulder-width-m METRES
                          Joint1 axis center distance; required for the user stand.
  --stand-height-m METRES  Ground-to-Joint1 axis height; required for the user stand.
  --wrist-camera d405ga|shw5g
                          Select the two wrist cameras. SHW5G uses CSI 4/5 on
                          Orin (Tianzun) and CSI 2/3 on Thor (Lingjing).
                          D405GA uses depth/color 4/5 and 6/7 on Orin, and
                          depth/color 2/4 and 9/11 on Thor.
  --robot-ip IP            Set APEX_ROBOT_IP and the selected robot config's robot_ip.
  --tool-type dm|zy|wuji|none
                          Deprecated for the base package. kernelmind-apex-tool owns APEX_TOOL_TYPE.
  --teleop-mode controller|dexhand
                          Set teleoperation input mode written to /etc/apex/apex.env.
  --dds fastdds|cyclone    Select the ROS 2 DDS implementation written to /etc/apex/apex.env.
                          cyclone uses /etc/apex/cyclonedds.xml (installed once, edits preserved).
  --ros-domain-id ID        Set ROS_DOMAIN_ID written to /etc/apex/apex.env.
  --ros-localhost-only 0|1  Set ROS_LOCALHOST_ONLY written to /etc/apex/apex.env.
  --ros-namespace NAME      Set the Apex ROS namespace (default: tj).
  --dnsmasq-interface IFACE Set interface used by apex-dnsmasq.service.
  --dnsmasq-host-ip IP      Set host interface IP. /24 mask is fixed and DHCP range is derived.
  --dnsmasq-lease-time TIME Set DHCP lease time, e.g. 12h.
  -h, --help                Show this help.

Environment overrides:
  APEX_ROBOT_PLATFORM
  APEX_COMPUTE_PLATFORM
  APEX_ROBOT_MODEL
  APEX_STAND_SHOULDER_WIDTH_M
  APEX_STAND_HEIGHT_M
  APEX_WRIST_CAMERA
  APEX_ROBOT_IP
  APEX_TOOL_TYPE
  APEX_TELEOP_MODE
  APEX_DDS
  APEX_BAG_STORAGE_ROOT
  ROS_DOMAIN_ID
  ROS_LOCALHOST_ONLY
  APEX_ROS_NAMESPACE
  APEX_DNSMASQ_INTERFACE
  APEX_DNSMASQ_HOST_IP
  APEX_DNSMASQ_HOST_CIDR
  APEX_DNSMASQ_LEASE_TIME

Defaults live in apex_env_defaults.sh next to this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --robot-platform)
      ROBOT_PLATFORM_VALUE="${2:?missing value for --robot-platform}"
      ROBOT_PLATFORM_FROM_ARG=1
      shift 2
      ;;
    --compute-platform)
      COMPUTE_PLATFORM_VALUE="${2:?missing value for --compute-platform}"
      COMPUTE_PLATFORM_FROM_ARG=1
      shift 2
      ;;
    --robot-model)
      ROBOT_MODEL_VALUE="${2:?missing value for --robot-model}"
      ROBOT_MODEL_FROM_ARG=1
      shift 2
      ;;
    --stand-shoulder-width-m)
      STAND_SHOULDER_WIDTH_VALUE="${2:?missing value for --stand-shoulder-width-m}"
      STAND_SHOULDER_WIDTH_FROM_ARG=1
      shift 2
      ;;
    --stand-height-m)
      STAND_HEIGHT_VALUE="${2:?missing value for --stand-height-m}"
      STAND_HEIGHT_FROM_ARG=1
      shift 2
      ;;
    --wrist-camera)
      WRIST_CAMERA_VALUE="${2:?missing value for --wrist-camera}"
      WRIST_CAMERA_FROM_ARG=1
      shift 2
      ;;
    --robot-ip)
      ROBOT_IP_VALUE="${2:?missing value for --robot-ip}"
      ROBOT_IP_FROM_ARG=1
      shift 2
      ;;
    --tool-type)
      TOOL_TYPE_VALUE="${2:?missing value for --tool-type}"
      TOOL_TYPE_FROM_ARG=1
      shift 2
      ;;
    --teleop-mode)
      TELEOP_MODE_VALUE="${2:?missing value for --teleop-mode}"
      TELEOP_MODE_FROM_ARG=1
      shift 2
      ;;
    --dds)
      DDS_VALUE="${2:?missing value for --dds}"
      DDS_FROM_ARG=1
      shift 2
      ;;
    --ros-domain-id)
      ROS_DOMAIN_ID_VALUE="${2:?missing value for --ros-domain-id}"
      ROS_DOMAIN_ID_FROM_ARG=1
      shift 2
      ;;
    --ros-localhost-only)
      ROS_LOCALHOST_ONLY_VALUE="${2:?missing value for --ros-localhost-only}"
      ROS_LOCALHOST_ONLY_FROM_ARG=1
      shift 2
      ;;
    --ros-namespace)
      ROS_NAMESPACE_VALUE="${2:?missing value for --ros-namespace}"
      shift 2
      ;;
    --dnsmasq-interface)
      DNSMASQ_INTERFACE_VALUE="${2:?missing value for --dnsmasq-interface}"
      DNSMASQ_INTERFACE_FROM_ARG=1
      shift 2
      ;;
    --dnsmasq-host-ip)
      DNSMASQ_HOST_IP_VALUE="${2:?missing value for --dnsmasq-host-ip}"
      DNSMASQ_HOST_IP_FROM_ARG=1
      shift 2
      ;;
    --dnsmasq-host-cidr)
      DNSMASQ_HOST_IP_VALUE="$(strip_cidr "${2:?missing value for --dnsmasq-host-cidr}")"
      DNSMASQ_HOST_IP_FROM_ARG=1
      shift 2
      ;;
    --dnsmasq-dhcp-start)
      echo "Ignoring deprecated --dnsmasq-dhcp-start; DHCP range is derived from host IP." >&2
      shift 2
      ;;
    --dnsmasq-dhcp-end)
      echo "Ignoring deprecated --dnsmasq-dhcp-end; DHCP range is derived from host IP." >&2
      shift 2
      ;;
    --dnsmasq-lease-time)
      DNSMASQ_LEASE_TIME_VALUE="${2:?missing value for --dnsmasq-lease-time}"
      DNSMASQ_LEASE_TIME_FROM_ARG=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ROBOT_PLATFORM_VALUE="$(echo "${ROBOT_PLATFORM_VALUE}" | tr '[:upper:]' '[:lower:]')"
case "${ROBOT_PLATFORM_VALUE}" in
  gento|pro) ;;
  *)
    echo "Unsupported robot platform: ${ROBOT_PLATFORM_VALUE}. Valid values: gento, pro." >&2
    exit 2
    ;;
esac

if [[ "${ROBOT_PLATFORM_FROM_ARG}" -eq 0 && -t 0 ]]; then
  prompt_select ROBOT_PLATFORM_VALUE "Select APEX_ROBOT_PLATFORM:" "${ROBOT_PLATFORM_VALUE}" gento pro
fi

COMPUTE_PLATFORM_VALUE="$(echo "${COMPUTE_PLATFORM_VALUE}" | tr '[:upper:]' '[:lower:]')"
COMPUTE_PLATFORM_VALUE="${COMPUTE_PLATFORM_VALUE:-${DEFAULT_APEX_COMPUTE_PLATFORM}}"
case "${COMPUTE_PLATFORM_VALUE}" in
  orin|thor) ;;
  *)
    echo "Unsupported compute platform: ${COMPUTE_PLATFORM_VALUE}. Valid values: orin, thor." >&2
    exit 2
    ;;
esac
if [[ "${COMPUTE_PLATFORM_FROM_ARG}" -eq 0 && -t 0 ]]; then
  prompt_select COMPUTE_PLATFORM_VALUE "Select APEX_COMPUTE_PLATFORM:" "${COMPUTE_PLATFORM_VALUE}" orin thor
fi

ROBOT_MODEL_VALUE="$(echo "${ROBOT_MODEL_VALUE}" | tr '[:upper:]' '[:lower:]')"
case "${ROBOT_MODEL_VALUE}" in
  sky) ROBOT_MODEL_VALUE="skye" ;;
  lunav3) ROBOT_MODEL_VALUE="luna_v3" ;;
  skyev2|skye_v2|skye920|gento_skye_v2|gento_skye_v2_920) ROBOT_MODEL_VALUE="skye_v2_920" ;;
esac
if [[ -z "${ROBOT_MODEL_VALUE}" ]]; then
  if [[ "${ROBOT_PLATFORM_VALUE}" == "gento" ]]; then
    ROBOT_MODEL_VALUE="${DEFAULT_APEX_ROBOT_MODEL_GENTO}"
  else
    ROBOT_MODEL_VALUE="${DEFAULT_APEX_ROBOT_MODEL_PRO}"
  fi
elif [[ "${ROBOT_PLATFORM_VALUE}" == "gento" && "${ROBOT_MODEL_FROM_ARG}" -eq 0 ]]; then
  case "${ROBOT_MODEL_VALUE}" in
    luna|luna_v3|skye|skye_v2_920) ;;
    *)
      ROBOT_MODEL_VALUE="${DEFAULT_APEX_ROBOT_MODEL_GENTO}"
      ;;
  esac
elif [[ "${ROBOT_PLATFORM_VALUE}" != "gento" && "${ROBOT_MODEL_FROM_ARG}" -eq 0 ]]; then
  case "${ROBOT_MODEL_VALUE}" in
    pro_*_*)
      ;;
    *)
      ROBOT_MODEL_VALUE="${DEFAULT_APEX_ROBOT_MODEL_PRO}"
      ;;
  esac
fi
if [[ "${ROBOT_PLATFORM_VALUE}" == "gento" && "${ROBOT_MODEL_VALUE}" != "luna" && "${ROBOT_MODEL_VALUE}" != "luna_v3" && "${ROBOT_MODEL_VALUE}" != "skye" && "${ROBOT_MODEL_VALUE}" != "skye_v2_920" ]]; then
  echo "Unsupported robot model: ${ROBOT_MODEL_VALUE}. Valid values: luna, luna_v3, skye, skye_v2_920." >&2
  exit 2
fi
if [[ "${ROBOT_PLATFORM_VALUE}" != "gento" && ! "${ROBOT_MODEL_VALUE}" =~ ^pro_[a-z0-9_]+_[a-z0-9]+$ ]]; then
  echo "Unsupported robot model: ${ROBOT_MODEL_VALUE}. For ${ROBOT_PLATFORM_VALUE}, use pro_arm_base format, e.g. pro_m6s_696_new." >&2
  exit 2
fi
if [[ "${ROBOT_PLATFORM_VALUE}" != "gento" ]]; then
  BASE_MODEL_CURRENT="${ROBOT_MODEL_VALUE##*_}"
  ROBOT_MODEL_BODY="${ROBOT_MODEL_VALUE#pro_}"
  ARM_MODEL_CURRENT="${ROBOT_MODEL_BODY%_*}"
  case "${BASE_MODEL_CURRENT}" in
    legacy|new|m6stand|m6litestand|user) ;;
    *)
      echo "Unsupported stand model: ${BASE_MODEL_CURRENT}. Valid values: legacy, new, m6stand, m6litestand, user." >&2
      exit 2
      ;;
  esac
  case "${ARM_MODEL_CURRENT}" in
    m6s_696|m3s_615|m6s_lite_615|m6s_lite_680|m6s_lite_750|m6s_809) ;;
    *)
      echo "Unsupported arm model: ${ARM_MODEL_CURRENT}." >&2
      exit 2
      ;;
  esac
fi

if [[ "${ROBOT_PLATFORM_VALUE}" == "gento" && "${ROBOT_MODEL_FROM_ARG}" -eq 0 && -t 0 ]]; then
  prompt_select ROBOT_MODEL_VALUE "Select APEX_ROBOT_MODEL:" "${ROBOT_MODEL_VALUE}" luna luna_v3 skye skye_v2_920
fi
if [[ "${ROBOT_PLATFORM_VALUE}" != "gento" && "${ROBOT_MODEL_FROM_ARG}" -eq 0 && -t 0 ]]; then
  BASE_MODEL_CURRENT="${ROBOT_MODEL_VALUE##*_}"
  ROBOT_MODEL_BODY="${ROBOT_MODEL_VALUE#pro_}"
  ARM_MODEL_CURRENT="${ROBOT_MODEL_BODY%_*}"
  prompt_select BASE_MODEL_SELECTED "Select APEX_BASE_MODEL:" "${BASE_MODEL_CURRENT}" legacy new m6stand m6litestand user
  prompt_select ARM_MODEL_SELECTED "Select APEX_ARM_MODEL:" "${ARM_MODEL_CURRENT}" m6s_696 m3s_615 m6s_lite_615 m6s_lite_680 m6s_lite_750 m6s_809
  ROBOT_MODEL_VALUE="pro_${ARM_MODEL_SELECTED}_${BASE_MODEL_SELECTED}"
  if [[ ! "${ROBOT_MODEL_VALUE}" =~ ^pro_[a-z0-9_]+_[a-z0-9]+$ ]]; then
    echo "Unsupported robot model: ${ROBOT_MODEL_VALUE}. For ${ROBOT_PLATFORM_VALUE}, use pro_arm_base format, e.g. pro_m6s_696_new." >&2
    exit 2
  fi
fi

if [[ "${ROBOT_PLATFORM_VALUE}" != "gento" && "${ROBOT_MODEL_VALUE##*_}" == "user" ]]; then
  if [[ ( -z "${STAND_SHOULDER_WIDTH_VALUE}" || -z "${STAND_HEIGHT_VALUE}" ) && ! -t 0 ]]; then
    echo "The user stand requires --stand-shoulder-width-m and --stand-height-m (or matching APEX_STAND_* environment values)." >&2
    exit 2
  fi
  STAND_SHOULDER_WIDTH_VALUE="${STAND_SHOULDER_WIDTH_VALUE:-0.401}"
  STAND_HEIGHT_VALUE="${STAND_HEIGHT_VALUE:-1.121}"
  if [[ "${STAND_SHOULDER_WIDTH_FROM_ARG}" -eq 0 && -z "${APEX_STAND_SHOULDER_WIDTH_M:-}" && -t 0 ]]; then
    read -r -p "Enter shoulder axis center distance in metres [${STAND_SHOULDER_WIDTH_VALUE}]: " STAND_SHOULDER_WIDTH_INPUT
    STAND_SHOULDER_WIDTH_VALUE="${STAND_SHOULDER_WIDTH_INPUT:-${STAND_SHOULDER_WIDTH_VALUE}}"
  fi
  if [[ "${STAND_HEIGHT_FROM_ARG}" -eq 0 && -z "${APEX_STAND_HEIGHT_M:-}" && -t 0 ]]; then
    read -r -p "Enter ground-to-arm-axis height in metres [${STAND_HEIGHT_VALUE}]: " STAND_HEIGHT_INPUT
    STAND_HEIGHT_VALUE="${STAND_HEIGHT_INPUT:-${STAND_HEIGHT_VALUE}}"
  fi
  if [[ ! "${STAND_SHOULDER_WIDTH_VALUE}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
     ! awk -v value="${STAND_SHOULDER_WIDTH_VALUE}" 'BEGIN { exit !(value > 0) }'; then
    echo "Invalid user stand shoulder width: ${STAND_SHOULDER_WIDTH_VALUE}. Enter positive metres." >&2
    exit 2
  fi
  if [[ ! "${STAND_HEIGHT_VALUE}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
     ! awk -v value="${STAND_HEIGHT_VALUE}" 'BEGIN { exit !(value > 0) }'; then
    echo "Invalid user stand height: ${STAND_HEIGHT_VALUE}. Enter positive metres." >&2
    exit 2
  fi
fi

WRIST_CAMERA_VALUE="$(echo "${WRIST_CAMERA_VALUE}" | tr '[:upper:]' '[:lower:]')"
case "${WRIST_CAMERA_VALUE}" in
  d405|d405ga) WRIST_CAMERA_VALUE="d405ga" ;;
  sh5|shw5g) WRIST_CAMERA_VALUE="shw5g" ;;
  *)
    echo "Unsupported wrist camera: ${WRIST_CAMERA_VALUE}. Valid values: d405ga, shw5g." >&2
    exit 2
    ;;
esac
if [[ "${WRIST_CAMERA_FROM_ARG}" -eq 0 && -z "${APEX_WRIST_CAMERA:-}" && -t 0 ]]; then
  prompt_select WRIST_CAMERA_VALUE "Select APEX_WRIST_CAMERA:" "${WRIST_CAMERA_VALUE}" d405ga shw5g
fi

TOOL_TYPE_VALUE="$(echo "${TOOL_TYPE_VALUE}" | tr '[:upper:]' '[:lower:]')"
case "${TOOL_TYPE_VALUE}" in
  dm|zy|wuji|none) ;;
  *)
    echo "Unsupported tool type: ${TOOL_TYPE_VALUE}. Valid values: dm, zy, wuji, none." >&2
    exit 2
    ;;
esac

TELEOP_MODE_VALUE="$(echo "${TELEOP_MODE_VALUE}" | tr '[:upper:]' '[:lower:]')"
case "${TELEOP_MODE_VALUE}" in
  controller|dexhand) ;;
  *)
    echo "Unsupported teleop mode: ${TELEOP_MODE_VALUE}. Valid values: controller, dexhand." >&2
    exit 2
    ;;
esac

if [[ "${TELEOP_MODE_FROM_ARG}" -eq 0 && -t 0 ]]; then
  prompt_select TELEOP_MODE_VALUE "Select APEX_TELEOP_MODE:" "${TELEOP_MODE_VALUE}" controller dexhand
fi

DDS_VALUE="$(echo "${DDS_VALUE}" | tr '[:upper:]' '[:lower:]')"
case "${DDS_VALUE}" in
  cyclonedds) DDS_VALUE="cyclone" ;;
  fastrtps) DDS_VALUE="fastdds" ;;
esac
case "${DDS_VALUE}" in
  fastdds|cyclone) ;;
  *)
    echo "Unsupported DDS implementation: ${DDS_VALUE}. Valid values: fastdds, cyclone." >&2
    exit 2
    ;;
esac

if [[ "${DDS_FROM_ARG}" -eq 0 && -t 0 ]]; then
  prompt_select DDS_VALUE "Select APEX_DDS:" "${DDS_VALUE}" fastdds cyclone
fi

if [[ "${ROS_DOMAIN_ID_FROM_ARG}" -eq 0 && -t 0 ]]; then
  read -r -p "Enter ROS_DOMAIN_ID [${ROS_DOMAIN_ID_VALUE}]: " ROS_DOMAIN_ID_INPUT
  ROS_DOMAIN_ID_VALUE="${ROS_DOMAIN_ID_INPUT:-${ROS_DOMAIN_ID_VALUE}}"
fi

if [[ "${ROS_LOCALHOST_ONLY_FROM_ARG}" -eq 0 && -t 0 ]]; then
  read -r -p "Enter ROS_LOCALHOST_ONLY (0 or 1) [${ROS_LOCALHOST_ONLY_VALUE}]: " ROS_LOCALHOST_ONLY_INPUT
  ROS_LOCALHOST_ONLY_VALUE="${ROS_LOCALHOST_ONLY_INPUT:-${ROS_LOCALHOST_ONLY_VALUE}}"
fi

ROS_NAMESPACE_VALUE="${ROS_NAMESPACE_VALUE#/}"
ROS_NAMESPACE_VALUE="${ROS_NAMESPACE_VALUE%/}"
if [[ ! "${ROS_NAMESPACE_VALUE}" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "Invalid ROS namespace: ${ROS_NAMESPACE_VALUE}. Use lowercase letters, digits, and underscores." >&2
  exit 2
fi

if [[ "${DNSMASQ_INTERFACE_FROM_ARG}" -eq 0 && -t 0 ]]; then
  read -r -p "Enter dnsmasq interface [${DNSMASQ_INTERFACE_VALUE}]: " DNSMASQ_INTERFACE_INPUT
  DNSMASQ_INTERFACE_VALUE="${DNSMASQ_INTERFACE_INPUT:-${DNSMASQ_INTERFACE_VALUE}}"
fi

if [[ "${DNSMASQ_HOST_IP_FROM_ARG}" -eq 0 && -t 0 ]]; then
  read -r -p "Enter host IP for ${DNSMASQ_INTERFACE_VALUE} (/24) [${DNSMASQ_HOST_IP_VALUE}]: " DNSMASQ_HOST_IP_INPUT
  DNSMASQ_HOST_IP_VALUE="${DNSMASQ_HOST_IP_INPUT:-${DNSMASQ_HOST_IP_VALUE}}"
fi

derive_dnsmasq_network "${DNSMASQ_HOST_IP_VALUE}"
ROBOT_IP_VALUE="${ROBOT_IP_VALUE:-$(derive_robot_ip "${DNSMASQ_HOST_IP_VALUE}")}"
if ! validate_ipv4 "${ROBOT_IP_VALUE}"; then
  echo "Invalid robot IP: ${ROBOT_IP_VALUE}." >&2
  exit 2
fi

if [[ "${ROBOT_IP_FROM_ARG}" -eq 0 && "${ROBOT_IP_FROM_ENV}" -eq 0 ]]; then
  ROBOT_IP_INPUT=""
  if [[ -r /dev/tty && -w /dev/tty ]] &&
      printf "Enter robot IP [%s]: " "${ROBOT_IP_VALUE}" >/dev/tty 2>/dev/null; then
    read -r ROBOT_IP_INPUT </dev/tty || ROBOT_IP_INPUT=""
  elif [[ -t 0 ]]; then
    read -r -p "Enter robot IP [${ROBOT_IP_VALUE}]: " ROBOT_IP_INPUT
  fi
  ROBOT_IP_VALUE="${ROBOT_IP_INPUT:-${ROBOT_IP_VALUE}}"
fi
if ! validate_ipv4 "${ROBOT_IP_VALUE}"; then
  echo "Invalid robot IP: ${ROBOT_IP_VALUE}." >&2
  exit 2
fi

if [[ "${DNSMASQ_LEASE_TIME_FROM_ARG}" -eq 0 && -t 0 ]]; then
  read -r -p "Enter DHCP lease time [${DNSMASQ_LEASE_TIME_VALUE}]: " DNSMASQ_LEASE_TIME_INPUT
  DNSMASQ_LEASE_TIME_VALUE="${DNSMASQ_LEASE_TIME_INPUT:-${DNSMASQ_LEASE_TIME_VALUE}}"
fi

as_root install -d "${ENV_DIR}"
as_root install -d -m 0775 "${ROS_LOG_DIR_VALUE}"
as_root chown "${RUN_USER}:${RUN_GROUP}" "${ROS_LOG_DIR_VALUE}"

# Regenerate /etc/apex/apex.env from the template in apex_env_lib.sh. Keys not
# listed there (manual additions) are preserved in a trailing Custom section.
set_env_value "HOME" "${RUN_HOME}"
set_env_value "BAG_STORAGE_ROOT" "${BAG_STORAGE_ROOT_VALUE}"
set_env_value "APEX_ROS_SETUP" "${ROS_SETUP_VALUE}"
set_env_value "APEX_WS_SETUP" "${WS_SETUP_VALUE}"
set_env_value "APEX_ROS_NAMESPACE" "${ROS_NAMESPACE_VALUE}"
set_env_value "ROS_DOMAIN_ID" "${ROS_DOMAIN_ID_VALUE}"
set_env_value "ROS_LOCALHOST_ONLY" "${ROS_LOCALHOST_ONLY_VALUE}"
set_env_value "ROS_LOG_DIR" "${ROS_LOG_DIR_VALUE}"
set_env_value "APEX_BACKEND_HOST" "${BACKEND_HOST_VALUE}"
set_env_value "APEX_BACKEND_PORT" "${BACKEND_PORT_VALUE}"
set_env_value "APEX_ROBOT_PLATFORM" "${ROBOT_PLATFORM_VALUE}"
set_env_value "APEX_COMPUTE_PLATFORM" "${COMPUTE_PLATFORM_VALUE}"
set_env_value "APEX_ROBOT_MODEL" "${ROBOT_MODEL_VALUE}"
set_env_value "APEX_STAND_SHOULDER_WIDTH_M" "${STAND_SHOULDER_WIDTH_VALUE}"
set_env_value "APEX_STAND_HEIGHT_M" "${STAND_HEIGHT_VALUE}"
set_env_value "APEX_WRIST_CAMERA" "${WRIST_CAMERA_VALUE}"
set_env_value "APEX_TOOL_TYPE" "${TOOL_TYPE_VALUE}"
set_env_value "APEX_TELEOP_MODE" "${TELEOP_MODE_VALUE}"
set_env_value "APEX_DDS" "${DDS_VALUE}"
set_env_value "APEX_ROBOT_IP" "${ROBOT_IP_VALUE}"
# PYTHONPATH is intentionally NOT set globally. Backend-only Python dependencies
# live in its image; Camera prepends only the package-owned camera-python path in
# apex-launch-camera.sh. Injecting ~/.local/site-packages used to leak numpy 2,
# cmeel pinocchio and placo into services and break the ROS Pinocchio 4.0 /
# numpy 1.x ABI.
set_env_value "PYTHONNOUSERSITE" "${DEFAULT_PYTHONNOUSERSITE}"
set_env_value "APEX_ENABLE_DNSMASQ" "${ENABLE_DNSMASQ_VALUE}"
set_env_value "APEX_DNSMASQ_INTERFACE" "${DNSMASQ_INTERFACE_VALUE}"
set_env_value "APEX_DNSMASQ_HOST_IP" "${DNSMASQ_HOST_IP_VALUE}"
set_env_value "APEX_DNSMASQ_HOST_CIDR" "${DNSMASQ_HOST_CIDR_VALUE}"
set_env_value "APEX_DNSMASQ_DHCP_START" "${DNSMASQ_DHCP_START_VALUE}"
set_env_value "APEX_DNSMASQ_DHCP_END" "${DNSMASQ_DHCP_END_VALUE}"
set_env_value "APEX_DNSMASQ_LEASE_TIME" "${DNSMASQ_LEASE_TIME_VALUE}"
write_apex_env "${ENV_FILE}"

update_robot_ip_yaml
update_camera_platform_yaml

write_dnsmasq_conf "${ENV_DIR}/dnsmasq.conf" \
  "${DNSMASQ_INTERFACE_VALUE}" "${DNSMASQ_HOST_CIDR_VALUE}" \
  "${DNSMASQ_DHCP_START_VALUE}" "${DNSMASQ_DHCP_END_VALUE}" \
  "${DNSMASQ_LEASE_TIME_VALUE}"

TOOL_SHARE_DIR=""
if TOOL_SHARE_DIR="$(find_apex_tool_share_dir 2>/dev/null)"; then
  :
else
  echo "apex_tool share directory not found; skipping apex-tool.service installation." >&2
  echo "Install kernelmind-apex-tool to enable the tool service." >&2
fi

if [[ "${APEX_PRESERVE_ROS_ENV:-0}" != "1" ]]; then
  as_root install -m 0644 "${SCRIPT_DIR}/apex_ros_env.sh" "${ENV_DIR}/apex_ros_env.sh"
fi
# CycloneDDS 配置：只在缺失时安装，保留部署机上的本地修改（如显式绑定网卡）。
CYCLONEDDS_XML_SRC="${SCRIPT_DIR}/../config/cyclonedds.xml"
if [[ -f "${CYCLONEDDS_XML_SRC}" && ! -f "${ENV_DIR}/cyclonedds.xml" ]]; then
  as_root install -m 0644 "${CYCLONEDDS_XML_SRC}" "${ENV_DIR}/cyclonedds.xml"
fi
as_root install -m 0755 "${SCRIPT_DIR}/apex-launch-robot.sh" "${ENV_DIR}/apex-launch-robot.sh"
as_root install -m 0755 "${SCRIPT_DIR}/apex-launch-teleop.sh" "${ENV_DIR}/apex-launch-teleop.sh"
as_root install -m 0755 "${SCRIPT_DIR}/apex-launch-camera.sh" "${ENV_DIR}/apex-launch-camera.sh"
as_root install -m 0755 "${SCRIPT_DIR}/apex-configure-camera.sh" "${ENV_DIR}/apex-configure-camera.sh"
BACKEND_SERVICE_MODE="${APEX_BACKEND_SERVICE_MODE:-native}"
if [[ "${BACKEND_SERVICE_MODE}" != "container" ]]; then
  as_root install -m 0644 "${SERVICE_DIR}/apex-backend.service" /etc/systemd/system/apex-backend.service
fi
as_root install -m 0644 "${SERVICE_DIR}/apex-camera.service" /etc/systemd/system/apex-camera.service
as_root install -m 0644 "${SERVICE_DIR}/apex-dnsmasq.service" /etc/systemd/system/apex-dnsmasq.service
as_root install -m 0644 "${SERVICE_DIR}/apex-robot.service" /etc/systemd/system/apex-robot.service
as_root install -m 0644 "${SERVICE_DIR}/apex-teleop.service" /etc/systemd/system/apex-teleop.service
if [[ -n "${TOOL_SHARE_DIR}" ]]; then
  as_root install -m 0755 "${TOOL_SHARE_DIR}/scripts/apex-launch-tool.sh" "${ENV_DIR}/apex-launch-tool.sh"
  as_root install -m 0644 "${TOOL_SHARE_DIR}/systemd/apex-tool.service" /etc/systemd/system/apex-tool.service
fi
for SERVICE_FILE in \
  /etc/systemd/system/apex-camera.service \
  /etc/systemd/system/apex-robot.service \
  /etc/systemd/system/apex-teleop.service; do
  as_root sed -i "s/^User=.*/User=${RUN_USER}/" "${SERVICE_FILE}"
  as_root sed -i "s/^Group=.*/Group=${RUN_GROUP}/" "${SERVICE_FILE}"
  as_root sed -i "s|^WorkingDirectory=.*|WorkingDirectory=${RUN_HOME}|" "${SERVICE_FILE}"
done
if [[ -n "${TOOL_SHARE_DIR}" ]]; then
  as_root sed -i "s/^User=.*/User=${RUN_USER}/" /etc/systemd/system/apex-tool.service
  as_root sed -i "s/^Group=.*/Group=${RUN_GROUP}/" /etc/systemd/system/apex-tool.service
  as_root sed -i "s|^WorkingDirectory=.*|WorkingDirectory=${RUN_HOME}|" /etc/systemd/system/apex-tool.service
fi
as_root systemctl disable --now apex-websocket.service >/dev/null 2>&1 || true
as_root rm -f /etc/systemd/system/apex-websocket.service

if [[ "${BACKEND_SERVICE_MODE}" != "container" ]]; then
  as_root tee "${SUDOERS_FILE}" >/dev/null <<EOF
${RUN_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start apex-camera.service, /usr/bin/systemctl stop apex-camera.service, /usr/bin/systemctl restart apex-camera.service
${RUN_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start apex-dnsmasq.service, /usr/bin/systemctl stop apex-dnsmasq.service, /usr/bin/systemctl restart apex-dnsmasq.service
${RUN_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start apex-robot.service, /usr/bin/systemctl stop apex-robot.service, /usr/bin/systemctl restart apex-robot.service
${RUN_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start apex-teleop.service, /usr/bin/systemctl stop apex-teleop.service, /usr/bin/systemctl restart apex-teleop.service
${RUN_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start apex-tool.service, /usr/bin/systemctl stop apex-tool.service, /usr/bin/systemctl restart apex-tool.service
${RUN_USER} ALL=(root) NOPASSWD: /usr/bin/journalctl *
EOF
  as_root chmod 0440 "${SUDOERS_FILE}"
  as_root visudo -cf "${SUDOERS_FILE}" >/dev/null
else
  # Container Backend controls only allowlisted units through the root-owned
  # Unix socket proxy. Remove broad sudo rules left by native releases.
  as_root rm -f "${SUDOERS_FILE}"
fi

as_root systemctl daemon-reload
if [[ "${BACKEND_SERVICE_MODE}" != "container" ]]; then
  as_root systemctl enable apex-backend.service
fi

echo "Installed Apex systemd services."
echo "RUN_USER=${RUN_USER}"
echo "RUN_GROUP=${RUN_GROUP}"
echo "APEX_ROBOT_PLATFORM=${ROBOT_PLATFORM_VALUE}"
echo "APEX_COMPUTE_PLATFORM=${COMPUTE_PLATFORM_VALUE}"
echo "APEX_ROBOT_MODEL=${ROBOT_MODEL_VALUE}"
if [[ "${ROBOT_PLATFORM_VALUE}" != "gento" && "${ROBOT_MODEL_VALUE##*_}" == "user" ]]; then
  echo "APEX_STAND_SHOULDER_WIDTH_M=${STAND_SHOULDER_WIDTH_VALUE}"
  echo "APEX_STAND_HEIGHT_M=${STAND_HEIGHT_VALUE}"
fi
echo "APEX_WRIST_CAMERA=${WRIST_CAMERA_VALUE}"
echo "APEX_TOOL_TYPE=${TOOL_TYPE_VALUE}"
echo "APEX_TELEOP_MODE=${TELEOP_MODE_VALUE}"
echo "APEX_DDS=${DDS_VALUE}"
echo "APEX_ROBOT_IP=${ROBOT_IP_VALUE}"
echo "ROS_DOMAIN_ID=${ROS_DOMAIN_ID_VALUE}"
echo "ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY_VALUE}"
echo "APEX_DNSMASQ_INTERFACE=${DNSMASQ_INTERFACE_VALUE}"
echo "APEX_DNSMASQ_HOST_CIDR=${DNSMASQ_HOST_CIDR_VALUE}"
echo "APEX_DNSMASQ_DHCP_RANGE=${DNSMASQ_DHCP_START_VALUE}-${DNSMASQ_DHCP_END_VALUE}"
if [[ "${BACKEND_SERVICE_MODE}" == "container" ]]; then
  echo "Host module services installed; Docker Backend installation follows."
else
  echo "Backend is enabled for boot. Camera, DNSMasq, robot, teleop and tool remain on-demand."
  echo "Start backend now with: sudo systemctl start apex-backend.service"
fi
