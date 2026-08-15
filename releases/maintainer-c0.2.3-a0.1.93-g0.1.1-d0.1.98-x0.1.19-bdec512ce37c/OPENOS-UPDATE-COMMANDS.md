# Exact Maintainer OpenOS Update Commands

Use this sheet only for release `maintainer-c0.2.3-a0.1.93-g0.1.1-d0.1.98-x0.1.19-bdec512ce37c`. The four public artifacts were verified byte-for-byte at the immutable public commit below.

- Release: `maintainer-c0.2.3-a0.1.93-g0.1.1-d0.1.98-x0.1.19-bdec512ce37c`
- Public repository: `SirJamesK/opencomputers-maintainer-releases`
- Public commit: `bcf4d41496073757164fca33134149c552dcda44`
- Private source commit: `9a1a8ae5ff211e5b736331aac5923be562a594c3`
- Systems: Core 0.2.3, AE2 0.1.93, GT Power 0.1.1, Dashboard 0.1.98, Commands 0.1.19
- Targets: 256
- Bundle SHA-256: `9b4e42fb90f3f06e83c33dc2585c03b5125475abef93cbe56b3e6b9d6fcd0189`

Before starting, obtain a confirmed no-backup maintenance window. Staging installs
a durable deployment inhibit while preserving the operator's desired daemon and
Craft API profile. Before the one apply reboot, exit every Dashboard and
Maintainer process; do not manually erase or force either desired setting OFF.

Mutating installer commands serialize through live OpenOS process authority and
create no filesystem lock. A crash releases that in-memory authority
automatically; `status` plus the durable phase/cursor and hash-proven artifacts
identify the exact action to retry. `unlock` is not part of normal operation. If
`status` reports a **legacy installer lock** created by an older installer, first
prove that installer has stopped, then remove only that legacy evidence with
`lua /home/oc-release.lua unlock NO_BACKUP CONFIRM`. If that fixed legacy path
is malformed, use the separately confirmed metadata recovery below instead.

No mount path or filesystem address is entered during normal operation. `plan`,
`stage`, and `status` inspect OpenOS mounts automatically. If `/` lacks transaction
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

If transaction state is corrupt/current-or-older, its inhibit or full-power
marker is orphaned, an expected metadata file became a directory, or the local
runtime is torn, close every Dashboard, AE2 command, migration command, RC
broker, and other release installer. Then run only the exact recovery action
printed by `status` or its error:

```sh
lua /home/oc-release.lua recover-installer OFFLINE NO_BACKUP CONFIRM
```

The command auto-selects only a coherent selector, one valid host-bound marker,
or—when no marker exists—the single provable local root. If it reports zero or
multiple choices, repeat it with one full UUID printed by the diagnostic:

```sh
lua /home/oc-release.lua recover-installer OFFLINE NO_BACKUP CONFIRM ROOT <full-root-filesystem-uuid>
lua /home/oc-release.lua recover-installer OFFLINE NO_BACKUP CONFIRM EXTERNAL <full-filesystem-uuid>
```

Recovery never guesses, edits live payload bytes, erases valid selected or
unselected payload roots, or runs implicitly from `status`, `next`, or `apply`.
It snapshots bounded metadata directory trees leaf-for-leaf, including old
recovery logs, writes and reads back one exact archive at
`/var/oc/releases/maintainer/installer-recovery.prior`, rechecks every source
byte/path and the bounded process list, then publishes current-release
`STAGING` plus a recovery inhibit. `cancel` remains unavailable until one full
verified `stage` replaces that fence; immediately rerun the normal immutable
bundle `stage` command. Restage durably reserves one of two fixed transaction
artifact slots before cleaning stage residue; existing rollback payloads force
the other slot, and a retry reuses the recorded slot instead of creating an
unbounded suffix history. No rollback payload is overwritten. A recognizable
newer state schema is retained for its matching pinned installer, never
downgraded by this command. Only after verified `FINALIZING` makes rollback
irreversible does the installer read/hash both fixed namespaces, recheck each
exact release-owned path, and retire them; `discard` does not erase the older
slot.

This release treats unreadable daemon policy as a maintenance brake, not an OFF
default. Normal daemon/evidence mutation writes and verifies only the stable
primary pathname and creates no lock/stage/prior file. Its recovery-aware loader
may consume a retained `.previous` from an older interrupted promotion;
otherwise every request boundary makes zero physical AE2 invocations until
valid policy is restored. Do not delete policy evidence to make this gate
disappear.

After a verified stage, `status` may advertise the exact out-of-band action
`recover-control OFFLINE NO_BACKUP CONFIRM`. Run it only when that exact line is
shown and every Dashboard/Maintainer process is closed:

