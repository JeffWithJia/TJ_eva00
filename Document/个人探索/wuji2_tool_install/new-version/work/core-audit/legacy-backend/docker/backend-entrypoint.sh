#!/usr/bin/env bash
# ROS 2 setup scripts probe optional variables while being sourced and are not
# compatible with bash nounset.  Keep strict error and pipeline handling here,
# but do not enable `set -u` around those vendor scripts.
set -eo pipefail

set -a
if [[ "${APEX_CONTAINER_ENV_LOADED:-0}" != "1" && -r /etc/apex/apex.env ]]; then
  # shellcheck disable=SC1091
  source /etc/apex/apex.env
fi
set +a

# Container paths must not be replaced by HOME/APEX_* values from the host.
export HOME=/home/apex
export PYTHONNOUSERSITE=1
export ROS_LOG_DIR="${APEX_BACKEND_ROS_LOG_DIR:-/var/log/apex/ros/backend-container}"
mkdir -p "${ROS_LOG_DIR}"

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
case "${APEX_DDS:-fastdds}" in
  cyclone|cyclonedds)
    export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
    if [[ -r /etc/apex/cyclonedds.xml ]]; then
      export CYCLONEDDS_URI=file:///etc/apex/cyclonedds.xml
    fi
    ;;
  *)
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
    ;;
esac

if [[ -z "${ROS_DISTRO:-}" || ! -r "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
  echo "ERROR: container ROS setup is unavailable for ROS_DISTRO=${ROS_DISTRO:-unset}" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# shellcheck disable=SC1091
source /opt/apex_ws/install/setup.bash

exec "$@"
