# Exact Maintainer OpenOS Update Commands

Use this sheet only for release `maintainer-c0.1.2-a0.1.80-g0.1.0-d0.1.83-x0.1.14-5ca03e6d9b2a`. The four public artifacts were verified byte-for-byte at the immutable public commit below.

- Release: `maintainer-c0.1.2-a0.1.80-g0.1.0-d0.1.83-x0.1.14-5ca03e6d9b2a`
- Public repository: `SirJamesK/opencomputers-maintainer-releases`
- Public commit: `0d1c3406e6a2cf250f5fdb2ebfb3fa420ed1f2ff`
- Private source commit: `666548a85cbea8f034efdf57212b7b3085bb0add`
- Systems: Core 0.1.2, AE2 0.1.80, GT Power 0.1.0, Dashboard 0.1.83, Commands 0.1.14
- Targets: 209
- Bundle SHA-256: `a25318a8b97e7837d239dc56cac666a8b41a686466249b27f8e61f40db7ede38`

Before starting: stop the Maintainer, exit every Dashboard, confirm the daemon policy is OFF, and obtain a confirmed no-backup maintenance window.

This release treats unreadable daemon policy as a maintenance brake, not an OFF
default. Its recovery-aware loader may honor a retained `.previous` after an
interrupted promotion; otherwise every request boundary makes zero physical AE2
invocations until valid policy is restored. Do not delete policy evidence to
make this gate disappear.

## 1. Download and stage

```sh
wget -f https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/0d1c3406e6a2cf250f5fdb2ebfb3fa420ed1f2ff/releases/maintainer-c0.1.2-a0.1.80-g0.1.0-d0.1.83-x0.1.14-5ca03e6d9b2a/install.lua /home/oc-release.lua
lua /home/oc-release.lua plan
lua /home/oc-release.lua status
lua /home/oc-release.lua stage https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/0d1c3406e6a2cf250f5fdb2ebfb3fa420ed1f2ff/releases/maintainer-c0.1.2-a0.1.80-g0.1.0-d0.1.83-x0.1.14-5ca03e6d9b2a/bundle.ocb NO_BACKUP
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
=type(require("oc.ae2.workflows").listIdentityEvidence)
=type(require("oc.ae2.workflows").addRecorded)
=type(require("oc.ae2.identity_evidence_v2_page").read)
=type(require("oc.ae2.identity_capture_worker").start)
=type(require("oc.ae2.workflow_identity_transaction").reconcileAll)
=type(require("oc.ae2.maintainer_daemon_control").reconcileRecorded)
```

All eleven Lua expressions must print `"function"`. Press Ctrl+D, then run:

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
rebind every craft. Recipe identity is now learned from structured AE2 CPU
`finalOutput` evidence. It never requires an operator to type a registry ID,
damage value, NBT, or topology name, and it never opens a storage snapshot.
Fluid stock authority is a separate global selector and must now be locked once:

8. To add a new managed operation whose AE2 crafting pattern already exists,
   first open **AE2 -> Targets -> Add Recorded Recipe**, then start only that
   intended AE2 craft once while the page's bounded two-second CPU poll is
   active. The page records the structured final output once,
   and offers the exact recorded identity for review. Select it and choose
   **Add Recorded**. The receipt must say MANUAL / OBSERVE / DISARMED.
   Observation is automatic whenever the page or daemon sees `finalOutput`.
   If the output already finished before observation, arm one durable future
   capture and start only that intended craft again:

   ```sh
   ae2-workflow capture-next
   ae2-workflow evidence
   ```

   When daemon ownership and Global Auto are explicitly OFF, that newly armed
   capture starts a detached capture-only worker. It polls no faster than once
   per second, performs no planning or submission, and stops at
   `CONSUMED`, `AMBIGUOUS`, `EXPIRED`, or its TTL. Evidence is deduplicated and
   retained under the immutable paged `/var/oc/ae2-evidence-v2` store; releases
   and `oc-config-migrate apply` do not erase it. Authority is fenced by the
   workflow namespace, Maintainer host, and AE2 grid so copied or stale evidence
   cannot silently authorize another installation. Facts are immutable,
   namespace associations and transaction receipts are bounded files, and every
   list or Fleet read returns at most 32 records instead of loading a monolithic
   ledger. This binds Maintainer policy to an existing AE2 pattern; it does not create the AE2 pattern.
   Review Flow thresholds and caps before enabling Auto,
   and arm only after stock and recipe status are valid.