```sh
lua /home/oc-release.lua recover-control OFFLINE NO_BACKUP CONFIRM
lua /home/oc-release.lua status
```

The staged installer accepts this action only under its own exact-release
deployment inhibit. It preserves any readable OFF or inhibited-ON primary
byte-for-byte while archiving and removing exact stale/corrupt
`.new`/`.previous`/legacy-lock evidence. For an unreadable current-or-older
primary, the stronger explicit consent archives every bounded primary/side/lock
byte and installs deterministic clean OFF; differing current-or-older sides do
not create a permanent dead end. A newer schema, foreign inhibit, live process,
or changed successor evidence is always retained and refused. The original
evidence remains bounded and exact in the single release-owned
`/var/oc/releases/maintainer/daemon-control.prior` rollback artifact until the
transaction is discarded or finalized. Recovery writes a verified clean OFF
primary only when the primary was unreadable; it never changes
`/var/oc/ae2-maintainer.state` and does not consume the staged cold-boot proof.
`next` and `apply` never perform this repair implicitly.

## 1. Download and stage

```sh
wget -f https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/bcf4d41496073757164fca33134149c552dcda44/releases/maintainer-c0.2.3-a0.1.93-g0.1.1-d0.1.98-x0.1.19-bdec512ce37c/install.lua /home/oc-release.lua
lua /home/oc-release.lua plan
lua /home/oc-release.lua status
lua /home/oc-release.lua stage https://raw.githubusercontent.com/SirJamesK/opencomputers-maintainer-releases/bcf4d41496073757164fca33134149c552dcda44/releases/maintainer-c0.2.3-a0.1.93-g0.1.1-d0.1.98-x0.1.19-bdec512ce37c/bundle.ocb NO_BACKUP
lua /home/oc-release.lua status
```

The final status in this phase must be STAGED and must no longer advertise a
control recovery action. Then run:

```sh
shutdown
```

Wait until the computer is visibly OFF and manually power it on. Do not use reboot and do not start the Dashboard or Maintainer.

## 2. Apply

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua next OFFLINE NO_BACKUP CONFIRM
lua /home/oc-release.lua status
```

The final status in this phase must be APPLIED.

If status instead shows APPLIED plus `deployment recovery marker: yes`, the
payload finished but the final inhibit cleanup was interrupted.
Status routes `next` back through cold apply recovery: perform another full
shutdown and manual power-on, then run:

```sh
lua /home/oc-release.lua next OFFLINE NO_BACKUP CONFIRM
```

Never attempt finalize while that inhibit remains. The displayed `cancel OFFLINE NO_BACKUP CONFIRM` route remains a verified rollback.

## 3. Verify from fresh processes

```sh
lua
=assert(require("oc_bootstrap").activate())
=type(require("oc.ae2.workflows").prepareOnboarding)
=type(require("oc.ae2.workflows").pollOnboardingPreparation)
=type(require("oc.ae2.workflows").restoreOnboarding)
=type(require("oc.ae2.workflows").setCraftCompatibility)
=type(require("oc.ae2.workflows").desiredCraftCompatibilityStatus)
=type(require("oc.ae2.workflows").setDesiredCraftCompatibility)
=type(require("oc.ae2.workflows").convergeDesiredCraftCompatibility)
=type(require("oc.ae2.workflows").recoverDesiredCraftCompatibility)
=type(require("oc.ae2.workflows").cancelAllCrafts)
=type(require("oc.ae2.workflows").craftDraftsStatus)
=type(require("oc.ae2.workflows").addCraftDraft)
=type(require("oc.ae2.workflows").removeCraftDraft)
=type(require("oc.ae2.workflows").bindCraftDraft)
=type(require("oc.ae2.workflows").resetCraftDrafts)
=type(require("oc.ae2.workflows").resetInvalidWorkflow)
=type(require("oc.ae2.workflows").setFluidStockCompatibility)
=type(require("oc.ae2.workflows").listIdentityEvidence)
=type(require("oc.ae2.workflows").addRecorded)
=type(require("oc.ae2.identity_evidence_v2_page").read)
=type(require("oc.ae2.identity_capture_worker").start)
=type(require("oc.ae2.workflow_identity_transaction").reconcileAll)
=type(require("oc.ae2.maintainer_daemon_control").reconcileRecorded)
=type(require("oc.ae2.maintainer_daemon_control").recoverControlPlane)
=type(require("oc.ae2.maintainer_daemon_control").abandonReconcileToSafeStop)
=type(require("oc.ae2.maintainer_commissioning").status)
```

Runtime activation must succeed, and all twenty-five function expressions must
print `"function"`. These five recovery-aware expressions prove the installed
runtime can explicitly
recover desired-profile control, reset corrupt draft/workflow control, restore a
verified daemon-OFF control plane, and abandon failed reconciliation into Safe
Stop. They are presence checks only; `type(...)` performs no recovery mutation.

Press Ctrl+D, then run:

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

A successful apply reports the conversion and durably requests the selected
Craft API profile used by release finalization and AE2 startup. A host with no
saved desired profile defaults once to GTNH 2.8.4 water-first commissioning.
If enqueueing fails after conversion, the command states that partial outcome;
rerunning apply is idempotent. If no conversion is required, skip this command.

Smoke-test the Dashboard from the new runtime by opening **AE2 -> Daemon**, but
do not start Fluid Autopilot before finalization. The normal page has one
**Start 2.8.4 Fluids** action, cached progress, and the independent owner-scoped
`X Stop Maintainer`; it has no profile selector, interval editor, manual arming
ritual, or whole-grid cancellation control. Finalization is metadata-only and
requires no second reboot.

## 4. Finalize after successful verification

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua next NO_BACKUP VERIFIED CONFIRM
lua /home/oc-release.lua status
oc-config-migrate verify-install
oc-config-migrate status
```

