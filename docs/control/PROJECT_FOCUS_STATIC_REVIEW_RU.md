# Независимое статическое ревью PROJECT-FOCUS-2026-09-05-R1

Reviewed subject: `2a502c28269ebc3e07d4570d4497af8bf2d7b628`.

Base: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.

Reviewer: отдельный агент `focus_static_review`, не автор реализации.

Review scope: `STATIC_ONLY`.

Verdict: `PASS` только для статического ревью указанного control-кандидата.

Verification status: `NOT_RUNTIME_VERIFIED`.

## Что проверено чтением

- Маршрутизация CLI до загрузки устаревшего execution epoch, отсутствие runtime authority у overview/candidate и удержание P7 runtime lease.
- Разделение закрытия принятой P7 и ещё не принятого MVP; чтение acceptance из того же закреплённого main commit, что и scheduler.
- Совместимость прежнего трёхаргументного API `load_checkpoint_acceptance` с новым необязательным keyword-параметром.
- Ветки output schema для обычного execution, project overview и control routing.
- Согласование целей, registry, scheduler, train, work map и признаков запрета нового runtime.
- Локальная область исследовательских findings, роли ECO/FABRIC tracks и отсутствие автоматического принятия по branch reports.
- Обновлённые ожидания текущей policy в существующих tests, сохранение исторических activation/epoch данных и изолированный future-main fixture для CLI hold.

## Закрытые замечания предыдущих чтений

| Замечание | Исправление в reviewed subject |
| --- | --- |
| Принятую P7 нельзя было закрыть до активации MVP | Завершение разрешено только для выбранной P7 с canonical acceptance; MVP остаётся незавершённым |
| Scheduler и acceptance могли относиться к разным main snapshots | Acceptance lookup получает закреплённый commit и проверяет его ancestry |
| Research findings превращались в обязательный продуктовый блокер | Exit 3 ограничен продуктовой и общей контрольной областью; family-local findings остаются видимыми |
| Checker пропускал противоречия operational mirrors | Добавлены проверки фаз, checkpoints, P7.7 flags и primary evidence; prebuild помечен historical-only |
| Отсутствовал обязательный false у registry P7.7 | `runtime_mutation_authorized: false` добавлен |
| Обязательные тесты ожидали старое оперативное состояние | Обновлены current-policy ожидания; dispatch при hold должен отклоняться |

В пределах указанного статического scope оставшихся блокирующих дефектов не обнаружено. Это утверждение не распространяется на исполнение новых команд, CI, регрессионные результаты или работоспособность симулятора.

## Ограничения и дальнейшие gates

Reviewer не запускал Python проекта, новые команды controller, тесты, CI, PC0 или Godot. Regression tests присутствуют в reviewed subject, но в рамках этого ревью не исполнялись. Запрет пользователя на запуски имеет приоритет над обычными требованиями AGENTS о Drive/Close; эти gates здесь не объявляются пройденными.

Этот документ не объявляет checkpoint acceptance, не закрывает P7, ECO или FABRIC, не разрешает runtime dispatch и не заменяет независимую verification либо human merge gate. Перед принятием изменения остаются проверка исполнением в разрешённой сессии и предусмотренное проектом решение о merge. Последующий кодовый или контрактный diff требует нового review соответствующего subject.
