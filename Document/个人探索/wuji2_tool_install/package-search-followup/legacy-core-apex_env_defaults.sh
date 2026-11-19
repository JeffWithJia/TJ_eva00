#!/usr/bin/env bash
# Central defaults for /etc/apex/apex.env — the single place to change a
# default value. Sourced by install_systemd_services.sh.
#
# Precedence at install time: CLI flag / environment override > value already
# present in /etc/apex/apex.env > the defaults below. Dynamic values that
# depend on the run user (HOME, BAG_STORAGE_ROOT, PYTHONPATH) or on the
# dnsmasq host IP (DHCP range, robot IP) are derived in
# install_systemd_services.sh instead.

# ── ROS / workspace ──────────────────────────────────────────────────────────
# Used when no APEX_ROS_SETUP is configured and /opt/ros/*/setup.bash detection
# fails.
DEFAULT_APEX_ROS_SETUP="/opt/ros/humble/setup.bash"
DEFAULT_APEX_WS_SETUP="/opt/kernelmind/apex/install/setup.bash"
DEFAULT_APEX_ROS_NAMESPACE="tj"
DEFAULT_ROS_DOMAIN_ID="0"
DEFAULT_ROS_LOCALHOST_ONLY="0"
DEFAULT_ROS_LOG_DIR="/var/log/apex/ros"
DEFAULT_APEX_DDS="fastdds"                   # fastdds | cyclone

# ── Backend ──────────────────────────────────────────────────────────────────
DEFAULT_APEX_BACKEND_HOST="0.0.0.0"
DEFAULT_APEX_BACKEND_PORT="8080"

# ── Robot ────────────────────────────────────────────────────────────────────
DEFAULT_APEX_ROBOT_PLATFORM="gento"          # gento | pro
DEFAULT_APEX_ROBOT_MODEL_GENTO="luna"        # luna | luna_v3 | skye | skye_v2_920
DEFAULT_APEX_ROBOT_MODEL_PRO="pro_m6s_696_new" # pro_arm_base format
DEFAULT_APEX_COMPUTE_PLATFORM="orin"         # orin | thor
DEFAULT_APEX_WRIST_CAMERA="d405ga"           # d405ga | shw5g
DEFAULT_APEX_TOOL_TYPE="dm"                  # dm | zy | wuji | none
DEFAULT_APEX_TELEOP_MODE="controller"        # controller | dexhand

# ── Python ───────────────────────────────────────────────────────────────────
# Skip user site-packages in service subprocesses (cmeel.pth noise otherwise).
DEFAULT_PYTHONNOUSERSITE="1"

# ── DNSMasq ──────────────────────────────────────────────────────────────────
DEFAULT_APEX_ENABLE_DNSMASQ="0"
DEFAULT_APEX_DNSMASQ_INTERFACE="eth0"
DEFAULT_APEX_DNSMASQ_HOST_IP="192.168.10.1"  # /24 mask fixed; DHCP range derived
DEFAULT_APEX_DNSMASQ_LEASE_TIME="12h"
