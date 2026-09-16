# ACT0 journal fence — control continuation

Parent V0-MVP-R1-WO-001; exact base3b82145ae946bb51aebf67f048a28420368b40be.
Единственный implementation target: tests/harness/test_v0_mvp_act0.py.
Canonical owner: main-owned Harness; новые runtime права не выдаются.

Root cause: test_all_p7_execution_and_acceptance_blobs_are_unchanged сравнивает
исторический ACT0 BASE3d767 с любым текущим HEAD и требует пустой network diff.
Разрешённые четыре строки journal ed23→abdf ломают это контрольное предположение.
Остальные full Harness Windows failures отдельно классифицируются parent.

Entry point: unittest discovery / MVPAct0Tests; callers: canonical control CI.
Соседние invariants: P7 execution/acceptance, runtime/simulation/project, exact A7
scene change, activation/epoch/mutation lease/risk. Они сохраняются.

Design: неизменяемый historical main6982 проверяется относительно ACT0 BASE;
текущий protected diff допускает zero либо ровно M journal olded23→newabdf.
Содержимое resolved HA и предложенного patch переносится из exact68433ec7 с
SHA256 и source locator. Проверка читает committed bytes, сопоставляет fixed
digests и точные identity/status/scope поля, не moving branch или remote main.

Не допускаются skip/xfail, удаление journal из diff, BASE=HEAD, wildcard allowlist,
новая runtime mutation, изменение accepted evidence или автоматический merge.
Негативы: altered journal byte; лишний protected path; wrong before blob;
rename/delete; missing/OPEN/foreign HA; P7 acceptance mutation; extra scene.

До code edits фиксируется этот exact CONTROL WO. Основание — пользовательский
control mandate §8 и Director replan, а не blanket расширение runtime HA.
После реализации frozen exact focused tests, fresh Reviewer/Verifier, HUMAN merge.

## FIX_REQUIRED: Linux fixture teardown

Run35103186274 на a7c711c4: 329 tests, один прежний directional RED failure и
10 ошибок TemporaryDirectory cleanup `Directory not empty: repo`. Все десять
возникают после negative commits с быстрым отказом source fence; assertions не
ослабляются. Windows focused17 проходил, поэтому он не заменяет Linux evidence.

Отдельный GIT_TRACE2_EVENT diagnostic на cloned a7 воспроизводит child command
`git maintenance run --auto --quiet --detach` при обычном fixture commit.
Windows diagnostic не воспроизводит сам Linux teardown race; связь detached
maintenance с Linux ошибками — проверяемая гипотеза, не доказательство harmless.
Raw trace сохранён parent в artifacts/mvp6-journal-73b88181/act0-maintenance-diagnostic.

Минимальное исправление test-only: установить maintenance.auto=false, gc.auto=0,
gc.autoDetach=false в конфигурацию каждой disposable clone до её первого checkout.
Добавить real-commit Trace2 проверку отсутствия automatic maintenance/gc children.
TemporaryDirectory cleanup остаётся строгим; ignore_errors, retries и skip нет.
Новый exact Windows/fresh Linux прогон обязателен; a7 Linux не переписывается в PASS.
