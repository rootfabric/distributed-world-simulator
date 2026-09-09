# ACT0 R4 — срок действия epoch audit и граница validation job

Свежий Reviewer отклонил `df1af401a11ef0c65ef442433f888f3a21963ac3` по двум P1: comments `3967524197`, `3967524212` в PR #594. Его машинные 296 PASS сохранены как результаты покрытого набора, но не как приёмка найденных дефектов.

1. Принятый exact epoch audit теперь остаётся доступным после законных IN_PROGRESS/IMPLEMENTED/VERIFYING/VERIFIED переходов. Валидность по-прежнему проверяется через фактический main SHA и неизменные committed bytes; новый main не может использовать старую evidence. Для MVP оба формата событий аудита обрабатываются в последовательности ledger, поэтому ранний recovery не перекрывает более поздний AUDIT_COMPLETED, в том числе RED. Остальной state_builder проверяется побайтно за исключением единственной функции `_select_epoch_audit`.

2. ACT0-only workflow на future runtime-ветке теперь выполняется только при `workflow_dispatch` или точном маркере `[act0-audit]` в сообщении commit. Обычные implementation pushes не запускают activation validator. Явный ACT0 audit сохраняет строгий контроль: только control-diff, пустые product predicates и отсутствие MVP acceptance. Пропущенный job не является PASS или evidence реализации MVP.

На control-ветке финальный gate выполняется автоматически. Новый тест прогоняет настоящий CLI по всей последовательности этапов; отдельные отрицательные проверки доказывают отказ после смены main и при позднем RED audit. Два predecessor negative controls используют старые неизменные implementation bytes и добавленный незакоммиченный test-only probe в отдельных worktree; исходные tracked files остаются clean. Старый P1 воспроизводится на `df1af401`, новое поведение проверяется на кандидате.

После ACT0 merge настоящий post-merge audit следует публиковать на `feature/v0-mvp-playable-seamless-planet-r1` с сообщением commit, содержащим `[act0-audit]`. Это разрешает запуск только read-only проверки ACT0, не запускает игрового агента и не принимает MVP. Все исходные и будущие runtime/acceptance gates остаются обязательными.
