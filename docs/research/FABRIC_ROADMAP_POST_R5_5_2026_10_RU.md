# FABRIC — актуальная дорожная карта после R5.5 (16 октября 2026)

**Статус:** предлагаемая R5.6 исследовательская программа; **не** автоматическая активация в `main`.
**Research baseline:** R5.5 R4 MERGED, PR #750, `e74c20725a760e56cac01ffd9eaf39a5e9ad5a90`.
**Старый документ:** `FABRIC_CURRENT_ROADMAP_R4_1_R4_2_R5_RU.md` — историческая R4/R5 программа, не оперативный статус.
**Владение:** `main`/PC0/Construction/Matter имеют приоритет; исследования не создают второй world owner.

## Главная цель

Сложная структура → derived physical graph → компактное исполнение, которое безопасно
инвалидируется при подтверждённом изменении canonical Construction/Matter. Число
канонических деталей не должно автоматически определять цену каждого физического тика.
Ни один из перечисленных ниже новых этапов не считается закрытым без exact, независимого
review/verifier и явно заданных ограничений scope.

## Текущее подтверждённое состояние

| Этап | Фактически доказано | Ограничение |
| --- | --- | --- |
| R5.0–R5.2/T1–T16 | Measurement/reduction/falsification ladder — закрытые исследовательские результаты сохраняются | Не считать составленные устройства production physics |
| R5.3 | Recursive four-level ROM + causal rebuild, закрыт | Linear/fixed canonical research scenario |
| R5.4 | Mixed 100k structural + recursive 15-node machine | Одна локальная структурная мутация и отдельная recursive-global ревизия; не полный произвольный мир |
| R5.5 | Кэшированный known successor, source/prefix integrity, cross-platform exact | Одна фиксированная 100k-конструкция, один canonical break, code-backed хеши; не общий incremental successor |

R5.5 приёмка: PR #750 MERGED; ревью PASS_WITH_FINDINGS / verifier VERIFIED,
Linux/Windows exact PASS. Это **закрытый эталон**; изменения делать в новой ветке.

## Пересмотренный порядок (не заменять его новым R5.7 World Integration)

```text
R5.5 R4 MERGED / fixed-scene reference
            │
            ▼
R5.6.1 — GENERAL CANONICAL SOURCE & DELTAS        ◀ CURRENT RESEARCH
    R1 read-only Construction delta proposal/observation
       external authoritative commit, two different constructions, repeated events
    R2 dynamic indexed aggregates & incremental successor for bounded edits
       (separate gate; NOT achieved by R1)
            │
            ▼
R5.6.2 — MULTI-EVENT LIFECYCLE / COLD RECOVERY
    damage → repair → second damage, transient state, exact-once, interrupted commits
            │
            ▼
R5.6.3 — COUPLED DYNAMIC EXECUTION
    power ↔ load ↔ thermal ↔ structure; transients, conservation/error envelopes,
    FULL/ROM transfer, NO_SAFE_BAKE and actual global causal propagations
            │
            ▼
R5.6.4 — SAFETY-FIRST EXECUTION BUDGET
    reuse B0.6 admissible fidelity/hysteresis and existing execution budget;
    deterministic fair work scheduler, overload policy, no stale/unsafe execution
            │
            ▼
R5.6.5 — GENERALIZATION / STRESS / COST AMORTIZATION
    varied graph families, 5k/20k/100k, event bursts, multiple machines,
    CPU/RSS/latency tails, compile/rebuild amortization and adversarial falsifiers
            │
            ▼
R5 CLOSE — DURABLE RESEARCH ACCEPTANCE
    quantitative + qualitative compression, physical parity, bounded scope,
    independent reviewer/verifier, canonical Windows/Linux, documented nonclaims
            │
            ▼
INTEGRATION-R6 — FRESH CURRENT-MAIN CONSUMER
    real owner/lease/persistence/network, one physical writer; human merge gate
```

