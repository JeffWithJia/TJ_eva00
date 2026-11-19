# Core 1.1.7.4 audit — read-only package inspection

## Artifact identity

- Official release: https://github.com/Gento-Teleoperation-Apex/KernelMind_Apex_Deb/releases/tag/v1.1.7.4gento
- Artifact: Gento-Teleoperation-Apex_v1.1.7.4o_humble_arm64.deb
- Downloaded 290975910 bytes; SHA256 verified against GitHub release asset metadata: `c4362aa6acafeac77a5e55d21a7b13e67008815770a6d2eaeb42a36d90f7d7b7`.
- Actual Debian identity: `Package: gento-apex`, `Version: 1.1.7.4`, `Architecture: arm64`. The prose documentation's `1.1.7.4g` is not the package version.
- `Provides`, `Conflicts`, `Replaces`: `kernelmind-apex` (unversioned). Installing through APT removes/replaces the old `kernelmind-apex` package.
- Depends: `docker.io | docker-ce`, `docker-compose-v2 | docker-compose-plugin`, `nvidia-container-toolkit`, `ca-certificates`, `python3`, `sudo`, `acl`.
- Payload targets Gento / Orin, permits Orin and Thor, Humble, ARM64.
- Common Runtime required: `teleoperation-apex-runtime:1.0.4`, ABI `humble-r2`; not embedded. Exact image ID: `sha256:85624684bf261053ee7327d2c05f2dfe530cdef0ca2679698cac0dd93fe4e966`. Merely retagging another runtime will fail validation.
- SDK 4.7.1 is bundled under `/opt/kernelmind/apex/releases/1.1.7.4/sdk` and loaded inside the runtime container. No host SDK DEB replacement is performed by the inspected scripts. New Robot runtime nevertheless uses SDK4.7.1 instead of old host SDK4.5.1.

## Important migration risk

The `preinst` backup only executes for the `upgrade` argument. Moving from package name `kernelmind-apex` to `gento-apex` can invoke `install` instead, skipping that backup. Do not rely on package rollback to preserve old Core. Also audit old package removal scripts before authorizing APT: the new package's rollback cannot resurrect files removed by the old package's removal scripts without an external snapshot.

Successful `postinst` deletes `/opt/kernelmind/venv` and `/opt/kernelmind/apex/backend-container`; it replaces `/opt/kernelmind/apex/install` with a release symlink and may delete an old real install directory. Full old Core + venv snapshot is mandatory before installation.

## Exact systemd impact

These are normal effects of the unmodified official installer, not changes executed by this audit:

1. `/etc/systemd/system/apex-stack.service`: install/overwrite and `enable`, `start`. `Requires=docker.service apex-container-control.service`; `After=network-online.target docker.service apex-container-control.service`; `Wants=network-online.target`; oneshot/remain-after-exit; `ExecStart=/usr/local/bin/apexctl up`, `ExecReload=... restart backend`, `ExecStop=... down`, timeouts180/120. Core Backend becomes container-managed; installation starts it and waits for HTTP health.
2. `/etc/systemd/system/apex-container-control.service`: install/overwrite, `enable`, `restart`. Requires/After docker.service, Before apex-stack.service. Root notify daemon `/usr/bin/python3 /usr/local/libexec/apex/apex_container_control.py`, Restart=on-failure, RestartSec=2; owns `/run/apex-host-control/backend.sock`; fixed allowlist controller.
3. `/etc/systemd/system/apex-recording-storage.service`: install/overwrite and start once. Runs `apexctl prepare-recording-storage`; may create/adjust recording-directory ownership/ACL/setgid and apex-recording group. No Install section/self-enable.
4. For each `apex-backend`, `apex-dnsmasq`, `apex-robot`, `apex-teleop`, `apex-tool`: `/etc/systemd/system/NAME.service` is created/replaced if absent or already a Compose facade; otherwise the existing unit is preserved and `/etc/systemd/system/NAME.service.d/90-apex-compose-compat.conf` is installed. That drop-in adds `Requires=apex-stack.service`, `After=apex-stack.service`; sets Type=simple, User/Group=root, WorkingDirectory=/; resets EnvironmentFile, ExecStartPre, ExecStart, ExecReload, ExecStop; installs `apex-service-compat start/restart/stop MODULE`; sets Restart=no, KillSignal=SIGTERM, TimeoutStartSec=90, TimeoutStopSec=70 for Robot or30 otherwise. Tool always gets the facade drop-in, and later independent Tool package owns its executor.
5. Existing legacy backend/dnsmasq/robot/teleop/tool units are stopped during migration. `apex-backend.service` is enabled; backend facade is started when its container is running. Robot/Teleop/DNS are restarted only if recorded active before the upgrade. This makes prestop state critical.
6. `apex-backend-host-control.service`: stopped, disabled; `/etc/systemd/system/apex-backend-host-control.service` removed. The new controller replaces its socket owner.
7. `apex-websocket.service`: unconditional `disable --now`; `/etc/systemd/system/apex-websocket.service` removed.
8. Camera is intended to remain owned by its independent package. Nevertheless legacy Core camera units can be removed: `/etc/systemd/system/apex-camera.service` matching the exact old Compose facade is stopped/disabled/removed; old Core camera-native-v1 unit or orphaned exact legacy unit is backed up then removed. Matching `/etc/systemd/system/apex-camera.service.d/90-apex-compose-compat.conf` also removed. Old `/etc/apex/apex-launch-camera.sh` and `apex-configure-camera.sh` are removed if recognized as old Core scripts. Consequently current old Camera compatibility cannot be promised without inspecting its files; Core+Tool-only upgrade is sufficient for software Tool checks but not proven to retain old camera chain.
9. `docker.service` is explicitly `enable --now` by Core postinst (record previous enabled/active state). Existing `apex-backend` Docker restart policy is changed to `no` before recreation.

