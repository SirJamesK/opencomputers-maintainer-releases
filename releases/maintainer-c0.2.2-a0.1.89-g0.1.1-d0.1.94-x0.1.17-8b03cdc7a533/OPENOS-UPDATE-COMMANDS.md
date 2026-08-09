# Exact Maintainer OpenOS Update Commands

Use this sheet only for release `maintainer-c0.2.2-a0.1.89-g0.1.1-d0.1.94-x0.1.17-8b03cdc7a533`. The four public artifacts were verified byte-for-byte at the immutable public commit below.

- Release: `maintainer-c0.2.2-a0.1.89-g0.1.1-d0.1.94-x0.1.17-8b03cdc7a533`
- Public repository: `SirJamesK/opencomputers-maintainer-releases`
- Public commit: `6e176f45aaff97a8279d0e3e86f7e906fd2ff915`
- Private source commit: `5d08d64438cd688b4a2ba9ee860c7c11d834a7f8`
- Systems: Core 0.2.2, AE2 0.1.89, GT Power 0.1.1, Dashboard 0.1.94, Commands 0.1.17
- Targets: 227
- Bundle SHA-256: `84bd62d0a9841164d57e88372e717752fec4b20a6705c429c737258566ca6ebb`

Before starting: stop the Maintainer, exit every Dashboard, confirm the daemon policy is OFF, and obtain a confirmed no-backup maintenance window.

Mutating installer commands serialize through live OpenOS process authority and
create no filesystem lock. A crash releases that in-memory authority
automatically; `status` plus the durable phase/cursor and hash-proven artifacts
identify the exact action to retry. `unlock` is not part of normal operation. If
`status` reports a **legacy installer lock** created by an older installer, first
prove that installer has stopped, then remove only that legacy evidence with
`lua /home/oc-release.lua unlock NO_BACKUP CONFIRM`.

No mount path or filesystem address is entered by the operator. `plan`, `stage`,
and `status` inspect OpenOS mounts automatically. If `/` lacks transaction
headroom, the installer may select the sole eligible writable non-root
filesystem larger than 4 MiB that can hold the runtime. Zero candidates or
multiple candidates block with diagnostics; it never chooses by label, mount
suffix, size rank, or enumeration order.

Only `/usr/lib/oc` program libraries may live in the external immutable release.
`/lib/oc_bootstrap.lua`, named commands, RC wrappers, and home launchers remain
on `/`. The root selector is `/etc/oc/maintainer-runtime.cfg`; the selected
volume carries `/.oc-platform/maintainer/active`. The resolver matches their
full filesystem identity and release digests on every fresh process, so a
different `/mnt/...` suffix after reboot is expected. `/etc` and `/var` remain
host-local and are never imported from the program volume. If status reports
missing, changed, corrupt, or ambiguous runtime storage, leave automation off
and correct that exact condition rather than copying or editing either marker.
External `finalize` removes declared root library duplicates so later
selector-loss discovery cannot downgrade to stale root code. Older versioned
external slots are retained and not automatically pruned; watch the free/total
capacity shown by `status` and do not delete slots without a reviewed ownership
inventory.

This release treats unreadable daemon policy as a maintenance brake, not an OFF
default. Normal daemon/evidence mutation writes and verifies only the stable
primary pathname and creates no lock/stage/prior file. Its recovery-aware loader
may consume a retained `.previous` from an older interrupted promotion;
otherwise every request boundary makes zero physical AE2 invocations until
valid policy is restored. Do not delete policy evidence to make this gate
disappear.

## 1. Download and stage

```sh
wget -f https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/6e176f45aaff97a8279d0e3e86f7e906fd2ff915/releases/maintainer-c0.2.2-a0.1.89-g0.1.1-d0.1.94-x0.1.17-8b03cdc7a533/install.lua /home/oc-release.lua
lua /home/oc-release.lua plan
lua /home/oc-release.lua status
lua /home/oc-release.lua stage https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/6e176f45aaff97a8279d0e3e86f7e906fd2ff915/releases/maintainer-c0.2.2-a0.1.89-g0.1.1-d0.1.94-x0.1.17-8b03cdc7a533/bundle.ocb NO_BACKUP
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
=assert(require("oc_bootstrap").activate())
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
=type(require("oc.ae2.maintainer_commissioning").status)
```

Runtime activation must succeed, and all twelve function expressions must print
`"function"`. Press Ctrl+D, then run:

