# ECO XFER1 — Readiness Pre-Design (research-only, non-authoritative)

Статус: `RESEARCH_ONLY_NON_AUTHORITATIVE / NOT_AN_XFER1_ACTIVATION`.
Ревизия: `ECO-R78-2026-08-22`.
Связанные документы: `docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`, `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## 0. Что этот документ НЕ делает

```text
НЕ активирует   XFER1
НЕ авторизует   production binding, runtime activation, persistence, network
НЕ подменяет    owner-approved canonical contracts G/ENV/MAT/WQ/SD/TF
НЕ изменяет     XFER1 = BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```

Единственная цель — заранее зафиксировать, какие вопросы должен закрыть каждый будущий канонический контракт, чтобы ECO-binding стал возможен сразу после их появления, без проектирования с нуля в момент открытия XFER1.

## 1. Контекст границы

```text
XFER0 = ACCEPTED_BOUNDED_DESIGN   (research simulator contract, принят)
XFER1 = BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
LIVE  = DEFERRED_UNTIL_XFER_AND_CANONICAL_FOUNDATIONS
```

EVO3 research evidence не является production authorization. Открытие XFER1 — human/owner gate на стороне канонических foundations.

## 2. Чему научила принятая цепочка E3.1–E3.7

Принятые stage-контракты EVO3 выработали повторяющийся шаблон, который канонические контракты должны поддержать со своей стороны:

| Шаблон из EVO3 | Требование к каноническому контракту |
|---|---|
| `stable_planet_identity` / `stable_time_key` | Канонические G/ENV/MAT/WQ/SD/TF обязаны давать стабильные идентичности планеты и времени, устойчивые к перекомпиляции |
| `field_provenance_hash` + git blob + sha256 входов | Каждый canonical field должен иметь machine-checkable provenance (blob/hash), а не «актуальный файл по пути» |
| snapshot-bound семантика (без global RNG/local clock) | Canonical fields поставляются как замороженные снапшоты; недетерминизм извне запрещён контрактом, а не дисциплиной |
| exact raw bytes для serialization authority | Production binding должен сохранять те же свойства: authority только у byte-exact входов |
| fail-closed неразрешённые состояния (`UNRESOLVED_SINGLE_SNAPSHOT`) | Контракт обязан определять явные fail-closed состояния вместо молчаливых значений по умолчанию |
| research namespace (`eco-research-species/…`) | Разделение research/canonical пространств имён должно быть взаимно однозначным и проверяемым |

## 3. Что должен зафиксировать каждый канонический контракт

Для каждого из шести foundations — одинаковый каркас из семи вопросов:

1. **Идентичность**: стабильные ключи (planet/spatial/time/reference-frame), версия и хеш контракта.
2. **Владение**: кто единственный owner поля; что запрещено присваивать консумерам (включая ECO research).
3. **Формат поставки**: byte-exact snapshot + blob/hash; правила обновления без перекрашивания истории.
4. **Детерминизм**: запрет RNG/локальных часов/environment-подмешивания на границе контракта.
5. **Fail-closed семантика**: разрешённые «не знаю»-состояния и их машинные метки.
6. **Гранулярность и масштаб**: минимальная/максимальная сетка, ожидания по размеру, ceiling.
7. **Совместимость с research chain**: как accepted E3.1–E3.7 артефакты ссылаются на это поле без переинтерпретации.

Специфика по полям:

- **G** (геометрия/гравитация): reference frame, стабильность identity рельефа между снапшотами.
- **ENV** (окружение): связь с `TF` без взаимного владения; правила температурных/влажностных полей против opportunity-семантики E3.2.
- **MAT** (материалы): соответствие substrate-семантике establishment-порогов E3.4.
- **WQ** (вода/качество): связь с moisture-осью семейств E3.8.
- **SD** (пространственные домены): отношение к research region graph E3.3 — canonical SD остаётся внешним, research-граф не претендует на canonical.
- **TF** (время): единственный источник сезонности; условие снятия `UNRESOLVED_SINGLE_SNAPSHOT` через мульти-снапшотную evidence (связь с E3.6-R).

## 4. Готовность ECO-стороны к XFER1

К моменту появления канонических контрактов research-сторона имеет:

- принятую детерминированную цепочку компиляции с capability-bound serialization;
- опыт predeclared-матриц генерализации (E3.8) и предстоящий unseen-challenge (E3.FINAL);
- политику no-retuning и byte-identity, переносимую на production binding.

Чего сознательно **нет** и не будет до XFER1: production runtime, persistence, network, транзакций, asset scatter truth.

## 5. Порядок действий при открытии XFER1 (черновик последовательности)

```text
owner публикует канонические контракты G/ENV/MAT/WQ/SD/TF
        ↓
Director dispatch XFER1 binding Work Order от exact main HEAD
        ↓
адаптеры E3.1 перепривязываются к каноническим полям БЕЗ retuning science
        ↓
полное регрессионное замыкание E3.0–E3.7 + byte-identity артефактов
        ↓
independent Reviewer + Verifier + PC0 audit
        ↓
human gate: активация production binding
```

Шаги 3–5 намеренно повторяют существующую harness-процедуру: открытие XFER1 не создаёт нового типа полномочий, а лишь меняет источник входов.