**R5 CLOSE и INTEGRATION-R6 сохраняются.** Название «R5.7 World Integration»
из прежней краткой схемы **отменено** во избежание второго интеграционного трека.
Интеграционный R6 не разрешает автоматически переносить огромную research lineage
в `main`: нужен свежий consumer и минимальный перенос проверенных возможностей.

## Правила архитектуры R5.6

1. Construction/Matter держат source/revision/authority; FABRIC имеет только derived,
   discardable representations и предложения. Подтверждение source mutation внешнее.
2. Не создавать новый solver, регистр мира, write authority или собственный production
   scheduler. BRIDGE-4 и B0.6 переиспользуются как исходные интерфейсы.
3. Safety evaluator имеет абсолютный приоритет над оптимизатором стоимости. При
   невозможности безопасно исполнить тик запрещены дешёвый unsafe mode и stale cache;
   нужна диагностируемая overload/fallback политика (R5.6.4).
4. Ревизия canonical source инвалидирует старое physical execution **сразу**.
   Неудачный BAKE не может откатить уже подтверждённое разрушение. REBAKE — не
   canonical mutation. Recovery восстанавливает source прежде любого кеша.
5. При изменении одного элемента проверять обязательный causal closure, а не требовать
   фиксированное «не больше 20 деталей». В настоящем глобальном случае допускается
   глобальный пересчёт при явном причинном обосновании.
6. R5.6.1 R1 допускает O(N) компиляцию/снимок малого bounded-тестового графа. Он
   **не** обещает O(local) обновление большого префиксного индекса; dynamic aggregation
   — отдельный acceptance R5.6.1 R2. Избегать неучтённых хешей и deep copy в perf-claim.
7. Для каждого этапа проверки: валидный runtime сценарий, falsifier, транзакционный
   rollback/stale, deterministic fresh replay, изменение geometry/IDs без patch kernel,
   явный перечень не покрытых свойств.
8. Экспериментальный код не должен импортировать fixture из `tests/` как физический
   источник. Тестовая машина передаётся через Construction/Matter contracts.

## R5.6.1 — ближайший контракт и критерии

R1 (первый исполняемый срез): `ConstructSnapshot + MatterBatch + AuthorityEnvelope`
→ независимая proposal с настоящим `ConstructionConstructMutation.OP_UPDATE` →
**внешний** `ConstructionConstructStore.apply_mutation` → проверенное наблюдение
в derived FABRIC graph. Поддержать BREAK/REPAIR/SET_BOND_STRENGTH для любых
допустимых bond IDs в как минимум двух разных графах; три последовательных события,
статус stale до observation, строгие отказы на повтор, mismatched event,
конкурирующий authoritative successor и изменение authority. Неиспользованные
состояния не выдумывать. R1 не исполняет общую динамическую физику: это R5.6.3.

R2: обновляемые агрегаты для массы/моментов/диапазонов, bounded изменить
партию/материал/часть, trust root и обработка произвольного edge delta без
hardcoded canonical successor. Работу индекса измерять отдельно от запросов.

## SHIP-LAB-1 — видимый интеграционный полигон

Сохранять SHIP-LAB-1 как независимый bounded lab, не новый gate V0.
Ранний research MIN: собрать → подключить → проверить силы/моменты → оборвать
управляющий сигнал → восстановить. Полный CLOSE: повреждение mount/frame,
selective detail, ремонт, cold restart, вторая компоновка и independent acceptance.
Исторический проект документа остаётся [PR #730](https://github.com/rootfabric/distributed-world-simulator/pull/730)
(DRAFT/не merge); перед любым merge PR #730 надо синхронизировать его с
актуальной R5.5/R5.6 картой. Product consumer только через R6.

## Evidence и human gates

Каждый R5.6 slice: exact base HEAD/TREE, scoped Work Order/Design Brief,
canonical Linux/Windows если затронуты численные/physical semantics, red/green,
separate independent Reviewer и Verifier, PC0 directional audit при актуальном
интеграционном checkpoint. Merge в исследовательскую ветку — отдельный human gate;
`main` напрямую не изменять. Roadmap publication ≠ acceptance runtime.
