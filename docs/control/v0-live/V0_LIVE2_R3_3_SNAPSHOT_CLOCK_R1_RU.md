# LIVE.2 R3.3 — server clock at the Earth remote presentation boundary

## Subject and evidence scope

Parent: 9299ef3e088d02eeee3b3eafaef5d256c782837e.
The corrected R3.2 human report supplied in chat describes approximately 80 minutes without a watchdog stall report, monotonic server progress, zero diagnostic scope repairs, and continuing remote HOLD/jitter. This note records that supplied summary, not a copy of the raw local Windows logs.

PR #703 and main must not move on the strength of this patch alone. Full world/core P2 instability remains a separate unresolved gate. Current-main integration is not claimed.

## Confirmed source defect

PlayerStateSnapshot.create writes server_tick, revision, and authority_epoch.
EarthApp._on_m3_replica_updated passes that full snapshot through EarthM3RemoteSpectatorPresenter.
The wrapper passed it unchanged to RemotePlayerPresenter, which expects snapshot_revision.
The delegate's parent is the wrapper, not EarthApp; its parent-runtime lookup fails and its legacy fallback invents a tick from state_revision / number of calls.
Thus a perfectly delivered 20Hz stream can be sampled against the wrong 60Hz timeline. A high HOLD count alone cannot identify packet loss.

## Bounded repair

Normalize revision to snapshot_revision in both Earth wrapper setup and update.
Retain the exact authoritative server_tick and authority_epoch.
Accept the existing compact NX5 context for compatibility.
Reject missing, fractional, or conflicting clock metadata instead of silently fabricating time.
Do not mutate the input envelope, PlayerStateSnapshot schema, interpolation coefficients, transport mapping, rotation, predictor, or canonical owners.

Separate wrapper-call arrivals from accepted interpolation samples; preserve the legacy max_snapshot_interval_ms field but add an explicit max_accepted_sample_interval_ms alias. Neither field is raw network receive timing.
Add sample-mode elapsed render milliseconds to compare 60/144/240fps observations without comparing raw frame counts.

## Tests

Use actual Earth wrapper plus the existing delegate/interpolator, not only Interpolator.sample_at_render_tick.
Use a real canonical PlayerStateSnapshot envelope.
Verify canonical clock preservation, existing compact-context compatibility, nonmutation, malformed metadata rejection, duplicate handling, and epoch reset/stale epoch rejection.
Replay a deterministic 20Hz stream with 60Hz server ticks at 60/144/240 render FPS; require interpolation after warmup and no HOLD without a delivery gap.
Then omit samples for one second; HOLD must still be observable.
Negative control loads the exact baseline wrapper extracted with git show and requires the specific semantic mismatch server_tick=6000 -> actual_tick=1. A parse failure is not a passing negative control.

## Watchdog caveat, not patched here

On the parent revision, max_elapsed_ms is updated at every scope exit, including outer scopes. The watchdog worker only examines the innermost scope every 250ms. exit() does not emit a threshold event. Therefore an outer scope can finish after 2796ms without a live soft report if its nested scopes are shorter or sampling misses it.
The supplied value must not be dismissed as proof of a healthy server. A later bounded diagnostic patch should report slow completed scopes with source=EXIT, exact stage/token, and live/completed distinction, without recreating leaked active tokens.

## Acceptance

A focused Windows PASS would validate this clock adapter and its regressions, not prove that all human jitter is fixed or that transport starvation is absent.
After the exact gate, compare the same short movement-only A/B session. Capture accepted server tick, interpolator estimated/render tick, epoch, wrapper arrivals versus accepted samples, mode elapsed milliseconds, and local reconciliation counter deltas within one transport epoch.
If wire arrivals are still in doubt, measure server snapshot emission and client boundary receive/replica acceptance separately rather than inferring them from max_snapshot_interval_ms.
