# ECO EVO3 E3.FINAL — Evidence Map

Статус: `IMPLEMENTED / AWAITING_INDEPENDENT_REVIEW`. Единица ревью: настоящий пакет. Принятие — за Director (PC0-аудит при принятии).

## Exact heads

- База ветки (принятое состояние): `5fc9895` (E3.8 ACCEPTED через PR #188).
- Reviewed/evidence/tested HEAD реализации: см. поле `exact_head` в чекпоинте `docs/checkpoints/2026-08-22_ECO_EVO3_E3_FINAL_IMPLEMENTED_RU.md` (коммит с настоящей картой).

## Замороженный precommit (до первой компиляции)

| Артефакт | sha256 | git blob |
|---|---|---|
| Контракт вызова `config/ecology/eco-evo3-e3-final-unseen-world-challenge-contract.v1.json` | — (self-hash `ee66f06dd186ba914508c1f7d157d01288a8d51d7c04f6be7147d558849ece99`) | — |
| Планеты arid-basin-02 / oceanic-ridge-03 / polar-plateau-04 / volcanic-isles-05 | пины в контракте (`8273ec2b…`, `7763aef9…`, `9798d986…`, `a9d5b3fe…`) | пины в контракте |
| Каталоги extended_r1 (12 видов) / mono_r1 (1 вид) | `5933e17e…` / `6e2a761b…`; catalog_hash `bd06d951…` / `f123e039…` | пины в контракте |
| Sealed commitments (12 дайджестов) | файл `117ab0094cb9eb6cf404dfc7ef3d9ab331d6e15a3fc0d8312b65d710e18ae70a` | пин в контракте |

Plaintext предсказаний хранится вне репозитория; вскрытие после заморозки байт программы.

## Программа вызова (заморожена коммитом)

- `validation/ecology/eco-evo3-e3-final-unseen-world-program.generated.json`: bytes 344198, sha256 `8235b4a6cf322101c5c9c578b7a94d182667c57b27d7c78c65686474c5cc2c1f`, git blob `24c677884c47b6662917372731d8b25b374da0f9`, provenance_hash `a59ebafccbb37766bb00da838fa47cf69909cc4695a33350fd19c894b6d2fa20`, planetary_ecology_program_hash `6d28b032c193cb046d48a07a21fd31996331ef4cbb19add25e5eb1fd2b228767`.
- 12 комбинаций (4 unseen-планеты × baseline/extended_r1/mono_r1): colonized_all=4, mixed=2, none=6.

## Гейты и прогоны

| Гейт | Результат |
|---|---|
| Семантические+authority тесты (`RUN_ECO_EVO3_E3_FINAL_TESTS.py`) | 20/20 PASS |
| Closure-предикаты | 19/19 PASS |
| Fresh-process determinism ×2 | byte-identical, sha совпадает с committed |
| Committed-bytes identity | identical (см. константы раннера) |
| Sealed commitments bound pre-build | 12/12 digest match |
| Пороги нетронуты (60000/150000 во всех 12 программах) | PASS |
| Переиспользование: 6 принятых модулей unmodified (дайджесты в provenance) | PASS |
| Execution envelope | 0.297s ≤ 60s; артефакт 344198 B ≤ 10 MiB |
| Запретные продвижения (14 ключей) | все False |
| Sealed reveal (после freeze) | 12/12 печатей; 6 confirmed / 6 falsified → falsification evidence |
| Регрессия принятых этапов A4 (`RUN_ECO_EVO3_REGRESSION_CLOSURE.py`, jsonschema 4.26.0) | 8/8 PASS |
| Lint привязок evidence (`scripts/control/lint_eco_evo3_evidence_sync.py`) | PASS (findings=0) |

## Вне рамок данного пакета

- Принятие E3.FINAL (Director) и merge в main — human gate.
- E3.6-R остаётся `CONDITIONAL_BLOCKED_WAIT_OWNER_TEMPORAL_EVIDENCE` (disposition подтверждена в итоговом чекпоинте).
- XFER1 остаётся `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`; pre-design `docs/plans/ECO_XFER1_READINESS_PREDESIGN_RU.md` готов как non-authoritative вход.
