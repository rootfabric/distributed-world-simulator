# V0-P1 R6 — Inventory parity Repair Map

Date: 2026-08-15
Branch: `feature/v0-p1-world-items-containers`
Risk: HIGH
Status: FIX_REQUIRED / IMPLEMENTATION AUTHORIZED WITHIN P1

## Trigger

Windows exact-head verification of R5 stopped on Godot 4.7.1 parser error at `m5_v0_modern_inventory_shell_r5.gd:145`. The branch subsequently received the narrow explicit-`bool` correction at `2c6443ed381f9f699a8d8bc53cddc2f6db720fd4`.

The parser defect is therefore no longer the remaining product gap. The next bounded gap is behavior parity with the accepted item UX donor `agent/inventory-carry-stack-sort-rev6@535eebd670473f7ab6557492a356bd47a03db763`.

## Finding R6.1 — incompatible occupied slot cannot swap

### Current behavior

P1 canonical `item.transfer` treats every non-empty `target_item_id` as a stack target. For two different definitions this reaches `_transfer_to_stack()` and returns `STACK_DEFINITION_MISMATCH`.

The accepted 7-Days-like donor instead treats a whole carried stack dropped onto an incompatible occupied slot as a swap: the carried item occupies the target slot and the displaced item remains on the cursor.

### Root cause

R5 restored canonical empty-slot identity (`location.slot_index`) but did not port the canonical occupied-slot transaction. Presentation already supplies both target slot and target item identity; the missing owner is the server-side P1 Item Graph adapter.

### Canonical fix location

`scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd`

The existing P1 adapter remains the sole canonical Item Graph owner. `item.transfer` keeps its public command type. When `target_item_id` is compatible, existing stack behavior remains. When definitions are incompatible, a whole-stack transfer performs one atomic slot-location swap after validating the actual canonical occupant.

No client-side Item Graph mutation and no second inventory truth are allowed.

### Required safety rules

- partial incompatible transfer rejects with `SWAP_REQUIRES_FULL_STACK`;
- target item must be the actual canonical occupant of the requested target slot;
- source and target must be accessible to the player;
- inventory/container membership arrays remain compatibility data while `location.slot_index` remains authoritative identity;
- hotbar-assigned item swap is not silently reinterpreted as backpack slot swap;
- one canonical command produces one revision/tick advance through the inherited execute boundary.

## Finding R6.2 — rejected cursor placement destroys presentation carry

### Current behavior

`m4_inventory_transient_state.gd` clears `_cursor` on any rejected canonical command.

### Donor behavior

A rejected place leaves the carried item on the cursor; only successful consumption, explicit cancel, or authoritative reconciliation ends carry.

### Canonical correction

Keep failed operations removed from the pending set, but preserve the presentation-only cursor. The next snapshot still owns canonical truth.

## Finding R6.3 — successful swap must continue carry with displaced item

A successful atomic swap cannot be treated as an ordinary full placement because the displaced target becomes the new carried item.

The P1 bridge must replace only transient cursor metadata from the canonical swap result: displaced item id, quantity and its new canonical source container/slot. The bridge must not mutate Item Graph state locally.

## Finding R6.4 — R5 sort reorders but does not merge compatible stacks

The accepted rev6 sort sequence first consolidates compatible stacks up to `max_stack`, then reorders survivors by display name. Current P1 R5 only reorders.

The P1 bridge should perform serial canonical `item.transfer` stack merges using the derived cell `max_stack`, refresh after each confirmed command, then run the existing authoritative slot reorder. No projection-only fake sort is allowed.

## Validation

Focused R6 regression must prove at minimum:

1. incompatible whole-stack inventory swap succeeds atomically;
2. both canonical `location.slot_index` values exchange;
3. stale/mismatched occupied target is rejected without mutation;
4. partial incompatible swap is rejected;
5. durable export/restore preserves swapped slots;
6. rejected cursor placement preserves presentation carry;
7. successful swap can replace transient cursor with the displaced item;
8. sort merge/reorder continues to use canonical commands only;
9. existing R5 empty-slot move and durable reconstruction remain green;
10. exact Godot 4.7.1 double Windows preflight is parser/startup-clean before graphical acceptance.

## Non-goals

- no second Item Graph;
- no client authority;
- no persistence schema redesign;
- no network protocol redesign;
- no hotbar semantic rewrite in this repair;
- no global V0 acceptance claim;
- no merge from implementer role.
