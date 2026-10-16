# FABRIC R5.6.1 R1 — Work Order / Design Brief

**Риск:** HIGH (research source provenance + external canonical transition),
но собственная write authority, production Construction/Matter schema и
архитектурные владельцы не изменяются. Реализация — additive.
**BASE:** R5.5 R4 merge `e74c20725a760e56cac01ffd9eaf39a5e9ad5a90`.
**Feature:** `research/fabric-r5-6-1-canonical-delta-binding-r1`.
**Status:** IMPLEMENTER CANDIDATE; independently VERIFIED/MERGE_READY не заявляется.

## Problem / Current behavior

R5.5 фиксирует один 100k subject и заранее известный единственный successor;
не умеет получать другие допустимые canonical Construction изменения без
hardcoded hashes. BRIDGE-4 уже принимает реальный внешний Construction successor,
но ограничен определённым overload break. Следующий шаг — data-driven
source provenance, не второй мир или device-specific solver.

## Selected design / alternatives

**Выбрано:** новый версионированный research-контракт `R56DeltaContract` и `R56DeltaSession`
как derived consumer настоящего внешнего `ConstructionConstructStore`.
Контракт компилирует initial/after через уже существующий
`Bridge4CanonicalWorldAdapter.compile_authoritative()`. Он предлагает
стандартный `ConstructionConstructMutation.OP_UPDATE` с before/after;
применить mutation может **только** внешний canonical owner.
Сессия заново читает canonical Store на commit boundary; до observation
старая derived binding считается stale и не возвращается для исполнения.

Отвергнуты: новое физическое ядро; второй registry/revision service;
hardcoded full successor под новый Fixture; возвращение stale BAKE после
подтверждённой ошибки; немедленное внедрение многодетального solver в main.

## Scope R1 (bounded)

- Состояния `OPERATIONAL`/`DAMAGED`; операции `BREAK_BOND`, `REPAIR_BOND`,
  `SET_BOND_STRENGTH`, только одно изменение существующей связи на commit;
  Construction part set и Matter Batch не изменяются.
- Подготовка proposal без canonical write; проверка полей и ревизии через
  реальные `ConstructSnapshot`, `ConstructionConstructMutation` и BRIDGE-4.
- Source revision растёт ровно на 1; event IDs уникальные; принадлежность
  source к authority не переносится из derived artifact.
- Derived session не умеет делать canonical write, может только observe
  committed Store и выдать новое `graph_hash / binding_checksum / events`.
- При несовпадении внешнего successor fail closed; stale derived binding
  нельзя читать. Новое состояние можно принять только после корректной
  external mutation / согласованной verified proposal.
- Проверки на двух разных конструкциях (разные размеры, связи, координаты),
  три последовательных события в каждой, повторяемость и новые falsifiers.

## Non-goals / deferred

Нет общих geometric contacts, нелинейной/тепловой динамики, node additions,
part-mass changes и dynamic aggregated index, general multi-authority or
concurrent CAS, полного restart/recovery после повреждения (R5.6.2),
physics execution с переносом скоростей и энергии (R5.6.3), сервера и
production networking (R6). Full graph compile может быть O(N) на каждый
source event R1: это **не** R5.6.1 R2 dynamic aggregate performance.

## Gates R1

1. Exact identity/base; diff additive; никаких closed R5 kernels и main.
2. Canonical Linux cold import+parse, 3 детерминированных запуска R5.6.1.
3. BRIDGE-4 regression; strict evidence + independent falsifier.
4. Windows exact same HEAD / Godot canonical double; payload parity.
5. Fresh Reviewer/Verifier, separate human merge authorization.

**После R1:** отдельный R5.6.1 R2 для физически корректного индексированного
обновления массы, моментов, произвольных связей и оценки стоимости изменений.

## R1 implementer notes / API

Используемые файлы:

- `r5_6_1_canonical_delta_contract_v1.gd` — stateless `prepare(...)` и
  `validate_external(...)`, event ID и строгое одно изменение связи.
- `r5_6_1_canonical_delta_session_v1.gd` — `start(store, source, matter,
  authority)`, `prepare(...)`, `observe_external_commit(...)`,
  `read_binding()`, `abandon_proposal()`; только borrowed store reference.
- `fabric_r5_6_1_canonical_delta_acceptance.gd` — реальные Construction snapshots,
  два разных графа, 3 × source revisions, независимый Bridge-4 graph recompile,
  stale fencing, replay, divergent external writes, authority/Matter mutation,
  detached proposal copy. Вариант alpha повторяется в свежем session.

**Важное различие:** `prepare` не выполняет `Store.apply_mutation`; его обязан
выполнить authorized Construction owner. Если он подтвердил изменение, но
`observe_external_commit` не смог принять derived state, старая derived
binding становится `R56_STALE_CANONICAL_SOURCE` и не может быть опубликована.
Само подтверждённое изменение canonical мира не откатывается.

`SET_BOND_STRENGTH` меняет единственный параметр связи, но не массу/материал.
Произвольная `DAMAGED` конструкция без разрушенных bond'ов в R1 отклоняется:
никакие иные причины повреждения не должны молча очищаться очередным ремонтом.

Implementation не предполагает, что `Bridge4` автоматически предоставляет
новый численный solver: R1 результат — авторитетно привязанный derived graph,
а продолжение времени и FULL/ROM state handoff остаётся R5.6.2/R5.6.3.
