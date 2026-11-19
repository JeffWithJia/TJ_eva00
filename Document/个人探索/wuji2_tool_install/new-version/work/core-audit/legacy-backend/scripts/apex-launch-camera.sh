#!/usr/bin/env bash
# ExecStart entrypoint for apex-camera.service.  The WebRTC signaling server is
# a host Python process, so make it use the version-locked runtime carried by
# kernelmind-apex instead of Ubuntu's older python3-websockets package.

source /etc/apex/apex_ros_env.sh

CAMERA_PYTHON_DIR="/opt/kernelmind/apex/camera-python"
if [[ ! -r "${CAMERA_PYTHON_DIR}/websockets/__init__.py" ]]; then
  echo "Bundled Camera Python runtime is missing: ${CAMERA_PYTHON_DIR}" >&2
  exit 2
fi
export PYTHONPATH="${CAMERA_PYTHON_DIR}${PYTHONPATH:+:${PYTHONPATH}}"

if ! CAMERA_WEBSOCKETS_VERSION="$(
  /usr/bin/python3 -c 'import websockets; print(websockets.__version__)'
)"; then
  echo "Cannot import bundled Camera websockets from ${CAMERA_PYTHON_DIR}." >&2
  exit 2
fi
if [[ "${CAMERA_WEBSOCKETS_VERSION}" != "16.0" ]]; then
  echo "Camera requires bundled websockets 16.0; found ${CAMERA_WEBSOCKETS_VERSION:-unknown}." >&2
  exit 2
fi

exec ros2 launch gmsl_quadcam quad_csi_quickview.launch.py
