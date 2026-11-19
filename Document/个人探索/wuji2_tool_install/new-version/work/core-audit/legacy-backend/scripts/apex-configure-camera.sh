#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${APEX_ENV_FILE:-/etc/apex/apex.env}"
ENV_LIB="${APEX_ENV_LIB:-/opt/kernelmind/apex/install/apex_backend/share/apex_backend/scripts/apex_env_lib.sh}"
CAMERA_CONFIG="${APEX_GMSL_CAMERA_CONFIG:-/opt/kernelmind/apex/install/gmsl_quadcam/share/gmsl_quadcam/config/quad_quickview.yaml}"

if [[ ! -r "${ENV_LIB}" ]]; then
  echo "Apex environment helper not found: ${ENV_LIB}" >&2
  exit 2
fi
# shellcheck source=apex_env_lib.sh
source "${ENV_LIB}"

COMPUTE_PLATFORM="${APEX_COMPUTE_PLATFORM:-$(existing_env_value APEX_COMPUTE_PLATFORM)}"
COMPUTE_PLATFORM="${COMPUTE_PLATFORM:-orin}"
ROBOT_PLATFORM="${APEX_ROBOT_PLATFORM:-$(existing_env_value APEX_ROBOT_PLATFORM)}"
ROBOT_PLATFORM="${ROBOT_PLATFORM:-gento}"
WRIST_CAMERA="${APEX_WRIST_CAMERA:-$(existing_env_value APEX_WRIST_CAMERA)}"
WRIST_CAMERA="${WRIST_CAMERA:-d405ga}"

write_camera_platform_yaml \
  "${CAMERA_CONFIG}" "${COMPUTE_PLATFORM}" "${ROBOT_PLATFORM}" "${WRIST_CAMERA}"
echo "Configured cameras: compute=${COMPUTE_PLATFORM}, robot=${ROBOT_PLATFORM}, wrist=${WRIST_CAMERA}, file=${CAMERA_CONFIG}"