The release transaction must now report FINALIZED. Finalization writes the
immutable `post_install=ae2_profile_converge_v1` receipt, starts or reuses the
deployed `/etc/rc.d/oc-ae2.lua` service, proves its sole RC-owned broker is
running, then persists and wakes desired-profile convergence. Broker startup or
request failure retains recoverable `FINALIZING` state and the exact `next`
command retries it; cleanup occurs only after the handoff succeeds. A missed
wake remains safe because the running bounded watchdog polls durable intent.
Later boot replay accepts only the exact finalized release receipt.

## 5. Bring GTNH 2.8.4 fluids online with one action

Run at most one `oc-dashboard` writer and open **AE2 -> Daemon**. Finalization,
successful migration, or boot may already show Starting, Restoring, automatic
retry, or Online; in any of those states only observe. Otherwise press the
visible **Start 2.8.4 Fluids** once. That is the only required Fluid action: it
durably saves the complete Fluid Autopilot intent before returning, and the AE2
RC service continues every remaining phase. The Dashboard may then close
without pausing setup.

The cached status strip renders the exact stop/configure/probe/repair/restore
phase and then `Autopilot ONLINE`, or a specific blocked reason. A blocked or
drifted persisted Autopilot state is read-only and reports automatic retry;
correct any stated external condition and the RC broker creates the next bounded
attempt itself. There is no repeat Start/Retry, second Configure, Attest,
profile-selection, Global Auto, row-arming, or final-enable action.

The coordinator performs its owner-scoped Safe Stop internally, selects the GTNH
2.8.4 Craft API, commissions Fluid Stock, turns Global Auto ON, arms every
eligible non-quarantined Auto fluid row, and restores daemon ownership. It does
not scan, wait for, or cancel unrelated AE2 CPU jobs. A selected wrapper repair
accepts only its own causal named-CPU completion and exact workflow/config scope;
unrelated CPU activity neither satisfies nor gates that selected target. When
complete, verify the Daemon strip reports `Autopilot ONLINE`, `Daemon ON`, and
`Global Auto ON`. The detailed **AE2 -> Maintainer** status must also report
`Storage Guard SCALAR ONLY` and `Craft API 2.8.4 FILTER`.

