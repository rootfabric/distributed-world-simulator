# MVP3 R13b — FRESH INDEPENDENT VERIFIER

Verifier-only carrier. DO NOT MERGE. Do not modify product/runtime/tests/acceptance data.

## Exact subject

```text
HEAD = f1d453fb2af49231c30bdc5cbe415ad199394446
TREE = f1697cc52c1abc7f1bb21922c5fab3b49a3c167d
FREEZE = freeze/v0-mvp3-r13b-f1d453fb-r1
R12 BASE = 91c0df9d9e9c36f3519110aea85b5884214b9278
CANONICAL MAIN = 7dfc68ab5a1e90254a1b7039807f275b5da04eef
```

Parent `V0-MVP-R1-WO-001` remains `IN_PROGRESS`.

Role: FRESH INDEPENDENT VERIFIER, not Implementer/Reviewer/Coordinator. Read-only. Return `PASS`, `FAIL`, or `INSUFFICIENT_EVIDENCE` with exact HEAD/TREE and independently derived reasons.

## Inputs that must be terminal/retrievable before verdict

1. Fresh R13 Reviewer on PR #621 for exact `f1d453fb...` (completed with no major issues; independently confirm no blocking inline findings).
2. R13 exact Linux graphical evidence run `34749737201`:
   - graphical job `103703953494` must be SUCCESS and artifact `10315018723` independently rehashed;
   - graphical artifact ZIP SHA-256 expected `b55a36c961d52fb5827dc7f821abf8019feeace82f69345b3015bfd7092646f1`;
   - historical failed control lane must be classified from raw log: Harness completed before `GIT_BRANCH_UNAVAILABLE` caused by detached validation-carrier branch context, not product bytes.
3. Separate exact full world/core gate MUST be inspected from workflow `MVP3 R13 Full World Core Exact Extended`:
   - run `34750914967`, job `103707193579` = terminal SUCCESS;
   - artifact `10316317299` (`mvp3-r13-f1d453fb-full-world-core-34750914967-1`);
   - artifact ZIP SHA-256 expected `35911d930a9f9ce79c9fd32ce2818eb952ade911e867a56016d30ac8dfa1985e`;
   - independently require exact HEAD/TREE, pinned Linux double Godot SHA `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`, clean tracked state, `world-regression-summary.json` `passed=true`, no failed/non-zero steps, literal `test_v0_p6_thirty_minute_soak` PASS, and `main_scene_cli_all` PASS;
   - known independent reduction: 1772/1772 manifest members matched; summary SHA-256 `39f7b7fc16ed790228a112f41fbae484288ab01d4efcf8482b4016a42353b9f0`, 333 declared/discovered tests, 338 steps, 0 failed, 0 non-zero, literal soak ~1804.077 s. Recheck rather than trusting this prose.
4. Exact Project Control run `34749699419` on repair PR #621 must be SUCCESS; inspect standard and directional reports, not only exit status.
5. Existing Windows physical-keyboard manual run must be retrievable byte-for-byte from evidence-only branch `evidence/v0-mvp3-r13b-manual-f1d453fb-r1` at exact evidence commit `96884d87b7e95d58595f02b1191261d7d3b8d4ce`. Do not accept the Implementer prose digest alone. Rehash every file and the index/report independently. Also inspect the hardened verifier workflow result after the carrier repair: it must validate the Windows engine SHA and `HUMAN_PHYSICAL_KEYBOARD`, not merely file digests/manual booleans.

If item 3 full world/core or item 5 raw manual bytes/provenance are unavailable, verdict must be `INSUFFICIENT_EVIDENCE`, not PASS.

## Verify R13 repair itself

Diff exact R12 base → R13 subject. Scope should remain bounded to the R13 Work Order, three MVP runtime files and two targeted tests.

### Source attestation repair

Independently establish that:
- producer `prepare_export` reaches a bounded stable JSON transport representation before checksum;
- checksum remains over the exact packet that crosses transport;
- target still requires current transfer/identity/epoch and exact packet equality;
- tamper without rehash, tamper with rehash, wrong identity, wrong epoch, unknown transfer and stale attestation all fail closed;
- no second authority owner or fallback path is introduced.

### Interactive ledger repair

Independently establish that 16384 is a bounded capacity correction for the 2-player × 60Hz × 120s session envelope, not an unbounded queue; exact replay does not consume a new slot; over-capacity still fails closed; eviction/retirement/admission semantics are unchanged.

## Exact graphical/native evidence

Independently reduce raw JSON/logs. Require:
- five distinct processes: gateway, authority/a, authority/b, client/a, client/b;
- A route exactly A→B→A;
- actual non-zero post-activation physical movement on B and after return A, with increasing input sequence/state revision and fixed 1/60 server receipt;
- B has its own non-zero fixed-tick movement, not observer-only evidence;
- connects=1 per client, disconnects=0, reconnects=0, respawns=0, identity_changes=0, gateway reconnects=0;
- stable logical player/entity/session and stable body/camera/surface instance IDs;
- immutable P7 bootstrap projection retained and no mutable terrain ownership introduced;
- automatic CI remains `manual_input_executed=false`.

## Windows manual evidence

Manual PASS is valid only if raw published bytes independently prove:
- subject exact `f1d453fb.../f1697cc5...` and Windows double Godot SHA `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`;
- report `godot_sha256` and raw manifest `engine_sha256` both equal that exact expected SHA;
- `manual_input_mode=true`, `manual_input_executed=true`, report method exactly `HUMAN_PHYSICAL_KEYBOARD`;
- report/manual subject is the frozen R13b product, not the verifier carrier;
- five processes exit 0;
- A→B→A plus post-activation movement both directions;
- B independent movement;
- no reconnect/disconnect/respawn/identity replacement;
- screenshots and logs are hash-bound to the same run;
- no raw bytes were regenerated during publication.

Implementer-reported manifest digest to compare, not trust:
`3075debd09a3f06e352387b430015204d3e1c095525dba1d958afcc1a7b03668`.

Implementer report digest to compare, not trust:
`a65b2352dba0d0394b90027b70a8beac87189deac7a00fa959b307d8704382da`.

## Verdict boundary

A Verifier PASS still does NOT create `PREDICATE_VERIFIED`, close MVP3, close parent, integrate PR #621, or merge main. Those are Coordinator actions after verifier result. Do not write runtime or acceptance files.
