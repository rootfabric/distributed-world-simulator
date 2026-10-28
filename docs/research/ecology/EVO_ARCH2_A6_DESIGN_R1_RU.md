# EVO ARCH2 A6 — Persistent Environmental Feedback: Design Brief R1

Дата: 2026-09-12. Work Order: `EVO-ARCH2-A6-20260912-R1`. Risk: HIGH.

## Исходная точка и полномочия

Принятый research A5: `ce98434481c90f7661f787ceb89b07104a586a2f`, TREE `ea5437a3572ab7e65815ef6117e972b7e6e96cc3`, ref `acceptance/eco-evo-arch2-a5-r1`. Main наблюдён на `127c732a56cc5c25d5712f24a7627ed4bb877374`, registry generation 82. Пользователь явно разрешил изолированную реализацию A6; main-owned production checkpoint и дополнительный product worker не активируются. Harness Drive не находит execution `ECO_ARCH2_A6_PERSISTENT_ENVIRONMENTAL_FEEDBACK`; это не PASS и не основание менять catalog.

Обязательный маршрут прочитан: PROJECT_CONTROL, HARNESS_CONTROL, Development Harness, Review/Evidence, registry/goals/catalog, A0 reconciliation, A5 Work Order и runtime. В исходном A0 train A6 — persistent niche construction и abiotic update после extinction; A7 — Observatory, A8 — production-consistent snapshot/seam, A9 — ecological fidelity, A10 — selective integration, A11 — habitat acceptance. Локальный A6 snapshot не выдаётся за A8.

## Проблема

A5 оставляет мёртвую особь инертной: её ресурсы не исчезают, но экологического обратного потока нет. A4 умеет выполнять owner/epoch/revision-bound typed deposits/sinks, однако сам не доказывает источник deposit. Нельзя просто добавить `deposit` и оставить то же вещество доступным в corpse.

## Решение

Новый аддитивный `persistent_environmental_feedback_v1.gd` координирует один ограниченный локальный эксперимент поверх неизменённых A4/A5. Поле остаётся A4 state; источник жизни — A5. Это не global ENV/Authority/Region/Transaction owner.

Порядок шага: A5 living population -> регистрация новых смертей -> corpse return -> abiotic mineralization -> A4 field tick. Все изменения происходят на candidate; ошибка возвращает только failure, source не мутирует. Пустая/вымершая population не останавливает field tick и mineralization. Генотипы не меняются, mutation/crossover и автоматическое заселение потомками не входят в A6.

Corpse вычисляется из замороженного dead A5 snapshot. Возвращаемый material = metabolic material + unspent A2 material + material в реальных body modules. Возвращаемая water = только metabolic и unspent A2 water. A2 construction water — expenditure, а не доказанная связанная вода: её не возвращаем без отдельного контракта. Аналогично construction/branch energy не становится новой энергией. Оставшаяся metabolic/A2 energy уходит в явный heat sink. Исходный dead snapshot хранится только как provenance: второй spendable body balance не существует.

Material поступает в `organic_mg`, water — в `water_mg`, через A4 typed effects в точную anchor cell умершего организма. Возврат ограничен policy rate, remaining inventory и свободной ёмкостью. Невместившийся остаток остаётся в corpse. Порядок конкурирующих returns — canonical individual ID. Независимая abiotic mineralization переводит organic -> nutrient в той же cell через равные A4 sink/deposit; organic+nutrient сохраняется, nutrient capacity ограничивает conversion. Сигналы среды не переопределяются.

Paid propagules сохраняются в bounded outbox с точным paid-parent payload; их budget overflow отклоняет весь шаг, не уничтожая оплаченный transfer. Это экспортируемые результаты, не автоматически материализованные новые individuals.

## Доказательство сохранений вместо доверия событиям

Простые mutable cursors и самоподписанные totals повторили бы класс ошибок RM32–RM34. Выбран bounded deterministic replay от неизменяемого genesis. Сохраняется genesis (initial field, canonical A5 payloads, policy) и текущий frame; public validate/restore сверяют frame с реальным повторным исполнением. Restore требует expected genesis hash из внешнего manifest вызывающего: hash внутри файла не является аутентификацией. A5 payloads хранятся каноническими строками, чтобы новый envelope не сокращал допустимую глубину parent provenance A5.

Bounds: явные лимиты steps, population, cells, outbox, serialized bytes и replay-work. Их достижение — диагностируемый budget error, не смерть, maturity или silent truncation. Это bounded research proof, не production million-organism performance claim. Arbitrary изменение genesis вместе с внешним anchor означает новый эксперимент, а не продолжение прежнего.

Дополнительно проверяется сквозной баланс: initial field + initial available biomass/reserves + последующая external light energy = current field + living inventory + remaining corpses + paid propagules + новые irreversible sinks. Архивы умерших не суммируются второй раз.

## Альтернативы и риски

Изменять A5 schema/ledger — отклонено: нарушает frozen predecessor. Считать corpse inventory из cumulative growth целиком — отклонено: возвращает потраченную energy/water. Mutable event/receipt-only доказательство — отклонено: rehash forge. Production transaction/journal/authority — отложено до A8/A10. Replay дороже incremental trust; поэтому область и budget строго ограничены и измеряются, без скрытого ухудшения биологии.

## Проверки

Настоящее paid развитие/размножение/смерть; exact inventory и sinks; capacity saturation/release continuation; competing corpse ordering; negative coordinates/half-open bounds; empty population и extinction abiotic continuation; duplicate/stale owner/epoch/revision; coherent maintenance/corpse/field rehash forgery; malformed/oversized/deep payloads; outbox/budget rollback; closed donor -> field -> recipient loop и effects-off control; canonical restart равен непрерывному исполнению. A6 x2 byte-identical и все A5 repair/A0–A4/VIS5 regressions на приложенной pinned double-сборке.

После реализации: post-build critique, Evidence Map, точный self-hosted verifier и независимый Reviewer. Research acceptance/main merge не объявляются Implementer-ом.
