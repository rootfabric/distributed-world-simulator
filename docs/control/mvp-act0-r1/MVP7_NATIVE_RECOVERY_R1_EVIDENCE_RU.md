# MVP7 R1 — native recovery prerequisite

## Проверенный subject

- HEAD: `909eaaffcdc66484c65f665f38d06d1227a6527e`
- TREE: `071d3dfbc4f00243f232e6ab35c0818766c45b33`
- Run: https://github.com/rootfabric/distributed-world-simulator/actions/runs/35438700820
- Job `mvp7-recovery`: `105885673961`, SUCCESS.
- Engine SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
- Artifact: `10582428919`, `mvp7-native-909eaaffcdc66484c65f665f38d06d1227a6527e-35438700820-1`.
- ZIP: 3,324,505 bytes; SHA-256 `7abdeba1aca86328d7ca3f28aa048ffba4d6c3e66b67075939401e7630c5d166`.

## Наблюдения из выполненного CI

| Процесс | PID | Assertions | Failures | Exit |
|---|---:|---:|---:|---:|
| produce | 4506 | 45 | 0 | 0 |
| recover1 | 4516 | 45 | 0 | 0 |
| recover2 | 4527 | 27 | 0 | 0 |

Всего 117 assertions, 0 failures. Import exit 0; все четыре лога без Parse Error/SCRIPT ERROR. Tracked checkout после выполнения чистый. Проверки разрешённых путей и неизменности зафиксированных prerequisite tests прошли. Read-only Harness Drive до и после вернул exit 0; это не независимая приёмка.

Подтверждены три разных процесса, два поколения native M6 checkpoint, точные checksum gameplay/replay/Item Graph между процессами, очистка старых transport-сессий, новая native session/ownership binding, запрет старых credentials, продолжение Item gameplay, отсутствие повторного server output, сохранение pending receipt, отказ checkpoint во время handoff, запрет мутаций после sealed cut, отказ испорченного replay до изменения gameplay, отказ rollback ниже явно требуемого поколения.

## Post-build critique / граница доказательства

Это **NATIVE_QUIESCENT_GAMEPLAY_PREREQUISITE**, а не полный MVP7. Материал в этом узком тесте имеет явно обозначенный synthetic fixture source; terrain dig provenance этим тестом не доказывается. Клиентское переподключение здесь выполнено через native service API, не через повторное ENet соединение. Terrain, Construction/collision, два graphical clients и их current-state resync должны пройти отдельную живую композицию. Исторический client Item command после изменения ownership epoch требует отдельного безопасного lookup: текущая авторизация обязательна, а старый operation fingerprint нельзя переписать или исполнить заново.

Нельзя засчитывать этот PASS как `MVP_RECONNECT_AND_RESTART` или подменять им оставшиеся predicates. Fresh Reviewer/Verifier не запускались, независимый verdict не заявлен. Codex agents не запускались. Parent `V0-MVP-R1-WO-001` остаётся `IN_PROGRESS`; MVP8 не начат; main не изменён.

## Следующий исполняемый шаг

Подключить согласованный native checkpoint к MVP6-наследнику, восстановить MW5 terrain и M0/C17 Construction, затем доказать новый процесс, новую transport-сессию, актуальную клиентскую проекцию и продолжение операций. Данные нельзя заново создавать из тестовых ожиданий. Допустимая модель отказа — restart из подтверждённого quiescent checkpoint; произвольный power-loss незакоммиченных операций пока не заявляется.