## Preventing Robot/Teleop motion during software checks

Do not depend only on having no Wuji hands attached. Inspect and record current service+container state. Explicitly stop Robot and Teleop through the OLD supported mechanism before invoking any package maintainer script; keep them inactive. `install_stack.sh` records active old services/containers and starts Robot/Teleop/DNS if they were active. In this fixture prior checks said Robot/Teleop inactive, but refresh just before change. `apexctl up` was checked: it starts Backend, and also DNSMasq when DNSMASQ_ENABLED=1. It does not start Robot or Teleop. Installer additionally restores previously-running Robot/Teleop/DNS. Do not start Robot or Teleop for this software-only task.

Runtime masks on Robot/Teleop can prevent systemd starts but do not stop direct `apexctl`/Compose starts; they also may cause installer operations to fail. Prefer correct inactive baseline and inspect running containers throughout. Any use of masks must be planned and backed up, not silently added.

## Full backup scope

Preserve ACLs/xattrs/mode/owner and symlink identity, plus exact list of absent files so rollback removes only files newly created by this installation.

- `/opt/kernelmind/apex` whole tree; `/opt/kernelmind/venv`; `/opt/kernelmind/apex_tool`; host SDK package/files for independent confirmation.
- `/etc/apex`; `/etc/kernelmind`; `/etc/profile.d/kernelmind_apex.sh`; `/etc/sudoers.d/apex-nvidia` (installer deletes this), `/etc/sudoers.d/apex-camera-argus` (legacy Core handoff may remove).
- All `/etc/systemd/system/apex-*.service`, corresponding `.service.d`, relevant wants/requires links; exact active/enabled/masked state; docker.service active/enabled state. Save unit text and systemctl properties.
- `/usr/local/bin/apexctl`, `/usr/local/bin/apex-service-compat`; `/usr/local/libexec/apex`; `/usr/local/share/apex/stack`.
- `/var/lib/apex`; `/var/backups/apex-camera-core-handoff`; deployed user's old config directory from apex.env; `/home/nvidia/.tj_config` (new defaults `/home/nvidia/.tj_config/apex-core`; old apex-beta migrates).
- Directory metadata for `/home/nvidia/.ros/log` and configured recording root; snapshot group metadata if new apex-recording group is created.
- Docker image IDs/tags, container inspect including restart policy, relevant Compose files; keep old images, never prune them.
- Exact official old Core/Tool DEBs and old SDK DEB with hashes; dpkg selections/status info and package file manifests, without restoring whole dpkg database over newer packages.

## Config / UI / camera scope

Tool2 requires applied Core schema3. Core regenerates `/etc/apex/apex.env`, DDS file, ROS env, creates new `.tj_config/apex-core`, `/var/lib/apex/module-context` and `/etc/apex/module-runtime.env`. Existing user config must be migrated/validated, not fabricated by changing schema integers.

