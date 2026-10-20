# EVO ARCH2 — Roadmap R6 (после A14.5)

Статус: A14.6 R1 PRODUCT CANDIDATE / acceptance pending.
База: main ae9a669336d93b3497fa78e5bb6d8eb3a21a0211.
Исторические roadmap R2–R5 остаются неизменными; R6 корректирует
отставшее описание «A13 CURRENT» после принятых A13/A14 шагов.

## Карта принятых результатов

| Этап | Фактическое состояние |
|---|---|
| A0–A10.5 | canonical evolvable ecology / совместимый LAB workbench |
| A11 | visible persistent evolving habitat, принят |
| A12 | canonical 256 population/256 corpses, принят |
| A13 | exact worksets, spatial, active/sleeping, parallel prepare/advance, FULL/REDUCED/PATCH, принято |
| A14.1 | measurement research; не считать ускорение доказанным |
| A14.2 | adaptive fidelity advice (same canonical kernel), принято |
| A14.3 | bounded estimated-CPU budget/wake replay, принято |
| A14.4 | budgeted LAB live loop, measured noncanonical wall telemetry, принято |
| A14.5 R1 | resumable A5 PREPARE/one GLOBAL ALLOCATE/ADVANCE, принято |
| A14.5 R2 | компактный защищённый transient cursor, принято |
| A14.5 R3 | LAB opt-in staged frames, cancellation/rollback/cursor memory cap, принято |
| **A14.6 R1** | **CURRENT: измерить конкретные bottleneck и resource dependency frontier, NO kernel changes** |
| A14.6 R2 | next: detached bounded preparation and R2 global allocator proof |
| A14.6 R3 | next: opt-in incremental atomic allocator admission when independently exact |
| A14.7 | next: reproducible full LAB GUI frame-latency and multi-tick throughput soak |
| A15 | next: separate guarded scale contracts >256 only with evidence |
| A16 | next: WORLD_COMPAT transactional owner/source, restart, Region/Matter integration |

## Неизменяемая причинная граница

Один канонический Field и общий глобальный A5 allocator связывают
требования организмов в настоящем тике. Ни один регион или sleeping
tile не может независимо продвинуть biological truth, используя только
локальный resource allocator. A14.6 сначала доказывает структуру
зависимостей заявок, включая второй pro-rata проход с нулевыми
первичными долями.

Стадии могут быть подготовлены или рассчитаны на временной копии.
Единый канонический commit допускается только после всех глобальных
grants, полного ADVANCE, propagule admission и A6 feedback. Ни часть
тик-фронтира, ни host profiler не попадают в A8 checkpoint.

## Честные performance-гейты

A14.5 R3 Windows 256 популяции: PREPARE p95 ~1.17s;
ALLOCATE p95 ~1.11s; ADVANCE p95 ~4.79s, при малой выборке.
Это НЕ статистически устойчивый p95, НЕ CPU-time и НЕ SLA.
A14.6 R1 фиксирует конкретные workset, buckets, retries, cursor
bytes и A4/A5/A6 latency без обещания реального ускорения.
Сравнивать равные **committed canonical ticks** после cold/warm,
на одном движке и железе, с точными hash/checkpoint эталонами.

Целевой продуктовый gate в будущих A14.7: измеренный main-thread frame
budget и устойчивое продвижение экологии без бесконечного scheduler debt.
Число миллисекунд должно быть определено в отдельном hardware/UX brief,
а не выдано за уже достигнутую гарантию.

## Что не относится к A14.6 R1

Изменение биологических законов A3–A6; A4 grant rounding; canonical
revision/ledger/owner; увеличение лимитов; per-region independent
truth; production WORLD_COMPAT opt-in; synthetic tick skips; жёсткий
preemptive wall clock deadline; окончательное закрытие экологической ветки.
