# Exact Maintainer OpenOS Update Commands

Use this sheet only for release `maintainer-c0.1.2-a0.1.76-g0.1.0-d0.1.79-x0.1.11-4325e97d4840`. The four public artifacts were verified byte-for-byte at the immutable public commit below.

- Release: `maintainer-c0.1.2-a0.1.76-g0.1.0-d0.1.79-x0.1.11-4325e97d4840`
- Public repository: `SirJamesK/opencomputers-maintainer-releases`
- Public commit: `404168b240591d6e9a28146f096ead47ceb1c99c`
- Private source commit: `9f4aa4e5d13cffb7458c005b2965435a3cda1d89`
- Systems: Core 0.1.2, AE2 0.1.76, GT Power 0.1.0, Dashboard 0.1.79, Commands 0.1.11
- Targets: 183
- Bundle SHA-256: `e1a0d56496f21ae8f1f650549f0e35eca2f72989eb82b4053897f4c27516f6b4`

Before starting: stop the Maintainer, exit every Dashboard, confirm the daemon policy is OFF, and obtain a confirmed no-backup maintenance window.

## 1. Download and stage

```sh
wget -f https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/404168b240591d6e9a28146f096ead47ceb1c99c/releases/maintainer-c0.1.2-a0.1.76-g0.1.0-d0.1.79-x0.1.11-4325e97d4840/install.lua /home/oc-release.lua
lua /home/oc-release.lua plan
lua /home/oc-release.lua status
lua /home/oc-release.lua stage https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/404168b240591d6e9a28146f096ead47ceb1c99c/releases/maintainer-c0.1.2-a0.1.76-g0.1.0-d0.1.79-x0.1.11-4325e97d4840/bundle.ocb NO_BACKUP
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
=type(require("oc.ae2.workflows").setCraftCompatibility)
=type(require("oc.ae2.workflows").setFluidStockCompatibility)
```

All five Lua expressions must print `"function"`. Press Ctrl+D, then run:

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

The release transaction must now report FINALIZED. Keep Global Auto and daemon
ownership OFF until the compatibility setup and smoke tests below pass.

## 5. Select GTNH 2.8.4 Craft and Fluid Stock APIs

Run exactly one `oc-dashboard` process and open **AE2 -> Daemon**. Then:

1. If Global Auto is on, press `G` to turn it off.
2. If daemon ownership is OFF, press `Shift+D` once to start it. This one
   Global-Auto-off run repairs missing proof left by an older release.
3. Wait until the Daemon page shows a live heartbeat and in-flight `0`.
4. Press `Shift+D` once to stop daemon ownership, then wait until it reports
   OFF and the selector no longer shows a worker-exit or runtime-state lock.
5. Under **Maintainer Settings - Craft API Selector**, click **GTNH 2.8.4**.
6. Click **GTNH 2.8.4** again within 15 seconds to confirm.
7. Verify the status strip reads `Storage Guard SCALAR ONLY` and `Craft API 2.8.4 FILTER`.

The selector is global. It preserves all valid configured workflow rows, exact
identities, thresholds, batches, and arm states; do not convert the library or
rebind every craft. Add/Repair and invalid or label-only rows remain quarantined.
Fluid stock authority is a separate global selector and must now be locked once:

8. Run `ae2-workflow --show-bind` in a separate shell only if needed to check
   identities. Choose one exact ordinary fluid registry name that is always
   positive and is **not** an auto Maintainer target. `water` is suitable only
   when it is truly stocked and absent from the maintained auto-fluid set.
9. Back in **AE2 -> Daemon**, under **Maintainer Settings - Fluid Stock API**,
   click **Configure 2.8.4**.
10. Type that exact canary registry name and press Enter.
11. Type a topology revision such as `GRID-R1` and press Enter. For every later
    target-set, Discretizer, or AE2 topology change, use a new revision such as
    `GRID-R2`; do not reuse the prior revision after membership changes.
12. Review the preview. Its eligible count must cover every intended ordinary
    auto-fluid identity. Excluded/tagged/invalid rows receive no global authority.
13. Click **Lock Profile**, read the pending attestation, then click
    **Lock Profile** again within 15 seconds. This confirms a powered/channelled
    AE2FC Fluid Discretizer and no external or nested AE inventories on this grid.
14. Verify the status strip reads `Fluid Stock 2.8.4 AE2FC` and the detail reads
    `LOCKED ... pinned=<count> exact fluids` with the reviewed count.
15. Press Ctrl+R or leave/reopen **AE2 -> Stock**. Every intended ordinary fluid
    must show a numeric mB value; an absent reviewed fluid must show `0 mB`, not
    `ERR`. No per-fluid bind, conversion, rebind, or seed batch is required.

If the profile says `BLOCKED`, leave automation off and correct the exact reason.
Adding/removing/rebinding an auto fluid or switching it between manual and auto
intentionally blocks the entire pin until it is reviewed and relocked under a
new topology revision. Never solve that guard by enabling broad AE2 grid scans.

## 6. Test manual and automatic operation

Keep automation off, select one intended ordinary fluid row whose stock is
numeric, and press `M` once. Use this as the only cold compatibility test and
keep one Dashboard writer. Wait one full configured daemon interval before
another cold GTNH 2.8.4 test. After the fluid request
shows the expected `PLANNING`, `ACCEPTED`, and terminal lifecycle, recheck the
Fluid Stock status is still `2.8.4 AE2FC`. Then restore Global Auto with `G` and
daemon ownership with `Shift+D` only if those states are intended. Confirm an
armed below-threshold fluid submits at most one batch and its stock returns to a
numeric mB value; keep automation off if any intended ordinary fluid still says
`ERR` or the profile becomes `BLOCKED`.

When the server upgrades to GTNH 2.9, repeat the stopped/off/no-in-flight gate,
select **GTNH 2.9+**, disable the 2.8.4 Fluid Stock profile after native scalar
fluid reads are verified, and then restore automation.

## Failure path instead of finalization

If fresh-process verification failed, keep every Dashboard and Maintainer process closed. After the required full shutdown, visible-OFF wait, and manual power-on, run:

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua rollback OFFLINE NO_BACKUP CONFIRM
lua /home/oc-release.lua status
lua /home/oc-release.lua discard NO_BACKUP CONFIRM
lua /home/oc-release.lua status
```
