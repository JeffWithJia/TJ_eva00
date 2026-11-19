#!/usr/bin/env bash
# Shared Apex ROS environment for systemd services and terminal debugging.

set -a
if [[ -f /etc/apex/apex.env ]]; then
  # shellcheck disable=SC1091
  source /etc/apex/apex.env
fi
set +a

export HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
export ROS_LOG_DIR="${ROS_LOG_DIR:-/var/log/apex/ros}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"

# DDS 实现选择（apex.env 里的 APEX_DDS：fastdds | cyclone）。
# cyclone 需要 ros-<distro>-rmw-cyclonedds-cpp，配置在 /etc/apex/cyclonedds.xml。
APEX_DDS_LOWER="$(echo "${APEX_DDS:-fastdds}" | tr '[:upper:]' '[:lower:]')"
case "${APEX_DDS_LOWER}" in
  cyclone|cyclonedds)
    export RMW_IMPLEMENTATION="rmw_cyclonedds_cpp"
    if [[ -f "${APEX_CYCLONEDDS_XML:-/etc/apex/cyclonedds.xml}" ]]; then
      export CYCLONEDDS_URI="file://${APEX_CYCLONEDDS_XML:-/etc/apex/cyclonedds.xml}"
    fi
    ;;
  fastdds|fastrtps|"")
    export RMW_IMPLEMENTATION="rmw_fastrtps_cpp"
    ;;
  *)
    echo "WARNING: unknown APEX_DDS='${APEX_DDS}', falling back to fastdds" >&2
    export RMW_IMPLEMENTATION="rmw_fastrtps_cpp"
    ;;
esac
unset APEX_DDS_LOWER

# shellcheck disable=SC1090
source "${APEX_ROS_SETUP:-/opt/ros/humble/setup.bash}"
# shellcheck disable=SC1090
source "${APEX_WS_SETUP:-/opt/kernelmind/apex/install/setup.bash}"

# Host modules use only Debian/ROS Python packages.  Backend-only Python
# dependencies live inside the Backend image; do not inject a host virtualenv
# or per-user site-packages into Camera, Robot, Teleop, or Tool services.
unset VIRTUAL_ENV
