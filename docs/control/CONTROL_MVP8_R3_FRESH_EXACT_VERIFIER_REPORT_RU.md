# CONTROL MVP8 R3 — fresh Windows/Linux exact verifier evidence

**Вердикт машинной верификации:** `FRESH_WINDOWS_EXACT_PASS / FRESH_LINUX_EXACT_PASS / EVIDENCE_INTEGRITY_11_11_PASS / PC0_NON_RED_WITH_WARNINGS / MERGE_READY=false`.

**Замороженный проверенный код PR #855:**
`PRODUCT_HEAD = 7510aa4ff81e6d3a13bbfa0872b6f60bfb547621`
`PRODUCT_TREE = 5003355e504c620c7f4bb0413bda6d4f36b9fd8d`
`PARENT_PR845_HEAD = 3a8f858f85c5ff018676557650f34179d6d5f86b`.
Отдельная verifier-only ветка `verify/control-mvp8-r3-fresh-7510aa4-r1` содержит только read-only workflow поверх проверенного продукта. Изменения verifier-ветки не являются частью R3-кандидата.

## Исходные RED и проверенный GREEN

- Исходный независимый Reviewer RED на PR #845: [run #40065997560](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40065997560). При `git update-index --assume-unchanged` изменённые байты события #0050 и отдельного Reviewer receipt принимались как будто они совпадали с `HEAD:` Git blob.
- Новый R3 код хеширует точно захваченные байты двух файлов через Git `hash-object --stdin`, парсит именно их, сверяет с удостоверенными `HEAD:path` blob и сравнивает detached event DTO по типо-строгой сериализации JSON, исключая `False==0` и `50.0==50`.
- Свежие тесты из исходного R3 exact HEAD: **5/5** позитив/негатив, включая два старых RED, forged in-memory summary и int/bool+float/int confusion; R2 **4/4**, R1 **6/6**, Evidence Map **5/5**. Все пройдены как на Linux, так и Windows.

## Два раздельных GitHub CI-прогона

### Implementer exact / raw proof

[Run #40091670412](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091670412): `frozen-scope`, `linux-exact`, `windows-exact` — **3/3 SUCCESS**. Linux full Harness **402/402 PASS**. Windows native `CONTROL_DEVELOPMENT.ps1 -Status` и `-CheckConsistency -Candidate` — exit0/ok=true. Git diff frozen base → product: **только четыре пути** (один Harness source, один тестовый файл, один workflow, один Repair Map). Исторические Event/Review/Witness Git blob неизменны.

[Implementer Linux evidence artifact #12559730444](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091670412/artifacts/12559730444): ZIP SHA256 `00f727451c2482e5076f554b8c0a7ae1598a6c59eb332b540163b74352a9e6a5`; побайтовое совпадение с GitHub digest. Внутри 11/11 SHA256SUMS MATCH, включая exact IDENTITY, full 402 log, R3/R2/R1/evidence-map logs, status, consistency, PC0.

### Fresh verifier exact on separate named worktrees

[Run #40091993517](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091993517): `source-provenance`, `linux-fresh`, `windows-fresh` — **3/3 SUCCESS**. `source-provenance` проверил, что verifier-ветка имеет только собственный CI-workflow и является прямым потомком точного R3 product HEAD/TREE. На Windows и Linux созданы новые именованные чистые worktree с **точным** product HEAD/TREE.

- Fresh Linux: targeted **5/5 + 4/4 + 6/6 + 5/5**, full Harness **402/402 PASS** (228.005 s), `status` и `check-consistency --candidate`: exit0/ok=true.
- Fresh Windows: targeted **5/5 + 4/4 + 6/6 + 5/5**, native `CONTROL_DEVELOPMENT.ps1 -Status` и `-CheckConsistency -Candidate`: exit0/ok=true.
- Fresh standard PC0 `overall_health=YELLOW` и directional PC0 `overall_health=YELLOW` (оба non-RED, но **не GREEN**). CheckConsistency `ok=true`, 3 warning `BRANCH_ADVANCED_SINCE_SNAPSHOT` для `ECO/integration`, `ECO/visual_repair`, `FABRIC/bake`. Отдельные предупреждения остаются видимыми; не маскировать их кодом выхода.

[Fresh verifier Linux artifact #12559825644](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091993517/artifacts/12559825644): SHA256 ZIP `cf452a64d45b7e1fb9732088dc65712729aefb2610a1caf34808b69ad3c6f08a` — **exact match** с GitHub. Внутренний SHA256SUMS **11/11 MATCH**. `IDENTITY` содержит ровно `7510aa4.../5003355e...`; JSON status = `ok=true`, full suite `Ran 402 tests ... OK`.

## Scope/ownership/human gates

- Этот отчёт подтверждает **достоверность machine evidence** и исправление двух исходных RED в R3; не является подписью стороннего independently authenticated Reviewer или Verifier. Проверочный workflow исполнен отдельными GitHub-hosted машинами, но организован в одной пользовательской сессии.
- PR #855 и родительские #845/#839/#834 остаются **Draft и unmerged**. `main` не переписывалась; FABRIC #784/#800/#818 не изменялись.
- Для `MERGE_READY=true` остаются **формальное независимое fresh Reviewer/Verifier signoff**, интеграционный аудит стековой цепочки, актуальные PC0/directional после интеграции и явное human merge approval.
- Возможный будущий соседний аудит: старый общий `_validate_event_git_provenance` для **других**, не охваченных R3 witness, событий пока использует `git status`. За пределами узкой Issue #848; не объявлять весь глобальный журнал защищённым одним R3 фиксом.

**Текущий статус:** `R3_IMPLEMENTED_AND_MACHINE_VERIFIED / FORMAL_INDEPENDENT_ROLES_PENDING / MERGE_READY=false`.