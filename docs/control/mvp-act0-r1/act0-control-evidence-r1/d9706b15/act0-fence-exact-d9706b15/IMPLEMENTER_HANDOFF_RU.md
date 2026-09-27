# Implementer FIX_REQUIRED handoff

Frozen/pushed d9706b157e84c653a753cc54243ce6651d53319c / 4925ea293c15d88153278437976a3b69f8985ccf.
Windows18/18 tests,23 negativeGitcases,115.998s,exit0. Новая Trace2 проверка наблюдает реальный fixturecommit и отсутствие maintenance/gcchildren. Исходные rawLinux a7/35103186274 ошибки сохранены; их PASS не заявляется.

FIX_REQUIRED root hypothesis: быстрый negative commit запускает Gitmaintenance--detach и потенциально оставляет writer, конкурирующий со строгимTemporaryDirectory cleanup. Windows диагностический clone rawTrace2 подтвердил запуск `git maintenance run --auto --quiet --detach`, но не сам Linux race. Поэтому validation новой гипотезы требует отдельногоLinux rerun, который запускает parent.

Fix исключительно fixture-local: maintenance.auto=false, gc.auto=0, gc.autoDetach=false записываются вclone config до первогоcheckout. Cleanup/assertions не ослаблены; skip/retry/ignore нет. Runtime/scenes/project относительно3b неизменны, cleanstatus. Бounded critique: NO_MATERIAL_REFACTOR_REQUIRED; clone lifetime должен принадлежать тесту без фонового обслуживания. Fresh Reviewer/Verifier обязательны; selfreview/merge не выполнялись.
