# MVP6 V0 → NX — clearance после merge journal, R2

## Поручение и граница

Пользователь поручил обновить отдельный clearance-кандидат под уже слитый journal, приложить новые доказательства и провести свежую независимую проверку. Этот control-only кандидат продолжает V0-MVP-R1-WO-001 / E2026-09-09-V0-MVP-R1; новый runtime worker не создаётся. Merge данного кандидата не разрешён этим поручением.

База: main `a6d5eb6b287130a638ba6cf397c34e29169948c1`, TREE `4925ea293c15d88153278437976a3b69f8985ccf`. Это фактический merge PR #646 с reviewed head `d9706b157e84c653a753cc54243ce6651d53319c`, не альтернативный PR #643.

Новая ветка: `control/v0-mvp6-nx-directional-clearance-postmerge-r2`. Исторический PR #644 / `bcfaae78bd852add71a2a2592998b46cc47878b5` сохраняется как предшественник; его obsolete prerequisite `6b147d03` не переносится. История не переписывается.

Разрешённый bounded diff: `config/control/directional-watch-clearances.v1.json`, `scripts/control/directional_watch_clearance.py`, минимальная адаптация исторического теста `tests/harness/test_project_control_directional_clearance.py`, новый `tests/harness/test_mvp6_postmerge_directional_clearance.py`, этот документ, `docs/control/mvp-act0-r1/MVP6_NX_CLEARANCE_POSTMERGE_R2_EVIDENCE.json`, `docs/control/mvp-act0-r1/validate_mvp6_clearance_postmerge_r2.py`. На отдельном validation carrier разрешён только именованный `.github/workflows/mvp6-clearance-postmerge-r2.yml`; он выполняет read-only tests/evidence и не входит в product/control merge diff. Runtime, registry ownership, historical clearance rows, ACT0/P7 acceptances и producer/NX ветки не изменяются.

## Доказательства, уже полученные до этого кандидата

Immutable source: feature commit `35a367e10ff723c46e7b2e6dd39b1f1e4d6f64de`, supporting-evidence `MVP6-POSTMERGE-A6D5EB6B-NX-PC0-R1.v1.json`.

Run `35162668295`, attempt 1, job `105016731540`; producer tested HEAD `2497ecb6b89b6c1e20afbff9c823c7564b78f956`, TREE `59186fa72db6c280e0d26470674884f280fe474c`. Artifact `10474045529`, ZIP SHA-256 `c1bca166ae69ef754065192a5a50e86d51434ccdaa92efba14af691d29c644c1`, manifest SHA-256 `f09da9fcf04d9b0dc8e03f18867346f60c773cba41766d101d3d5318950f1a7f`. При продолжении ZIP и все 28 manifest members перепроверены: несовпадений нет.

Действительно merged canonical journal, без repair override: baseline 1077/1077 PASS; baseline + V0 M4 1077/1077 PASS; failures/fatal markers 0. Это compatibility evidence с явно раскрытой одинаковой parser-only нормализацией трёх NX tests и одного dynamic runtime declaration в disposable compositions. Не unmodified NX source acceptance, не независимый verdict текущего control-кандидата.

Независимые producer review/verification IDs из предыдущего exact runtime evidence сохраняются как таковые: `MVP6-JOURNAL-73B88181-REVIEW-R1` и `MVP6-JOURNAL-FEATURE-VERIFIER-R1` на `73b8818184c93986e3313f35f9f4548c608e47e6`. Новые контрольные роли должны отдельно проверить этот кандидат и достаточность postmerge evidence.

## Причина и выбранное исправление

Raw standard PC0 YELLOW, directional RED: critical M4 hit и ordinary journal hit между V0 и NX. Старый кандидат требует несделанный merge PR #643 и ссылается на repair composition. Новый clearance `V0-MVP6-NX-POSTMERGE-CRITICAL-WATCH-CLEARANCE-005` привязывается к фактическому merge PR #646 и exact producer/consumer fingerprints.

Дополнительные fail-closed предпосылки resolver: полный hex commit `required_main_ancestor`, его наличие в origin/main и непустой exact `required_main_file_blobs`. Blob проверяется одновременно в prerequisite commit и текущем origin/main: последующий revert journal не может оставить clearance действующим только потому, что merge остался в истории. Старые записи без этих optional полей работают без изменения прежних правил.

Сохраняются все прежние проверки: exact critical/watched sets; reviewed producer ancestry; consumer HEAD/passport; reviewed и live producer blobs; accepted decision и independent producer evidence IDs. `status=ACCEPTED` в unmerged registry является предлагаемым состоянием после merge, а не текущим canonical acceptance. Production loader читает registry только из origin/main; он не изменяется.

## Validation и независимые роли

Сохранить все исторические тесты; адаптировать только проверку отсутствия исторического P4 clearance для текущей V0 ветки, не запрет нового exact clearance. Добавить actual-Git positive checks и отрицательные: prerequisite absent/malformed, main journal reverted/missing/misbinding, wrong producer ancestry, changed reviewed/current blobs, consumer HEAD/passport/path drift, critical/watched-set drift, missing evidence/decision, candidate registry not canonical.

Exact CI на отдельном carrier проверяет frozen candidate HEAD/TREE, scope/runtime equality с actual main, digest предыдущего artifact, focused tests, actual raw canonical auditors, затем кандидатную проекцию в отдельном disposable Git repository. Только в fixture origin/main указывает на candidate; реальный remote/main не меняется. В evidence раздельно сохраняются RAW_CANONICAL и SIMULATED_CANDIDATE_MAIN, а не выдаётся synthetic NON_RED за canonical result. Полный Harness запускается в кандидатной проекции с сохранением ошибок, без skips/ослабления assertions.

После machine evidence — fresh independent review exact candidate. Implementer не создаёт собственный independent PASS. Все замечания исправляются новым subject с повторной валидацией. Финальный approval/merge этого control-only PR — отдельный HUMAN gate. После разрешённого merge нужны реальные canonical PC0 и epoch audit; MVP6 Construction/seam runtime и whole-MVP acceptance этим не закрываются.