```sh
oc-config-migrate verify-install
oc-config-migrate status
ae2-probe
oc-dashboard
```

`verify-install` is strictly read-only: it checks the complete matched placement
without activating, requesting, or launching commissioning. `status` is also
observational. If status reports that readable policy conversion is required,
keep daemon ownership OFF and the Dashboard closed, then run:

```sh
oc-config-migrate apply CONFIRM
```

A successful apply reports the conversion and durably requests the same
automatic GTNH 2.8.4 continuation used by release finalization and AE2 startup.
If enqueueing fails after conversion, the command states that partial outcome;
rerunning apply is idempotent. If no conversion is required, skip this command.

Smoke-test the Dashboard while Maintainer ownership remains OFF; it may already
show durable automatic commissioning progress. Then exit the Dashboard, confirm
daemon policy remains OFF, and run:

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

The release transaction must now report FINALIZED. Finalization writes the
immutable `post_install=ae2_gtnh_284_auto_v1` receipt, persists the commissioning
request, and wakes the already-running AE2 RC broker. A missed wake cannot make
a verified release non-final or strand the request; `/etc/rc.d/oc-ae2.lua` owns
the only commissioning worker and replays the same durable transaction only
from the exact finalized release receipt after boot.

## 5. Observe automatic GTNH 2.8.4 commissioning

Run at most one `oc-dashboard` writer and open **AE2 -> Daemon** only to observe.
The status strip renders durable `AUTO REQUESTED`, stop/configure/probe/repair/
restore phases, `COMPLETE`, or the exact blocked reason. A blocked receipt offers
**Retry Automatically**; **Commission Automatically** and **Recheck
Automatically** submit the same idempotent request. These controls are optional
replay surfaces, not attestations, and the Dashboard need not remain open.

The coordinator preserves prior daemon, Global Auto, and exact per-row arming
intent. It performs owner-scoped Safe Stop, selects the GTNH 2.8.4 Craft API,
commissions Fluid Stock, and restores that intent. Safe Stop does not scan, wait
for, or cancel unrelated AE2 CPU jobs. A selected wrapper repair accepts only
its own causal named-CPU completion and exact workflow/config scope; unrelated
CPU activity neither satisfies nor gates that selected target. When complete,
verify `Storage Guard SCALAR ONLY` and `Craft API 2.8.4 FILTER`.

The Craft selector is global and preserves valid workflow identities,
thresholds, and batches. Recipe identity comes from structured AE2 CPU
`finalOutput` evidence, never typed registry/damage/NBT/topology text or a
storage snapshot.

Optional recipe onboarding and identity repair remain available after automatic
commissioning:

1. To add a new managed operation whose AE2 crafting pattern already exists,
   open **AE2 -> Targets -> Find / Add Craft**. The page automatically lists
   unclaimed structured CPU recordings. Select an existing result, or press
   **F Look For**, enter a visible label hint, and then start only that intended
   AE2 craft once. The hint scopes discovery but is never saved as identity.
   Select the exact recorded output and choose **Add Disarmed**. The receipt
   must say MANUAL / OBSERVE / DISARMED. Maintainer and Global Auto keep their
   existing ON/OFF states; ordinary Add never invokes the repair brake. If no
   matching output was observed, the page arms one durable future capture.
   The shell can arm and inspect the same contract:

   ```sh
   ae2-workflow capture-next
   ae2-workflow evidence
   ```

   When daemon ownership is absent, that newly armed capture starts a detached
   capture-only worker with Global Auto either ON or OFF.
   It polls no faster than once per second, records unrelated completions without
   letting them consume a query-scoped capture, performs no planning or submission,
   and stops at
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
2. To repair old, incomplete, or drifted workflow identities, use
   **AE2 -> Daemon -> Danger -> Reconcile Recorded**. The first click previews
   exact repair/add/conflict counts. Preview token v2 binds the canonical raw and
   quiesced workflow snapshots, evidence generation, namespace/host/grid
   authority, stable workflow scope, bounded page cursor, and exact
   record/outcome digests; confirm only that consequence-stable preview.
   The daemon then applies its maintenance brake, turns Global Auto off, disarms
   managed rows, drains existing request ownership, requires fresh whole-grid
   CPU/final-output quiescence, persists fresh zero proof after both scopes clear,
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
   never guessed or overwritten. Reopen Find / Add Craft, choose the intended
   human-readable recorded output with zero registry/damage/NBT/topology text,
   or start only the intended craft while capture is active, then reconcile
   again.

   `X Stop All` is not an immediate worker kill. It engages the same brake,
   disables Global Auto, disarms, drains Maintainer-owned lifecycle/persistence,
   proves durable owned-work zero, records daemon OFF, and only then exits. It
   does not scan, wait for, or cancel unrelated AE2 CPU jobs. Keep this Dashboard
   open until its one-second receipt polling reports `COMPLETE SAFE`; the first
   accepted message is not stopped-state proof.