9. To repair old, incomplete, or drifted workflow identities, use
   **AE2 -> Daemon -> Danger -> Reconcile Recorded**. The first click previews
   exact repair/add/conflict counts. Preview token v2 binds the canonical raw and
   quiesced workflow snapshots, evidence generation, namespace/host/grid
   authority, stable workflow scope, bounded page cursor, and exact
   record/outcome digests; confirm only that consequence-stable preview.
   The daemon then applies its maintenance brake, turns Global Auto off, disarms
   managed rows, drains existing request ownership, persists fresh zero proof,
   installs a workflow-root mutation fence, and only then claims and
   compare-and-swap commits the referenced evidence by stable workflow ID.
   Concurrent workflow edits cannot pass that fence. `configIndex` provenance
   is repair-only and is claimed rather than transferred as authority. Fleet
   mode processes at most one 32-record page per daemon tick, durably advances
   its cursor and counts, retains the brake between pages, and resumes the same
   consequence-bound transaction after a restart. It repairs exact-provenance
   rows and adds uniquely supported unclaimed outputs;
   it never invents a legacy label-only row/output pairing. Ambiguous rows are
   visibly deferred to selected zero-text record pairing/capture, where the
   operator chooses the intended recorded result if several new outputs exist,
   without registry/damage/NBT/topology input. The shell surface is equivalent:

   ```sh
   ae2-workflow reconcile
   ae2-workflow reconcile CONFIRM
   ```

   Wait for every bounded page to finish and for `COMPLETE SAFE` before
   continuing. A stale preview, changed authority/evidence, foreign workflow
   edit, blocked or ambiguous plan, partial claim, or missing/conflicting
   identity finishes `FAILED SAFE`; an uncommitted page makes no workflow
   change, and every failure retains the brake for deterministic recovery. It is
   never guessed or overwritten. Reopen Recorded Add, choose the intended
   human-readable recorded output with zero registry/damage/NBT/topology text,
   or start only the intended craft while capture is active, then reconcile
   again.

   `X Stop All` is not an immediate worker kill. It engages the same brake,
   disables Global Auto, disarms, drains lifecycle/persistence ownership, proves
   durable zero, records daemon OFF, and only then exits. Keep this Dashboard
   open until its one-second receipt polling reports `COMPLETE SAFE`; the first
   accepted message is not stopped-state proof.
10. Back in **AE2 -> Daemon**, under **Maintainer Settings - Fluid Stock API**,
   click **Configure 2.8.4**.
11. Do not type a registry identity or topology revision. Configure loads exact
    ordinary-fluid identities already present in recorded evidence or workflow
    policy, excludes the Auto target set, and probes one candidate per second
    with exact AE2FC `getItemInNetwork` until the first currently positive fluid
    is proven. No plural-fluid or whole-grid read is used.
12. If setup reports that no recorded non-auto positive fluid exists, open Add
    Recorded Recipe, start/craft one ordinary fluid outside the Auto set while
    bounded output recording is active, save its evidence, and click Configure
    again. Never invent or type its identity/revision into the Dashboard.
13. Review the selected canary, generated monotonic `AUTO-Rn` topology epoch,
    and eligible/excluded counts. Every intended ordinary auto-fluid identity
    must be eligible; excluded/tagged/invalid rows receive no global authority.
14. Click **Lock Profile**, read the pending physical attestation, then click
    **Lock Profile** again within 15 seconds. This confirms a powered/channelled
    AE2FC Fluid Discretizer and no external or nested AE inventories on this grid.
15. Verify the status strip reads `Fluid Stock 2.8.4 AE2FC` and the detail reads
    `LOCKED ... pinned=<count> exact fluids` with the reviewed count.
16. Press Ctrl+R or leave/reopen **AE2 -> Stock**. Every intended ordinary fluid
    must show a numeric mB value; an absent reviewed fluid must show `0 mB`, not
    `ERR`. No per-fluid bind, conversion, rebind, or seed batch is required for
    ordinary exact fluids; only an invalid legacy wrapper needs the one-time
    identity repair described above.

If the profile says `BLOCKED`, leave automation off and correct the exact reason.
Adding/removing/rebinding an auto fluid or switching it between manual and auto
intentionally blocks the entire pin until it is reviewed and relocked under a
new generated `AUTO-Rn` epoch. Click Configure again; do not type or reuse a
revision. Never solve that guard by enabling broad AE2 grid scans. The typed
`ae2-workflow set-fluid-stock-global` command remains emergency compatibility
only, not the normal Dashboard setup path.

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
