# MVP5 — ограниченная диагностика воспроизводимости P2 R1

Родитель: `V0-MVP-R1-WO-001`, `E2026-09-09-V0-MVP-R1`, состояние `IN_PROGRESS`.
Это выполнение существующей проверки, не новый runtime worker и не независимая приёмка.

## Зафиксированный subject

- Product HEAD: `b78de4980328bb7b4d19e030bb7f0fa5d9976cd8`.
- Product TREE: `0bfdd7595e10f007815bb666e62e7c5575172173`.
- Product branch: `feature/v0-mvp-playable-seamless-planet-r1`.
- Diagnostic carrier: `control/v0-mvp5-p2-repro-b78de498-r1`.
- Разрешённые изменения carrier: этот документ и уже разрешённый родительским Work Order файл `.github/workflows/mvp5-material-output-validation.yml`.
- Runtime, исходные тесты, параметры взаимодействия, канонические владельцы, feature ref и main не изменяются.

## Основание

World/core run `34967384187`, attempt 1, artifact `10396726706`, ZIP SHA-256 `03b0cf1e930930f593b81febb5483a46be1ed393103b2173a058e94d842c9026`.
Все 1028 индексированных файлов повторно проверены, несовпадений нет.
`actor.json` фиксирует `item.pickup -> ITEM_INTERACTION_OUT_OF_RANGE` после успешного результата `_move_toward`.
Помощник возвращает успех последней команды движения, но не проверяет достижение цели. Это статически подтверждённая слабость свидетельства; причинная регрессия продукта или конкретная race пока не доказаны.
Диагноз сохранён в evidence carrier коммитом `c2931661a724cf37844fa2846a0dca21f6bc96a3`.

## Исполнение

В чистом checkout точного продукта и на каноническом Linux double Godot с SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`:

1. Проверить HEAD/TREE и отсутствие tracked changes, выполнить fresh import.
2. Последовательно три раза запустить неизменённый `tests/runtime/test_v0_p2_live_shared_state_convergence.gd`.
3. Для каждого запуска сохранить команду, exit code, длительность, полный основной лог и непосредственные JSON/log результаты native harness. Не копировать пользовательские профили/cache/секреты.
4. Проверить неизменность tracked checkout, связать все сохранённые файлы SHA-256 manifest с product/carrier/run/attempt.
5. После диагностики использовать только фактические результаты. Любой failed repeat делает diagnostic job красным; последующий успех не стирает предыдущий отказ.

Это отдельная целевая диагностика, а не замена полной регрессии или независимого Verifier. Уже выполняющийся world/core attempt 2 не отменяется и не дублируется.

## Решение по результатам

- Повторный `ITEM_INTERACTION_OUT_OF_RANGE`: воспроизводимость подтверждена; следующий bounded repair обязан сначала восстановить authoritative reach/input/snapshot causal trace и проверить sibling callers. Изменять legacy P2 helper вне текущего write fence без отдельного разрешённого scope amendment нельзя.
- Три успеха: сбой не воспроизведён в этой выборке; нельзя заявлять доказанное отсутствие дефекта или закрывать старый failure как исправленный.
- Infrastructure/import failure: сохранить ошибку как диагностическую, не выдавать её за результат P2.
- MVP5 leaf по-прежнему требует terminal exact full world/core, свежий независимый Verifier и корректную coordinator closure. Whole-MVP acceptance и merge не разрешены.

## Восстановление

Читать этот документ, exact feature ref, workflow runs данного carrier и сохранённый manifest. Артефакты получать через GitHub connector. В чате выводить только небольшие JSON summaries и точные failure windows, не полные логи и не список ZIP members.
