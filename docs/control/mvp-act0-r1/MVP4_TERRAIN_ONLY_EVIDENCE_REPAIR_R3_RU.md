# MVP4 — terrain-only evidence repair R3

Исходный candidate: `55fcffe437faa6d4919c1baa120b6e4ca5fc8d11` (tree `7cf1351fbb3a9e563a2ac9451d2a090d3d3312b0`), CI run `34766046994` SUCCESS, artifact `10320342701`, ZIP SHA256 `89234e6e29fc7ec36e9897deaaf363f8715b3299b1b74e5cff842eedf9abc118`, Project Control `34766048958` SUCCESS. Эти результаты — историческое evidence для `55fcffe`, не для исправленного HEAD.

## Blocking finding (review thread 4001519528)

`tests/fixtures/v0_mvp/mvp4_viewport_pixels.py` считал «терраином» всё ниже строки 160. Реальный наследованный HUD (Label на y=18, шрифт 19, после MVP4-строки 8+ строк) занимает rect `20,18 размером 467x237`, т.е. до строки ~255: строки статуса MVP4 лежат ниже 160. Между before/after меняются фаза HUD и MW6 cursor, поэтому критерий `terrain_changed_pixels >= 32` мог выполняться только за счёт HUD при неизменном терраине — риск false positive.

## Ремонт (evidence correctness, не архитектура)

