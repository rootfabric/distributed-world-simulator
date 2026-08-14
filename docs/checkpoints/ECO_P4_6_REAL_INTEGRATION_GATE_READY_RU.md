# ECO P4.6 — Interest + Client Read Model — REAL INTEGRATION GATE READY

Статус: `CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_REAL_COMMITTED_INTEGRATION_GATE_READY`.

Parent P4.5: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419` — ACCEPTED.

## Что добавлено после P4.5 acceptance

P4.6 unit contract уже проверял deterministic summary/interest/cache semantics на synthetic summaries. Для lifecycle acceptance этого недостаточно, поэтому добавлен отдельный real integration gate:

`tests/ecology/production/support/eco_p4_fixture_v1.gd`

воспроизводит accepted P3→P4.5 fixture без изменения frozen kernels/tests, а

`tests/ecology/production/eco_p4_6_real_integration_acceptance.gd`

проверяет настоящий путь:

```text
P3 ecology
→ P4.1 RegionState
→ P4.2 Clock
→ P4.3 Catch-up
→ P4.4 production snapshot
→ P4.5 ownership/handoff
→ P4.6 summary/interest/client cache
```

Дополнительно проверяются future-generation update, persistence serialize/deserialize restart, exact P4.5 ownership reconstruction, stale-client rejection, detached read-model mutation и отсутствие global RNG side effects.

## Gate policy

`RUN_ECO_P4_6_TESTS.ps1` теперь:

1. pin'ит accepted P4.5 validation/kernel/test/runner;
2. parser-check'ит unit и real integration tests;
3. запускает direct P4.5 parent regression;
4. запускает P4.6 unit A/B с frozen unit hashes;
5. запускает real integration A/B и требует byte-identical logs;
6. печатает real integration identities для отдельного freeze в lifecycle acceptance.

На этой стадии real integration hashes намеренно ещё не объявлены canonical: они должны быть получены из exact committed run.

P4.7 canonical gate остаётся закрыт до P4.6 acceptance, но его pre-acceptance harness можно разрабатывать параллельно.