No DEB dependency forces Camera or UI installation. Core payload excludes camera and Tool implementations. Official release pairs Camera1.3.3 (specific rebuild), UI1.1.7.3 and VR1.1.0.3. For Tool-only software checks Core+Common+Tool is a technically coherent scope if Camera/Robot/Teleop remain stopped; old UI1.0.42 support for new independent config APIs is not proven, and old Camera can lose Core-provided wrappers. Using CLI/API avoids relying on old UI for those checks. Full VR/recording compatibility requires later acceptance.

## Rollback framework — must be concretized with old package audit before execution

Do not run the following as a blind script. General shape:

1. Stop new Tool executor and new Core stack using new `apexctl` while binaries exist; disable/remove only newly added Core stack/controller facades as audited. Keep Robot/Teleop stopped.
2. Use APT's resolved transaction to remove `gento-apex` and install exact old `kernelmind-apex` and `gento-apex-tool` versions. Account for old maintainer scripts' automatic starts; `policy-rc.d` alone does not intercept direct systemctl calls. Do not use --force-depends.
3. Restore complete old filesystem snapshot (including venv, symlinks, service/drop-ins, config, sudoers), remove only documented new artifacts that were absent before, `systemctl daemon-reload`; restore old enablement from snapshot.
4. Restore only originally-running service(s), usually Backend, and original Docker restart policy if changed; do not start Robot/Teleop/Tool just to claim success.
5. Verify dpkg status and exact package versions, old file hashes/symlinks, old Backend health, all service active/enabled states, no new container still listening on same ports. Compare against pre-upgrade baseline. Rollback successful means baseline restored, not that hardware/robot control was newly tested.

No package scripts or remote mutations were executed by this audit.

## Additional evidence from refreshed legacy-preflight.jsonl

The installed `kernelmind-apex` file manifest owns `/opt/kernelmind/apex/install/gmsl_quadcam`, and dpkg verification reports a site modification in `gmsl_quadcam/config/quad_quickview.yaml` (plus robot_param_luna.yaml). New Core excludes gmsl_quadcam and removes/replaces the old install directory, so retaining old camera service files alone cannot retain camera execution. Core+Tool-only can pass its limited software check, but preserving all existing camera/recording behavior requires the matching independent Camera package or rollback. Back up the modified camera and robot YAML as part of full old install tree.

Legacy package also owns `/lib/systemd/system/apex-backend-container.service`, `apex-backend-host-control.service`, `apex-backend.service`, `apex-camera.service`, `apex-dnsmasq.service`, etc. Include `/lib/systemd/system/apex-*` (resolved `/usr/lib` as applicable) in service snapshot in addition to `/etc/systemd/system` overrides. Preserve exact old DEB to restore package-owned vendor units.

Refreshed host observation says `/opt/kernelmind/venv` absent, `.tj_config` absent, `/var/lib/apex` absent; preserve these absence records. `/home/nvidia/.ros/log` mode is 0775 and installer changes parent mode to 0750. `docker.service` already active+enabled, so its enable-now command introduces no enablement change in the observed baseline.

## Installed legacy maintainer script audit

Source: `/home/jeff/coscene/Robot/天机/wuji2_tool_install/new-version/work/legacy-maintainer-scripts.tar.gz`; seven actual scripts extracted under `legacy-scripts/`. No old Core preinst exists.

- Old Core `prerm upgrade|failed-upgrade` returns immediately. Its `remove` path removes `/etc/profile.d/kernelmind_apex.sh` and config links, runs `/usr/local/share/apex/backend-docker/docker/install_backend_container.sh uninstall` (if present), then stops and disables Camera/DNS/Robot/Teleop/Tool. Fallback stops+disables Backend/controller, forcibly removes Docker `apex-backend` and `apex-backend-smoke`, and removes controller/backend configuration files.
- Old Core `postrm remove|purge` removes `/opt/kernelmind/venv`, `/etc/systemd/system/apex-backend-host-control.service`, `/usr/local/libexec/apex/apex_backend_host_control.py`, `/etc/apex/backend-container.env`, `/usr/local/share/apex/backend-docker`. It does not purge recordings.
- Therefore additional snapshot path required: `/usr/local/share/apex/backend-docker`. Old DEB embeds Backend image tar, but preserving existing image ID/container inspect is still useful.
- Old Core `postinst` runs Pinocchio and Camera websockets16 checks; sets old `/etc/kernelmind/.../config` symlinks; invokes old `install_systemd_services.sh` with `APEX_BACKEND_SERVICE_MODE=container`, then enables/starts Docker and invokes old `install_backend_container.sh install`. It explicitly expects Backend enabled+running. Nested installer inspection is required to rule out other auto-starts; maintainer script itself contains no Robot/Teleop/Tool start.
- Old Tool `preinst upgrade` stops `apex-tool.service`; `prerm remove` stops it. Old Tool `postinst` chooses dm/zy/none (default dm), updates `/etc/apex/apex.env`, fixes unit user/group and daemon-reloads. It explicitly does not start or enable Tool. Passing `DEBIAN_FRONTEND=noninteractive APEX_RUN_USER=nvidia APEX_TOOL_TYPE=none` avoids the DM default during a rollback transaction; after complete restoration, original apex.env returns `dm` while Tool remains stopped/disabled.
- `policy-rc.d` cannot be relied upon: both old and new scripts call `systemctl` directly.

