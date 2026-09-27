# MVP4 R1 — bootstrap mismatch repair

Предыдущий subject `4ab5b80f14656a96fca4463ad55d81aaa97d58b0`, exact run `34764856985`, artifact `10319704752`.

Наблюдение: focused runtime завершился FAIL на первоначальном MW6 snapshot с `SAME_SEQUENCE_MATTER_SNAPSHOT_CONFLICT`, до копания. Сервер materialize-ил revision-zero procedural bricks, а клиент держал их только в presentation baseline, не в собственном MW6 replica store. Поэтому один stream_sequence=0 соответствовал разным state_hash.

Исправляется producer bootstrap клиента: после `Replica.configure` и до `activate_session` ровно те же validated revision-zero snapshots устанавливаются через существующий public `snapshot_store().put()`. Hash должен совпасть с procedural bootstrap. MW6 same-sequence/conflict/authority/session checks не изменяются. Любая дальнейшая мутация поступает только через `apply_frame`.

В первом CI также обнаружен исторический shutdown diagnostic в неизменённом R13 attestation test: 86 assertions / 0 failures / exit 0, но `ERROR: 6 resources still in use at exit`. Его не считать новым MVP4 runtime defect и не скрывать: отдельная baseline replay/classification требуется перед окончательным PASS всего matrix. Native live-owner 232/0, fixed-input 931/0, SM1 carry 89/0 прошли.

Ни один MVP4 predicate не закрыт. Следующий шаг: exact повтор focused gates; затем живой пяти-процессный graphical dig.
