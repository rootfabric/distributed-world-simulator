# SEAM-E2E R1 — исполнение приёмки на Windows и Linux

**Статус:** `SPEC_CANDIDATE / EXECUTION_NOT_STARTED / NO_RELEASE_CLAIM`.  
Головной контракт: `docs/testing/SEAM_E2E_R1_MULTISERVER_WORLD_ACCEPTANCE_RU.md`.  
Машинная матрица: `config/testing/seam-e2e-r1-acceptance.v1.json`.

## Миссия 0 — независимая инвентаризация продуктовых возможностей

На свежем HEAD проверить, существуют ли реальные product API для:
- трёх и более разных authority-процессов (не две service-authority внутри M3);
- Ownership Directory, CAS/epoch/fence, стабильного client↔Gateway transport и read-only AOI/projection;
- production Earth+Quaternius, Item Graph, M6, Construction, mining/terrain, cross-owner physics;
- запуска хотя бы через две независимые Windows/Linux host boundary с ненулевым backend LAN transport.

Любую недостающую функцию пометить `BLOCKED_NOT_IMPLEMENTED`, назвать точный owner и минимальную недостающую API/контракт. Запрещён test-only proxy/writer/ItemGraph, который превращает fixture в зелёный product gate. Существующие `RUN_V0_SM1_GRAPHICAL.sh`, `RUN_V0_SM1_CONCURRENT_CROSSINGS.sh`, `RUN_V0_SM1_RECONNECT_AFTER_HANDOFF.sh`, `RUN_V0_PLAYABLE_SEAMLESS_CLIENTS.ps1` полезны только как prereq/regression.

## Миссия E0 — 3 authority + 2 hosts + 2 real clients

В отдельном **test harness PR** написать рабочий launcher (`tools/seam_e2e/run_seam_e2e.py` либо эквивалент) с отдельным конфигом реальных host/PID/port/process owners. Минимум 3 authority A/B/C + 1 Gateway + 2 независимых графических Earth-клиента. Подтвердить реальные backend network connections G↔B не через loopback; одинаковый `world_id`, frozen HEAD/TREE/build.

Запуск `--scenario topology` должен быть FAIL/INCONCLUSIVE на одном хосте, с одним клиентом, с двумя authority, с fallback-avatar, без Quaternius, без независимого Directory и при наличии только фальшивых ролей внутри одного процесса.

## Миссия E1–E3 — пересечения и реальное взаимодействие игроков

Исполнить на *одном живом мире*:

1. A→B→C→B→A с 10+ переходами по каждому направлению, без логин-экрана, respawn или client socket к симуляции.
2. Два игрока под **разными owners** одновременно видят движение/анимации друг друга, встречаются у границы и продолжают взаимодействие при передаче authority.
3. A передаёт/роняет конкретный canonical ItemId, B под своим owner его подбирает, equip/use/drop; оба клиента и два server authoritative readers сходятся в одном outcome.
4. A и B совместно достраивают/разбирают **одну** конструкцию через шов с единой коллизией; подлинные ресурсы списываются ровно один раз.
5. Mining/terrain меняется на граничной клетке, у обеих сторон та же версия и тот же остаток руды/материала.
6. Cross-owner collision/physical interaction имеет одного resolver; если owner/API отсутствует — гейт RED до отдельной продуктовой доработки.

Каждый сценарий должен иметь независимые client/authority/Directory/Gateway traces и canonical state digests. Просто два объекта на экране или один сценарий SM1 плюс второй M5 не принимаются.

## Миссия E4–E5 — отказоустойчивость, производительность и приёмка

Injection до/после Directory CAS, перед/после target activate, старый owner после restart, stale route/response, duplicate OperationId, gateway crash/rehome, двухсторонние network partition/loss/reorder/jitter. Проверить ровно одного writer, стабильные identities, FIFO/ACK escrow и durable-before-ACK, отсутствие потерь/дублей и idempotent replay.

Только после функциональных и точных нативных PASS: три 120-секундных GUI прогона с полными трассами; frame p99≤25ms, p99.9≤50ms, client max gap≤100ms, server≥59Hz и perceptual targets из контракта. После этого 30 минут soak с реальными повторяющимися пересечениями и cross-owner interaction — не idle test.

Обязательная структура evidence:

```text
identity/HEAD-TREE-GODOT-SHA256.json
topology/hosts-pids-links.json
gateway/trace.jsonl
directory/cas-ownership-fencing.jsonl
authorities/a/trace.jsonl
authorities/b/trace.jsonl
authorities/c/trace.jsonl
clients/a/trace.jsonl
clients/b/trace.jsonl
clients/a/screenshots/  clients/b/screenshots/
state/itemgraph-construction-resource-digests.json
faults/injection-and-recovery.json
performance/frame-seam-metrics.json
SHA256SUMS.txt
review/independent-reviewer.json
verify/independent-verifier.json
control/project-control.json
```

Отсутствие любой обязательной информации => `INCONCLUSIVE`, а не PASS. Project Control и release Human Gate обязательны. На старом R31 или SM1 lab нельзя получить `SEAM_E2E_FULL_ACCEPTANCE_PASS`.

## Входные команды для первых агентов

```powershell
git fetch origin --prune
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
python tools/seam_e2e/check_contract.py
python -m unittest discover -s tests/tools -p "test_seam_e2e_r1_contract.py" -v
# NOTE: SPEC_CONTRACT_PASS != runtime E2E acceptance.
```

Для Linux:
```bash
GODOT_BIN=/verified/godot-double ./RUN_V0_SM1_GRAPHICAL.sh
GODOT_BIN=/verified/godot-double ./RUN_V0_SM1_CONCURRENT_CROSSINGS.sh
GODOT_BIN=/verified/godot-double ./RUN_V0_SM1_RECONNECT_AFTER_HANDOFF.sh
```

Предварительные SM1 команды служат только диагностике существующей базы. Следующие E0–E5 PR должны исполнять **новую единую продуктовую topology**. Никакой ротации registry/lease, force-push, product merge и soak без соответствующего human authorization.