## Nested legacy installer verification — final

Read old `scripts/install_systemd_services.sh`, `docker/install_backend_container.sh`, and host-control helper from `legacy-backend-scripts.tar.gz`. No scripts were executed.

- `install_systemd_services.sh` installs/replaces Camera, DNS, Robot, Teleop and Tool units but does not start/enable them. For container mode it does not start Backend either; the following container installer handles that.
- `install_backend_container.sh install` starts/enables only old Backend host controller and Backend; creates short-lived Backend smoke container18080; verifies production health8080. Core postinst enables/starts Docker. It does not issue any Robot/Teleop/Tool/Camera/DNS start.
- Host-control helper's start/stop methods are request handlers, not startup jobs.
- Thus the audited old reinstall path does not itself command Robot/Teleop/DM. Keep their baseline inactive, avoid unrelated external control requests, and verify no new Compose containers remain before old Backend is restored. No global policy-rc.d or masks are needed for these particular scripts.
- Critical old uninstall behavior: it removes the old Backend image by default. Pass `APEX_KEEP_BACKEND_IMAGE=1` into the privileged APT process for both forward upgrade and rollback. This setting is honored by old `uninstall_container_service`.
- `cleanup_previous_image` on old reinstall removes a different previous `kernelmind/apex-backend:*` tag and does not honor that flag. Restoring the original `/etc/apex/backend-container.env` before old reinstall avoids designating an unrelated previous image. Preserve old image by ID and offline DEB regardless.

### Reviewed package command forms (not executed)

Forward Core-only package transaction, once all authorization/preconditions are met. Install Tool separately after Core schema3 has been applied; the combined APT ordering is unsuitable:

```bash
sudo env DEBIAN_FRONTEND=noninteractive APEX_RUN_USER=nvidia \
  APEX_KEEP_BACKEND_IMAGE=1 apt-get install "$new_core_deb"
```

Rollback package simulation and then exact joint downgrade, with variables pointing to verified local original DEBs:

```bash
sudo env DEBIAN_FRONTEND=noninteractive APEX_RUN_USER=nvidia \
  APEX_KEEP_BACKEND_IMAGE=1 APEX_TOOL_TYPE=none \
  apt-get --simulate --allow-downgrades install "$old_core_deb" "$old_tool_deb"

sudo env DEBIAN_FRONTEND=noninteractive APEX_RUN_USER=nvidia \
  APEX_KEEP_BACKEND_IMAGE=1 APEX_TOOL_TYPE=none \
  apt-get --allow-downgrades --reinstall install "$old_core_deb" "$old_tool_deb"
```

Before actual rollback package command: stop new Tool and new stack, restore original `/etc/apex/apex.env` and original `/etc/apex/backend-container.env`; ensure exact old DEBs and full snapshot are locally readable. Simulation must show new `gento-apex` removed and original `kernelmind-apex` installed with Tool downgrade, without unrelated removals. After package transaction finishes: restore full original snapshot (not dpkg database), remove only new artifacts recorded absent in baseline, daemon-reload, restore old enablement and only original running Backend/controller. OldCore postinst does start Backend during package configure, hence original deployment/network config must be restored before configure. Final original `apex.env` restores dm, while Tool remains stopped/disabled. Preserve/compare exact unit content+drop-ins and all original site-modified YAML.

The final complete rollback script must merge these Core steps with independently audited Tool2 executor cleanup, use actual snapshot member paths, and verify no `apex-tool-docker`/new stack remains. The commands above alone are not a full rollback script.
