# V0 / P — правила развития продуктовой ветки

**Owner:** `main`  
**Machine policy:** `config/control/harness/v0-product-train-policy.v1.json`  
**Policy amendment:** `H0-PTRAIN-2026-08-18-R1`

## Что такое P

P — это не набор независимых экспериментов. Это одна последовательная продуктовая линия V0, в которой каждый следующий checkpoint продолжает уже работающий playable world:

```text
P0 playable frontier
→ P1 world items / containers
→ P2 reconnectable shared state
→ P3 resource mining
→ P4 real-resource Construction
→ P5 equipment / tools
→ P6 persistent shared outpost
→ POST-P6 seamless decision
→ V0-SM1 seamless product integration (или явный defer)
→ P7 bounded terrain mutation
→ P8 first mobile construct / ship
```

Главное правило: следующий P checkpoint не начинается, пока предыдущий не принят как checkpoint. Reviewed implementation head сам по себе не является accepted predecessor.

## Текущее положение — P4 closure

Текущий runtime P4 уже реализован и должен оставаться замороженным:

```text
exact runtime/evidence target:
2a6721cdf02fa1134c59d1ab98bb7b597c66821d
```

Сейчас задача P — не писать ещё runtime-код P4 и не начинать P5, а закрыть control lifecycle P4.

После merge PR #130 текущий canonical main:

```text
598e92bb29a147bf12208d8549ddecaa4c9781ab
```

Оставшаяся последовательность P4:

```text
1. подтвердить Project Control NON_RED на exact current main после #130
2. повторно прогнать PR #127 против исправленного main
3. если exact reviewed subject #127 остаётся валиден — интегрировать control-only ledger repair
4. продолжить append-only closure ledger без runtime mutation
5. записать оставшиеся required predicates
6. сформировать V0_P4_CHECKPOINT_PROPOSED
7. пройти требуемый Director/Human acceptance gate
8. только после принятого P4 активировать P5
```

Runtime P4 не должен ремонтироваться в ходе этой closure-последовательности, если не появляется новый доказанный runtime defect. В таком случае текущий closure останавливается и открывается отдельный repair lifecycle.

## Как открывать каждый следующий P checkpoint

Для P5, P6, P7, P8 применяется одинаковая схема:

```text
PREDECESSOR CHECKPOINT ACCEPTED
        ↓
fetch current main + referenced branches
        ↓
standard + directional Project Control NON_RED
        ↓
main объявляет exact accepted predecessor product base
        ↓
fresh bounded successor branch
        ↓
new Project Epoch + Work Order
        ↓
risk classification + Design Brief
        ↓
main-owned mutation lease rotation
        ↓
Director dispatch
        ↓
bounded runtime implementation
        ↓
freeze exact runtime head
        ↓
independent Reviewer + Verifier
        ↓
append-only closure
        ↓
checkpoint proposal / required merge gate
```

Запрещено продолжать следующий продуктовый этап на случайной исторической ветке, начинать его от bare `main`, если при этом теряется принятая продуктовая композиция, или считать donor branch новым product base.

## P5 — Equipment / Tools

P5 должен сделать предметы не просто содержимым inventory, а рабочими инструментами игрового цикла.

Минимальная цель:

```text
canonical item
→ equip / unequip server-authoritative
→ equipment state replicated to A/B
→ reconnect restores exact equipment state
→ at least one real gameplay action requires/uses equipped tool
```

Рекомендуемый первый вертикальный slice:

```text
mining tool
→ equip
→ mining action validates equipped tool
→ canonical resource output remains P3 authority path
```

Затем можно связать tool/equipment с Construction UX, но нельзя создавать отдельную equipment inventory truth.

Исторический CH9.6 — donor presentation/equipment semantics, не product base и не новый Item Graph owner.

P5 не eligible сейчас. Для его активации нужны accepted P4, exact successor base, новый Work Order/Epoch и ротация mutation lease на P5.

## P6 — Persistent Shared Outpost

P6 — первый стабильный продуктовый baseline.

К концу P6 должна работать целая петля:

```text
join
→ mine
→ inventory / container
→ equip tool
→ build from real resources
→ second client sees canonical result
→ disconnect / reconnect
→ server restart
→ same canonical outpost reconstructed
```

Минимальные acceptance outcomes:

- два клиента видят одно общее состояние outpost;
- inventory/equipment/Construction восстанавливаются после reconnect;
- canonical outpost восстанавливается после server restart;
- минимум 5 чистых end-to-end повторов;
- 30-minute two-client soak;
- zero duplicate canonical truth.

После P6 мы получаем первую действительно полезную стабильную точку, которую уже разумно распределять между authorities.

## После P6 — обязательный seamless gate

После принятия P6 **P7 автоматически не запускается**.

Сначала открыть:

- `docs/plans/V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`
- `docs/plans/V0_MULTI_ROUTE_PROJECTION_FABRIC_RU.md`

И main-owned решением выбрать одно:

```text
ACTIVATE_V0_SM1
или
DEFER_V0_SM1_WITH_EXPLICIT_HUMAN_DECISION
```

Если SM1 активируется, он стартует от accepted P6 product baseline. SM0 и MRPF используются только как capability/evidence donors.

Цель V0-SM1 — перенести в реальный продукт:

- exactly one active authority;
- stable player/entity identity;
- monotonic authority epoch;
- seamless route role pivot;
- derived multi-authority projections;
- existing canonical Item Graph/Construction/persistence owners.

После этого P7 terrain и P8 mobile construct строятся уже поверх seam-aware продукта.

## P7 — bounded terrain mutation

P7 добавляет ограниченное реальное изменение terrain/material state в playable loop.

Правило ownership:

```text
V0 consumes canonical Matter/terrain authority
V0 does not create private terrain or material truth
```

P7 начинается только после accepted P6 и durable post-P6 seamless decision.

## P8 — first mobile construct / ship

P8 должен впервые собрать в одном реальном продукте:

```text
Construction
+ canonical items/resources
+ persistence
+ reference frames
+ terrain/world relation
+ selected authority/seam model
→ mobile construct / ship
```

Не нужно сразу делать полноценный space game. Первый P8 должен быть bounded mobile construct с проверяемым lifecycle, persistence и authority behavior.

## ECO и другие research branches

ECO сейчас экспериментальная ветка и **не блокирует P**.

Общее Harness-правило:

```text
research branch status != product blocker
```

Research может стать настоящим блокером только если возникает одно из условий:

```text
main explicitly registers dependency
canonical foundation owned by that program becomes required
ownership/directional-watch audit proves real intersection
P Work Order explicitly consumes that research capability
```

Поэтому RED/unfinished/active состояние ECO само по себе не должно останавливать P4/P5/P6.

## Что делать агенту, когда пользователь говорит «продолжи P»

1. Прочитать `v0-product-train-policy.v1.json`.
2. Определить current checkpoint и phase.
3. Не выбирать следующий checkpoint по названию из roadmap — проверить его eligibility.
4. Если current checkpoint в closure, закрывать его control lifecycle, а не писать successor runtime.
5. Если predecessor accepted — подготовить main-owned successor activation.
6. Создавать свежую successor branch только от exact main-declared accepted product base.
7. Сохранять один runtime mutation worker до принятия H0.3 scheduler.
8. Не превращать research/lab donor в product authority.
9. Любой новый network foundation/authority change fail-closed маршрутизировать в NX.
10. Любой второй Item Graph, Construction, persistence или terrain truth — STOP_AND_REPLAN.
