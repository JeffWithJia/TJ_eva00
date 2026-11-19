# Apex Backend Docker（Orin/Humble 与 Thor/Jazzy）

This is the first stage of moving Apex runtime management into containers. It
puts the Backend Python and ROS dependencies in an ARM64 image while the camera,
robot, teleop, tool, and dnsmasq modules remain host systemd services.

The REST, WebSocket, and ROS interfaces are unchanged. The container uses host
networking and IPC so DDS discovery behaves like the native Backend. It does not
mount the Docker socket and does not run privileged. A small root-owned host
service exposes only allowlisted `show/start/stop/restart` and journal operations
for the five Apex module services over a Unix socket.

## Build on ARM64 Jetson

The host must be ARM64 and have Docker 28 or later. From the Apex_Deploy root:

```bash
export APEX_BACKEND_IMAGE=kernelmind/apex-backend:humble-arm64
sudo -E UI_node/apex_backend/docker/build_backend_image.sh
```

在 Ubuntu 24.04 / ROS 2 Jazzy 的 Thor 上构建：

```bash
export APEX_ROS_DISTRO=jazzy
export APEX_BACKEND_IMAGE=kernelmind/apex-backend:jazzy-arm64
sudo -E UI_node/apex_backend/docker/build_backend_image.sh
```

The build defaults to the Aliyun Python package index on deployments in China.
Override it without editing the Dockerfile when another mirror is required:

```bash
export APEX_PIP_INDEX_URL=https://your-pypi-mirror.example/simple/
sudo -E UI_node/apex_backend/docker/build_backend_image.sh
```

Humble 的默认基础镜像是 `ros:humble-ros-base-jammy`，Jazzy 的默认基础镜像是
`ros:jazzy-ros-base-noble`。If Docker Hub alone is blocked
but the Ubuntu/ROS and PyPI repositories are reachable, load a previously
exported ARM64 base image first:

```bash
export APEX_ROS_BASE_IMAGE_TAR=/path/ros-humble-ros-base-jammy-arm64.tar
sudo -E UI_node/apex_backend/docker/build_backend_image.sh
```

Alternatively, set `APEX_ROS_BASE_IMAGE` to an ARM64 registry mirror reference;
the selected base image is recorded in the build but the final Apex image tag
remains `APEX_BACKEND_IMAGE`.

For a fully offline robot, build once on a connected ARM64 builder and export the
complete image:

```bash
export APEX_BACKEND_IMAGE_TAR_OUT=/tmp/apex-backend-humble-arm64.tar
sudo -E UI_node/apex_backend/docker/build_backend_image.sh
```

Copy that archive to the robot and pass `APEX_BACKEND_IMAGE_TAR` to the smoke or
install command. The Python dependency versions are locked in the matching
`requirements-humble.lock` or `requirements-jazzy.lock`; no host venv or user
site-packages are mounted into the container.

## Non-disruptive smoke test

This keeps the native Backend on port 8080 and starts the container on port
18080. Installing the restricted host proxy does not restart any robot module.

```bash
sudo -E UI_node/apex_backend/docker/install_backend_container.sh smoke
```

On an offline robot:

```bash
export APEX_BACKEND_IMAGE_TAR=/path/apex-backend-humble-arm64.tar
sudo -E UI_node/apex_backend/docker/install_backend_container.sh smoke
```

The test verifies that the HTTP API starts, the host control socket is usable,
and the `apex_backend` and `marvin_msgs` ROS packages exist in the image.

## Package-managed switch

Only switch after the smoke test passes and the robot is in a safe state:

```bash
sudo -E UI_node/apex_backend/docker/install_backend_container.sh install
```

The deb carries a versioned `docker save` archive. Its `postinst` loads the
image without network access, runs the smoke test on port `18080`, and only
then switches the production unit on port `8080`. During upgrades the previous
unit is restored automatically if the new image fails either health check.
There is no native-Backend rollback because the host venv/pip runtime is no
longer installed. Package removal uses the `uninstall` action to remove the
container, image, host-control helper and generated units.

Runtime configuration remains `/etc/apex/apex.env`. The exact
`BAG_STORAGE_ROOT`, ROS logs under `/var/log/apex`, and `/etc/apex` are
bind-mounted explicitly.

## Migration boundary

This stage deliberately keeps the module services on the host. When robot,
teleop, camera, and tool become containers, the same Backend API can be retained
and the host-control transport replaced by a container orchestrator. Do not give
the Backend unrestricted access to `/var/run/docker.sock`.
