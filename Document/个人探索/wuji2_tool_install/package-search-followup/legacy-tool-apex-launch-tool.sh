#!/usr/bin/env bash
# ExecStart entrypoint for apex-tool.service.

set -eo pipefail

source /etc/apex/apex_ros_env.sh
source /opt/kernelmind/apex_tool/install/setup.bash

tool_type="$(echo "${APEX_TOOL_TYPE:-dm}" | tr '[:upper:]' '[:lower:]')"

exec ros2 launch apex_tool tool.launch.py tool_type:="${tool_type}"
