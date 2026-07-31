# Checkpoint v16.10.4 — M5 Graphical Multiplayer Acceptance

## Решение

Кандидат M5 доказывает полноценную UI-driven multiplayer vertical одного dedicated server и двух обычных графических клиентов.

## Evidence

- M5 contracts: `tests/runtime/test_m5_graphical_acceptance_contracts.gd`;
- preparation boundary: `tests/runtime/test_m5_graphical_acceptance_preparation.gd`;
- graphical process acceptance: `tests/runtime/test_m5_graphical_multiplayer_acceptance.gd`;
- focused runner: `RUN_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_TESTS.ps1/.sh`;
- machine-readable manifest: `config/network/graphical-multiplayer-acceptance.v1.json`.

## Доказанный сценарий

Два graphical clients используют реальные InputMap и inventory widgets, проходят deterministic contention, полный hotbar/container/mount/drop workflow, disconnect/reconnect и сходятся с dedicated server к одинаковым player и Item Graph checksums. Transient cursor не переживает reconnect, а canonical inventory сохраняется.


## Результаты локальной проверки кандидата

- M5 contracts: `76/76 PASS`;
- M5 graphical process: `89 assertions` в Windows и `90 assertions` в Linux, где дополнительное утверждение проверяет запуск Xvfb;
- focused M5: `15/15`, `1109 assertions` в Windows и `1110 assertions` в Linux;
- network/runtime: `57/57 suites`, `4320 assertions`;
- world regression: `102/102`;
- main scene: `6/6`.

## Следующий этап

`M6 — Dedicated persistence and recovery` должен аварийно остановить server process, восстановить players и canonical Item Graph из durable state и доказать отсутствие дубликатов после reconnect.
