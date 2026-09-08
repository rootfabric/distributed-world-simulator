# A5 RM-A5-21 / RM-A5-22 — Fresh Review Handoff

Exact candidate:
- HEAD: `3c88051b80fa66f277fa1f781ce49451bbc6f2ff`
- TREE: `f91a05ed333692a8486cc80748304f24dd499919`
- accepted base: `4b0f772ff39592262b853f7293bbd5403558b145`

Fresh review must not inherit prior PASS/FIX conclusions.

Re-falsify specifically:
1. RM-A5-21: any public/callable A5 path that can produce a `PARENT_TRANSFER` child without exact propagule + paid-parent validation; include caller-selected origin/endowment/ID attempts.
2. RM-A5-22: persisted maintenance histories that refund required maintenance while keeping conservation balanced; test survival-window lower bounds, development `grant_seq` evidence, reproduction events, alive/dead starvation policy and combinations thereof.
3. Regression interaction with RM-A5-18..20, persistence/restart, conservation, founder creation and valid paid propagule materialization.

Do not modify source or merge. Blocking correctness findings => FIX_REQUIRED. Zero blocking findings is required for PASS.
