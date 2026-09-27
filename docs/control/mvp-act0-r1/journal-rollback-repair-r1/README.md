# Исполнение разрешённого journal repair

Пользователь «разрешаю»; resolution/write fence: commit `68433ec7`.
Единственный runtime delta — четыре строки из согласованного
`mvp6_nx_same_revision_rollback_proposed.patch` в `resolve_prediction()`.

RED на исходном journal: 77 assertions / 10 failures. GREEN после patch:
77/77 PASS. Оба лога получены одной командой canonical Windows double Godot:
`--headless --path . --script res://tests/runtime/test_v0_mvp_6_prediction_rollback.gd`.
Это рабочий red→green эксперимент, не exact frozen acceptance.

Первые pickup/drop/correction cases заимствованы из внешнего frozen subject
`6b147d0300529a6b40568b4de0817d5cc7f95fdb` (PR #643). Его generic duplicate-adoption
patch не используется: согласованный fix ограничен resolution path.
Добавлены place/transfer, независимый oracle для surviving prediction,
duplicate response, timeout/newer authority и реальные M7 bridge completion/stop.
Bridge использует существующий FakeRuntime NX6, проверяет full canonical view
в emitted signal и отсутствие изменения authority snapshot.

Два предварительных RED запуска в local artifacts содержали дополнительные
ошибки нового теста: сигнал не испускается при submit; replica имеет иной формат,
чем canonical snapshot. Positive control исправлен на публичный
`project_canonical_snapshot()`. RED/GREEN здесь используют одинаковый final test.
Исходные failures не ослаблены. Новый тест обязателен в `validate_mvp6_native.py`:
exit 0, отсутствие fatal markers и ровно один PASS с 77 assertions.

Далее: frozen exact regression, NX A/B с явно обозначенным repair input,
независимые Reviewer/Verifier и main-owned integration через HUMAN merge gate.
Main baseline пока неисправлен; PC0 directional RED; MVP6 IN_PROGRESS.
