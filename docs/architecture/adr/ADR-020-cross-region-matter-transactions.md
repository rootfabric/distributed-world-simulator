# ADR-020: Durable cross-region Matter transactions

- Status: Proposed / MW10 candidate
- Date: 2026-08-03
- Checkpoint: `v17.12.0-simulation-mw10-cross-region-matter-transactions`

## Context

MW8 предоставляет single-owner regional authority, MW9 делает lease/handoff durable, а RL1 строит summaries по exact source revision. Одна excavation/deposition operation может пересечь boundary нескольких authority-regions. Последовательные независимые commits нарушили бы сохранение массы, создавали бы частично видимые revisions и позволяли бы RL2 собрать proxy из несовместимого состояния.

## Decision

Использовать детерминированную двухфазную транзакцию с durable coordinator journal:

1. Проверить exact MW9 leases и атомарно зарезервировать весь отсортированный region set.
2. Подготовить regions в лексикографическом порядке и сохранить receipt после каждого шага.
3. После подготовки всех participants записать необратимый `COMMIT_DECIDED` с global commit hash.
4. Commit-ить regions в том же порядке; после crash продолжать оставшиеся commits.
5. До decision при recovery записывать abort и rollback-ить только подготовленный suffix в обратном порядке.
6. Публиковать один representation invalidation batch только после global terminal commit через durable outbox.
7. Запрещать MW9 handoff зарезервированного region через interlock.

## Consequences

Положительные:

- сохранение массы проверяется до runtime mutation;
- нет частично опубликованной multi-region revision;
- crash recovery детерминирован;
- operation replay не повторяет canonical mutation;
- RL2 получает единый invalidation frontier.

Ограничения:

- coordinator repository пока является одним durable service, не quorum;
- транзакция ограничена одним Matter body и заранее известным region set;
- runtime participants обязаны реализовать идемпотентные prepare/commit/rollback;
- handoff integration требует обязательного interlock вызова.

## Rejected alternatives

- Best-effort sequential mutations: допускают частичное состояние и mass imbalance.
- Publish invalidation per region: делает несовместимые revisions наблюдаемыми.
- Abort after durable commit decision: нарушает atomicity после первого committed participant.
- Lock regions только в памяти: crash снимает fence и допускает competing transaction/handoff.
- Общий consensus в MW10: преждевременно расширяет scope; production quorum остаётся отдельным этапом.