1. **Terrain-only по построению.** `v0_mvp4_graphical_client.gd::_capture4` перед КАЖДЫМ каноническим capture (before и after) выводит полный UI-регион из живого UI-дерева (все CanvasLayer/CanvasItem под корнем клиента), скрывает весь UI, ждёт два завершённых render-кадра, делает capture через тот же реальный viewport, затем восстанавливает видимость ровно скрытых элементов. В evidence каждого capture записаны `ui.nodes` (класс/имя/rect/видимость), `ui.region` (union rect) и `ui.hidden`.
2. **Сравнение без угаданных строк.** `mvp4_viewport_pixels.py::terrain_change` считает изменения по всему изображению, исключая только UI-регион, выведенный из UI-дерева (никаких констант строк). Порог остался `>= 32` пикселей на каждого клиента.
3. **Обязательная фальсификация.** `test_v0_mvp_4_visible_graphical_shared_dig.py` синтезирует из РЕАЛЬНОГО before-capture пару изображений, идентичных по терраину и различающихся только внутри выведенного UI-региона (включая строки ниже 160). Контроль доказывает: пара «HUD changes + identical terrain» отвергается новым гейтом (0 изменений вне региона => FAIL), при этом отвергнутый legacy row-160 критерий demonstrably принимал ту же пару (воспроизведение механики finding'а). Positive control сохранён для обоих клиентов: реальная мутация терраина => PASS (`>= 32`).
4. **Процессные проверки.** `test_v0_mvp_4_graphical_shared_dig.py` добавляет проверку `a:terrain_only_capture`/`b:terrain_only_capture` (обязательны `ui.hidden` и выведенный регион для обоих capture) и девятый negative control `hud_visible_capture` (подделка `ui.hidden=false` должна рушить процессный gate).

Ничего из защищённого не изменилось: один canonical Matter owner (`authority/a`), P7/MW8 authorization, MW6 sequence/checksum/session validation, foreign-peer/gap/corrupted/duplicate rejection, read-only реплики клиентов, MVP3 frozen evidence, foundations (P7/SM1/Matter/network/m4/project.godot) не тронуты.

## Exact execution на исправленном HEAD

- Implementation subject: `e3e22af63bc7e672cbe68dd6851143ea8e659b67` / tree `687f30365938f2e83e895750d320f4745dc47523` (локальный runner: canonical Ubuntu, double Godot SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`, `LIBGL_ALWAYS_SOFTWARE=1`, display `:0`).
- Локальный прогон `docs/control/mvp-act0-r1/validate_mvp4_exact.py`: `passed=true`, `exact_subject=true`, `tracked_clean_after=true`. Все строки прошли: import (6.0s), mvp4-focused (45 assertions), mvp4-replica-rejection (57 assertions), mvp3-attestation + baseline `f1d453fb` classification, mvp3-live-owner, mvp3-fixed-input, sm1-carry, mvp4-five-process-visible (33.6s), mvp3-native-process, mvp3-graphical-process. Сырые артефакты и digests: `artifacts/mvp4-exact/` (summary.json `269bdb57…a742fac`, commands.json `34147b3b…00ded9b`, baseline-cleanup-classification.json `bccfafc2…103d60b`).
- Process manifest (run_id `7d08c94d2caae33a721c4b343634c967`): `passed=true`, все проверки true, 9 negative controls включая новый `hud_visible_capture`; digests: manifest `470206e7…a522004`, visible-acceptance `cbc12f98…555770`.
- Positive control (реальная мутация терраина => PASS): клиент A `203` changed pixels, клиент B `203` (минимум 32), исключённый UI-регион `[20,18,420,237]` (union реальных before/after регионов Label). Независимые A/B рендеры побайтово идентичны (before: `4d09424e…71bd31` у обоих клиентов; after: `bf775b0f…40dcd7` у обоих) — детерминированная конвергенция двух независимо перестроенных проекций.
- Pixel-level верификация построения: во всех четырёх канонических capture в HUD-области `0` near-white текстовых пикселей; в финальном скриншоте `client-a.png` (UI восстановлен) — `251`: HUD реально был скрыт в обоих capture и восстановлен после.
- HUD-only negative control (identical terrain + HUD changes => FAIL): клиент A — legacy row-160 критерий принял бы пару (`11024` changed px ниже строки 160), новый гейт отверг (`0` px вне UI-региона); клиент B — `11149`/`0`. `rejected_all=true`. Синтезированные пары сохранены как реальные PNG (`client-*-hud-only-*.png`).
- MVP3 регрессии: все PASS; R13 cleanup-диагностика (17 leaked / 6 resources in use) побайтово идентична immutable baseline `f1d453fb`, тест не изменён, диагностика сохранена в raw logs (историческая классификация, не подавление).
- Полный Harness (python equivalent `CONTROL_DEVELOPMENT`/CI discovery): `349 tests OK (skipped=2)` на исправленном HEAD. PC0 standard: exit 0, overall YELLOW (без RED для V0; standing `RUNTIME_TEST_PENDING`, dependency drift пуст). Directional PC0: exit 0, YELLOW, критических WATCH_HIT нет, V0 не участвует. Drive до ledger-инцидента возвращал `CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED`, INTEGRATOR, без human gate.
- CI exact-head прогон на pushed HEAD: workflow `MVP4 Shared Canonical Dig Exact Validation` срабатывает по тегу `[mvp4-evidence]`; итоговый run id фиксируется в completion report / PR #597.

MVP4 по-прежнему NOT VERIFIED. Реализатор не выносит independent verdict: требуется новый fresh exact-head Reviewer, затем независимый Verifier. Parent `V0-MVP-R1-WO-001` остаётся `IN_PROGRESS`; merge в main не выполнялся.

## Incident: событие 0013 и контроль целостности ledger

Первичная публикация event 0013 в историческом commit `2b6b8d7e` ошибочно ссылалась в `evidence_paths` на git-ignored `artifacts/mvp4-exact/summary.json`; provenance-fence это выявил. Исторический corrective commit `65f2d085` исправил ссылку, но тем самым изменил уже опубликованный event-файл и нарушил machine-invariant append-only ledger (`EVENT_IMMUTABILITY_NOT_PROVEN`). После инцидента были добавлены ещё control/evidence commits `75c0a6e3` и `51585dd2`, поэтому безопасный repair обязан перестроить весь непринятый хвост после `e3e22af6`, а не буквально только первые два commits.

2026-09-14 пользователь явно разрешил surgical force-push rewrite ветки `feature/v0-mvp-playable-seamless-planet-r1` от `e3e22af6` с сохранением финального содержимого `51585dd2`, единичным add event 0013 и RESOLVED HA. Clean history repair строит один новый commit на parent `e3e22af6`, в котором event 0013 появляется впервые уже с корректными committed `evidence_paths`; финальные runtime/evidence bytes сохранены, HA `HA-V0-MVP4-EVENT-0013-HISTORY-REPAIR-R1` переведён в `RESOLVED`.

После force-update обязательны новый exact MVP4 CI, полный Harness, Project Control, PC0/directional PC0 и `CONTROL_DEVELOPMENT -Drive`. До этих пост-rewrite проверок MVP4 остаётся NOT VERIFIED; никакой predicate closure или merge не разрешены.
