# Exact Maintainer OpenOS Update Commands

Use this sheet only for release `maintainer-c0.1.2-a0.1.61-g0.1.0-d0.1.64-x0.1.8-49c169136e34`. The four public artifacts were verified byte-for-byte at the immutable public commit below.

- Release: `maintainer-c0.1.2-a0.1.61-g0.1.0-d0.1.64-x0.1.8-49c169136e34`
- Public repository: `SirJamesK/opencomputers-maintainer-releases`
- Public commit: `a4966d374f2cd60c991d09fe54f62b0f887fce6d`
- Private source commit: `cd367354285578ea47be9700d8816017d50f95a4`
- Systems: Core 0.1.2, AE2 0.1.61, GT Power 0.1.0, Dashboard 0.1.64, Commands 0.1.8
- Targets: 174
- Bundle SHA-256: `4b2398d4ac2996fcc4b704ebd1e92ede1361b3d23ab5d0c0fc3164d16e74008a`

Before starting: stop the Maintainer, exit every Dashboard, confirm the daemon policy is OFF, and obtain a confirmed no-backup maintenance window.

## 1. Download and stage

```sh
wget -f https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/a4966d374f2cd60c991d09fe54f62b0f887fce6d/releases/maintainer-c0.1.2-a0.1.61-g0.1.0-d0.1.64-x0.1.8-49c169136e34/install.lua /home/oc-release.lua
lua /home/oc-release.lua plan
lua /home/oc-release.lua status
lua /home/oc-release.lua stage https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/a4966d374f2cd60c991d09fe54f62b0f887fce6d/releases/maintainer-c0.1.2-a0.1.61-g0.1.0-d0.1.64-x0.1.8-49c169136e34/bundle.ocb NO_BACKUP
lua /home/oc-release.lua status
```

The final status in this phase must be STAGED. Then run:

```sh
shutdown
```

Wait until the computer is visibly OFF and manually power it on. Do not use reboot and do not start the Dashboard or Maintainer.

## 2. Apply

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua apply OFFLINE NO_BACKUP CONFIRM
lua /home/oc-release.lua status
```

The final status in this phase must be APPLIED.

## 3. Verify from fresh processes

```sh
lua
=type(require("oc.ae2.workflows").prepareOnboarding)
=type(require("oc.ae2.workflows").pollOnboardingPreparation)
=type(require("oc.ae2.workflows").restoreOnboarding)
```

All three Lua expressions must print `"function"`. Press Ctrl+D, then run:

```sh
oc-config-migrate verify-install
oc-config-migrate status
ae2-probe
oc-dashboard
```

Smoke-test the Dashboard while Maintainer remains OFF, then exit the Dashboard. Confirm daemon policy is still OFF and run:

```sh
shutdown
```

Wait until visibly OFF and manually power it on again. Remain at the shell.

## 4. Finalize after successful verification

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua finalize OFFLINE NO_BACKUP VERIFIED CONFIRM
lua /home/oc-release.lua status
oc-config-migrate verify-install
oc-config-migrate status
```

The release transaction must now report FINALIZED. Normal Dashboard/Maintainer startup may resume.

## Failure path instead of finalization

If fresh-process verification failed, keep every Dashboard and Maintainer process closed. After the required full shutdown, visible-OFF wait, and manual power-on, run:

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua rollback OFFLINE NO_BACKUP CONFIRM
lua /home/oc-release.lua status
lua /home/oc-release.lua discard NO_BACKUP CONFIRM
lua /home/oc-release.lua status
```
