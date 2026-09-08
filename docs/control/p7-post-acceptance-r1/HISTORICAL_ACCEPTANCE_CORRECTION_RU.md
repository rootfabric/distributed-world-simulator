# Уточнение исторической P7 acceptance без переписывания истории

Исходная acceptance `V0-P7-R1-CHECKPOINT-ACCEPTED-001` остаётся неизменной.
Runtime и настоящие 330-stage/29-leaf результаты исходного P7 сохраняются.

## Доставка исторических R2 verdicts

Точные файлы восстановлены из commit
`0f9454c482803af7ddeec1ea0c944ad5e3c5d819`:

| Файл в docs/control/p7-eg1-world-core-repair-r1/review/ | Git blob |
|---|---|
| REVIEWER-RESULT-DCA12CEC-R2.v1.json | 8021cd51cdbd153c0f05b2b0d7b6d15864835fb4 |
| VERIFIER-RESULT-DCA12CEC-R2.v1.json | f31aec4c9b12b9e0d0863ed12a8343dcbcd1ff82 |

Теперь относительные ссылки исходной acceptance разрешаются в checkout.
Содержание, авторство роли, дата и reviewed/verified head не изменены.
Это исторические PASS для `dca12cec`, не независимая приёмка нового lock fix.
Verifier R1 FAIL сохраняется; R2 не объявляется проверявшим ещё не завершённый
CI. Новый валидатор вычисляет SHA256 восстановленных файлов в evidence.

## Фактический control-observation

В артефакте `10028335356`, run `34147956945`:
Overview=0, CheckConsistency=0, Drive=0, CloseRole=3,
CloseMission=8. Причина CloseRole: `EPOCH_REGISTRY_GENERATION_MISMATCH`.
Версия «Overview/CheckConsistency отсутствуют» неверна. Исторический epoch
с generation80 нельзя переписывать в generation81. Его отказ сохранён,
не whitelist-ится как PASS. Новая post-acceptance correction имеет собственные
проверки, не подменяемые завершением старой checkpoint mission.

Отдельный post-acceptance run `34173113080` на `438b21d0` упал на тесте
`test_valid_hold_routes_without_loading_obsolete_execution`: fixture ожидал
exit8, хотя принятое P7 закономерно дало exit0. Исправляется тестовая
изоляция, а не снятие защиты production controller.

## Авторизация и время

В оригинальной acceptance записана интерактивная директива владельца
«Да, merge + accept» с временем 2026-09-07T19:05:00Z. Исходная локальная
сессия этой correction не доступна, поэтому это отмечается как заявление
оригинальной записи, а не заново удостоверенный transcript.

Публичный комментарий `5574568635` в PR580 является запросом human gate,
а не самой авторизацией. Проверяемые GitHub integration times:
PR580 runtime merge — 2026-09-08T00:20:44Z;
PR584 acceptance merge — 2026-09-08T00:22:37Z.
Они не равны времени интерактивного решения. Историческое поле accepted_at
сохранено, но не используется здесь как время канонической публикации.

Текущее поручение пользователя разрешает исправить найденные недостатки.
Оно не используется для выдумывания независимых verdicts или отсутствующего
исторического подтверждения. Новая интеграция и acceptance addendum проходят
собственные обязательные условия. MVP не активирован этой correction.