The lower-level Craft API selector remains available through `ae2-workflow` for
explicit compatibility and future migrations; it is not another Dashboard step
for 2.8.4 Fluid Autopilot. Recipe identity comes from structured AE2 CPU
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
2. To repair one old, incomplete, or drifted workflow identity, open that
   target's **Flow** page and use **R Reconcile Recorded** when the binding-error
   action is shown. For a whole-fleet repair, use the shell preview below. The
   preview prints exact repair/add/conflict counts and the serial required by
   confirmation. Preview token v2 binds the canonical raw and quiesced workflow
   snapshots, evidence generation, namespace/host/grid authority, stable
   workflow scope, bounded page cursor, and exact record/outcome digests;
   confirm only that consequence-stable preview.
   Both scopes apply the maintenance brake, turn Global Auto off, disarm managed
   rows, drain Maintainer-owned request state, persist fresh local ownership-zero
   proof, and install a workflow-root mutation fence before any evidence claim.
   A selected repair proceeds only from its exact row/record/grid/namespace fence
   and local ownership-zero proof; it never inspects or waits on unrelated CPU
   work. Fleet reconciliation alone additionally requires fresh whole-grid
   CPU/final-output quiescence before it claims otherwise unowned evidence and
   compare-and-swap commits the referenced rows by stable workflow ID.
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
   ae2-workflow reconcile CONFIRM <printed-serial>
   ```

   Monitor Daemon while `CONTROL LOCK RECONCILE/<phase>` advances through every
   bounded page. Success is that lock clearing after the final committed page.
   A stale preview, changed authority/evidence, foreign workflow edit, blocked or
   ambiguous plan, partial claim, or missing/conflicting identity retains
   `CONTROL LOCK RECONCILE/FAILED SAFE`; an uncommitted page makes no workflow
   change, and every failure retains the brake for deterministic recovery. It is
   never guessed or overwritten. Reopen Find / Add Craft, choose the intended
   human-readable recorded output with zero registry/damage/NBT/topology text,
   or start only the intended craft while capture is active, then reconcile
   again.

   `X Stop Maintainer` is not an immediate worker kill. It engages the same brake,
   disables Global Auto, disarms, drains Maintainer-owned lifecycle/persistence,
   proves durable owned-work zero, records daemon OFF, and only then exits. It
   does not scan, wait for, or cancel unrelated AE2 CPU jobs. Keep this Dashboard
   open when monitoring until its one-second refresh clears `CONTROL LOCK` and
   the command strip proves `Daemon OFF` and `Global Auto OFF`; a commissioning
   stop may also report `SAFE OFF VERIFIED`. The first accepted message is not
   stopped-state proof, although the RC service continues if the Dashboard
   closes. Dashboard exposes no whole-grid
   cancellation control or hotkey. The destructive break-glass path exists only
   as the exact shell command `ae2-maintainer cancel-all CONFIRM`; it attempts to
   brake new local submissions, then cancels every currently visible busy AE2 CPU
   on the connected grid and verifies two bounded idle scans. CPU ownership is
   not exposed by GTNH, so this shell command can cancel another player's grid
   job. It cannot cancel an unresolved CraftingStatus plan or work already
   executing in external machines. It also revokes Fluid Autopilot restart intent
   so cancellation cannot race an automatic restart; to resume later,
   return to AE2 -> Daemon and press Start 2.8.4 Fluids once.
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
quarantined, the remaining profile commits as `DEGRADED`, Global Auto and every
eligible non-quarantined Auto fluid row converge ON, daemon ownership resumes,
and commissioning reaches `COMPLETE`. Label
mismatch, malformed/tagged evidence, generic CPU observation, or an unrelated
recording cannot authorize another row. A proven repair retains the row's Auto
policy and thresholds; eligible Auto fluid rows arm through the coordinator,
while unrelated and noneligible rows retain their independent permissions.

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
invariant: the persistent broker detects live grid drift and schedules the next
`AUTO-Rn` automatically. Correct any reported physical deployment condition and
observe restoration; no repeat Fluid button is required. Never enable
a broad AE2 scan to bypass this contract. Typed `ae2-workflow
set-fluid-stock-global` remains emergency compatibility only.

## 6. Optional post-commission observation

`Autopilot ONLINE` is the completion proof; there is no additional smoke-test or
enablement gate. Do not turn the daemon, Global Auto, or fluid rows OFF merely to
test the release. During normal operation, if an armed ordinary fluid naturally
falls below its threshold, observe that it submits at most one batch, reaches a
terminal lifecycle, and returns to a numeric mB value. Recheck that Fluid Stock
remains `2.8.4 AE2FC` or the expected `2.8.4 DEGRADED` state. If no row is
naturally below threshold, no operator action is required. Investigate any
non-quarantined intended fluid that says `ERR`.

When the server later upgrades to GTNH 2.9, use the lower-level migration command
once; the normal 2.8.4 Dashboard intentionally has no version selector:

```sh
ae2-workflow craft-api select 2.9+
```

The desired selection saves immediately; the RC owner performs bounded
stop/apply/restore convergence, retires the 2.8.4 Fluid Stock authority, and
preserves the newest desired selection across a collision or reboot.

## Failure path instead of finalization

If fresh-process verification failed, keep every Dashboard and Maintainer process closed. After the required full shutdown, visible-OFF wait, and manual power-on, run:

```sh
lua /home/oc-release.lua status
lua /home/oc-release.lua rollback OFFLINE NO_BACKUP CONFIRM
lua /home/oc-release.lua status
lua /home/oc-release.lua discard NO_BACKUP CONFIRM
lua /home/oc-release.lua status
```
