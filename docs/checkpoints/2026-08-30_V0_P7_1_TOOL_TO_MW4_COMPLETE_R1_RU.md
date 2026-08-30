# V0 P7.1 — Tool → Existing MW4 — COMPLETE

Дата: 2026-08-30

## Статус

**P7.1 COMPLETE / MERGED.** Весь checkpoint **P7 остаётся IN_PROGRESS**.

- exact runtime subject: `28c47e26969608b126e6097bc8a26bd9c593be8c`
- runtime tree: `99629227f66b15092df5d798f7706364bfaadf1d`
- runtime merge PR: **#341**
- canonical runtime merge: `e86ec851b263ac6fca8177921b01cb7486fdff2f`
- exact accepted SM1 execution base: `acb9379cacc413fc25a65117fb1627f5a01b9736`

## Что реализовано

P7.1 добавляет один stateless product gate `authorize_mutation(request)` между существующим MW6 command ingress и существующим MW4 mutation owner.

Путь:

```text
MW6 validated MatterMutationRequest
  -> canonical V0 player identity
  -> SM1 one-writer authorize_write
  -> P5 canonical equipped mining-tool item_id
  -> server-side projected bounded reach
  -> existing MW8 regional authority
  -> optional existing MW9 durable fence
  -> existing MW6
  -> existing MW4 Matter mutation
```

Нового Matter/Terrain truth, Item Graph, persistence, replay ledger, replication protocol или authority directory не создано.

## Exact verification

Godot: `4.7.1.stable.double.custom_build.a13da4feb`

- P7.1 gate: **83/83**
- real P5→SM1→P7→MW8→MW6→MW4 integration: **30/30**, MW4 result = **COMMITTED**
- P5 mining-tool regression: **36/36**
- MW6 authority/replication regression: **130/130**
- Project Control exact head: runs **33305605035** and **33305871495**, SUCCESS

Source was exported from exact GitHub head by run **33305614883**, artifact **9730349477**; archive SHA-256:
`abf05c2580ed669f609f77ec9cf729af471c3f9ec2f82f7f68be398cc83737fd`.

## Исправления, найденные свежей проверкой

1. В integration test Godot выявил неявный Variant type inference — исправлено explicit typing.
2. Первая версия integration пыталась поставить второй MW6 command gate. Это правильно блокировалось foundation. Финальная архитектура использует **один P7 gate**, который внутри вызывает существующий MW8 gate.
3. Accepted MW5 fixture имеет большой excavation sweep; integration-only bound установлен 25 м только для допуска этой фиксированной тестовой геометрии. Отдельный focused test продолжает доказывать fail-closed reach при 4 м.

## Следующий шаг

**P7.2 — Bounded Planetary Matter Bubble.**

Он должен подключить реальную ограниченную область планеты к существующей Matter truth, не создавая второй terrain/Matter owner.