The automatic Fluid Stock phase creates a v3 authority marker from one measured
exact-positive AE2FC canary receipt. It tries canonical `water` first, excludes
the Auto target set, and probes one candidate per second with exact AE2FC
`getItemInNetwork`; the durable proof binds the exact method, positive count,
OpenComputers host, current AE2 grid, and observation time. The coordinator then
commits the generated monotonic `AUTO-Rn` epoch. No plural-fluid or whole-grid
storage read is used.

The profile also names `dedicated_ae2fc_stock_domain_v1` as a required
deployment invariant. This is an explicit server-deployment contract, not a
false claim that Lua inspected every cable or proved physical absence of every
external or nested inventory. Keep that dedicated domain true operationally;
the measured canary proves exact API capability on the bound grid, not unseen
physical topology.

If an Auto row is an item-shaped tagged AE2FC wrapper, commissioning detects it
before stock authority and scopes causal capture to the selected named CPU,
workflow ID, config index, normalized fluid label, and exact repair epoch. It
accepts only one uniquely linked exact ordinary-fluid recording. Missing proof
waits automatically for at most 480 seconds inside the 600-second commissioning
epoch; recovery never resends the craft. If the exact result remains
API-ambiguous at that boundary, only that signature-bound row is durably
quarantined, the remaining profile commits as `DEGRADED`, prior daemon/Global
Auto/arming intent is restored, and commissioning reaches `COMPLETE`. Label
mismatch, malformed/tagged evidence, generic CPU observation, or an unrelated
recording cannot authorize another row. A proven repair retains the row's prior
Auto policy and thresholds and restores its saved arming intent only through
the coordinator's final policy restore.

No positive candidate keeps the durable scan active and automatically retryable;
it does not become a manual-unblock state. A positive canary with zero eligible
Auto fluids commits `2.8.4 STANDBY / READY FOR FIRST AUTO FLUID`. A
target-local excluded/tagged/invalid row receives no global authority and does
not disable unrelated eligible rows.

After completion, verify `Fluid Stock 2.8.4 AE2FC` with `LOCKED ...
enrolled=<count> exact fluids`, the valid STANDBY state, or `2.8.4 DEGRADED`
with an exact isolated-row count. Press Ctrl+R or leave/reopen **AE2 -> Stock**.
Every non-quarantined intended ordinary fluid must show a numeric mB value; an
exact lookup returning nil under matching v3 authority must show `0 mB`, not
`ERR`. That zero is an exact API result, not physical absence proof. No per-fluid
bind, conversion, rebind, seed batch, or final-enable action is required.

Later exact ordinary Auto-fluid additions, removals, rebinds, or mode changes
enroll immediately through the existing locked v3 profile; they require no
profile rewrite, seed craft, or new epoch. If the canary enters Auto, the profile
blocks because its independent witness was destroyed. A host, grid, Fluid
Discretizer, or declared dedicated-deployment change invalidates the old
invariant: leave automation off, disable the profile, correct deployment, and
use **Commission Automatically** to generate the next `AUTO-Rn`. Never enable a
broad AE2 scan to bypass this contract. Typed `ae2-workflow
set-fluid-stock-global` remains emergency compatibility only.

## 6. Optional post-commission smoke test

Commissioning has already restored the captured production intent; this section
is optional and is not an install, commissioning, or final-enable gate. For a
planned cold smoke test, deliberately turn automation off, select one
non-quarantined ordinary fluid row whose stock is numeric, and press `M` once.
Keep one Dashboard writer and wait one full configured daemon interval before
another cold GTNH 2.8.4 test. After the request shows `PLANNING`, `ACCEPTED`, and
a terminal lifecycle, recheck that Fluid Stock remains `2.8.4 AE2FC` or the
expected `2.8.4 DEGRADED` state. Restore only the Global Auto and daemon settings
you deliberately changed for the test. Confirm an armed below-threshold fluid
submits at most one batch and returns to a numeric mB value; investigate any
non-quarantined intended fluid that says `ERR`.

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
