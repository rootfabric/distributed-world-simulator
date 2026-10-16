# FABRIC R5.6.1 R1 — narrow source-admission repair

## Причина ремонта

Свежий independent Reviewer обнаружил два воспроизводимых нарушения в R1
(исходный HEAD `ee1fa655981bba4c7adadd3e7d1d64b3635dfae1`):

- `F1` — произвольный `RefCounted` с методом `get_snapshot()` проходил
  `Session.start()` и мог имитировать внешний Construction commit.
- `F2` — после `prepare(BREAK_BOND)` согласованное изменение `session._pending`
  на другое допустимое `SET_BOND_STRENGTH` с тем же event ID позволяло
  принять другую canonical mutation и опубликовать неправильную derived state.

Independent RED test опубликован отдельно в
`review/fabric-r56-1-r1-canonical-provenance-falsifiers` и неизменённо
повторён перед narrow repair: exit 1, 3 ожидаемых failures.

## Узкий ремонт

1. `start()` принимает только экземпляр **точного** предварительно
   загруженного `ConstructionConstructStore` script, а не класс, наследующийся
   и переопределяющий `get_snapshot`, и не просто объект с похожим API.
   При `start` фиксируется `Object.get_instance_id()`. Любая последующая
   подмена ссылки на иной Store делает session fail-closed.
2. В `prepare()` значение полного original-proposal hash и его event ID,
   source checksum и Store ID захватываются локальными значениями внутри
   **лексического callable**. В отличие от изменяемого `_pending`, замена
   всех его полей после `prepare` не меняет захваченный исходный intent.
   `observe_external_commit` проверяет guard **перед чтением внешнего
   successor**, и отклоняет подмену с `R56_PENDING_PROVENANCE_MISMATCH`.
3. `abandon_proposal()` отклоняет повреждённую pending-запись; очищение
   `_pending={}` не разрешает новый prepare, пока существует оригинальный
   guard. После нормального commit/abandon guard сбрасывается.
4. Проверка полного `Delta.validate_external` и фактической canonical
   ревизии остаётся штатной и не ослабляется. FABRIC не получил методов
   записи в Construction Store; BRIDGE-4 и закрытые физические kernels
   не меняются.

## Доказательства

- Оригинальный reviewer RED -> GREEN (тот же скрипт без переписывания
  условий, expected outcome `exit 0`, `checks=7`, `failures=[]`).
- Дополнительная продуктовая narrow-регрессия (26 checks): фальшивый Store,
  поддельный наследник Store, подмена реального Store после старта, подмена
  pending, отклонение скрытого abandon, защита повторного prepare после
  стирания pending, корректный abandon, внешний commit, чтение настоящей
  revision и replay rejection; неизменность опубликованных graph/source/events
  после отказа и stale fencing.
- Оригинальный R5.6.1 full acceptance `203/0` + BRIDGE-4 `49/0` сохраняются.
  Linux/Windows runner'ы требуют новую narrow-регрессию и строгий evidence
  collector (формат `fabric.r5_6_1.exact_evidence.v2`).

## Честные границы

В исследовательском R1 trusted caller передаёт конкретный
ConstructionConstructStore. Проверка типа и ID **не является**
криптографическим подтверждением идентичности удалённого сервера:
любой код, которому уже разрешено создавать подлинные Store и напрямую
менять все внутренние поля session/callable, находится за пределами
принятой модели угроз. Callable защищает исходное intent от подмены
**одного изменяемого pending DTO**, но не от замены самого исполняемого
кода/Callable произвольным вредоносным кодом в том же процессе.

Owner-issued durable mutation receipts, cold restart, event-log exactly-once,
многопоточная синхронизация и R5.6.1 R2 dynamic aggregate indexing
остаются отдельными следующими задачами. Runtime R1 не стал новым world
writer/authority или численным solver. Full graph compile/O(N) и дорогие
хеши пока допускаются, локальная O(1) стоимость не заявляется.

Для merge: canonical Linux/Windows exact на новом frozen HEAD/TREE,
независимые fresh Reviewer+Verifier, затем отдельный human gate.
`main` не изменять; PR #774 оставлять DRAFT.
