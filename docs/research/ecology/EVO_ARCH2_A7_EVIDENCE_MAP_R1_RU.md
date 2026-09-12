# A7 — Evidence Map / Post-build critique R1

Work Order: EVO-ARCH2-A7-20260912-R1. Risk: HIGH. IMPLEMENTED_CANDIDATE; не acceptance.

## Владельцы и поверхности

A7 protocol/session: только setup/controller ограниченного эксперимента. A4 владеет field semantics, A5 — жизнью, A6 — feedback/replay. Все их исходники и тесты сохранены. Единственный renderer получает копию полного source-bound phenotype. UI не создаёт собственный рост/ресурсы.

Public entrypoints: start, advance, observe, save_text/load_text, export_report; UI signals Play/Step/Reset/Save/Load/Export. Siblings: каждый из трёх сайтов, live/corpse/outbox, wet/dry/dark, common-garden, effects-off, A3 none. Новых production или architecture owners нет.

| Predicate | Executable evidence |
|---|---|
| Все предобъявленные seeds / wet-dry-dark | arch2_a7_acceptance.gd: three-seed loop |
| A3 mutation / none и неподменённый parent | founding_genome + paired treatment controls |
| Common-garden / effects-off | same genotype и body/field equality; real A6 return/intake differences |
| Functional/visual source equality | phenotype.body_hash == digest(representation.modules); UI source hashes |
| Полный баланс | initial + external == current + sinks, все каналы/сайты |
| Atomic step / restore | later-site replay failure; missing/swapped site; stale revision/anchor |
| Coherent tampering | rehashed return ledger отвергается A6 replay |
| Bounds | non-whitelisted seed, malformed bool, unknown keys, >2MiB, horizon=16 |
| Управление / rendering | arch2_a7_ui.gd вызывает настоящие Button signals, viewport PNG/source report |
| Cross-process restart | arch2_a7_restart.gd write/read с внешним manifest |
| Preserved predecessor | exact diff fence + unchanged A6/A5/RM/A0–A4/VIS5 suites |

## Critique

NO_MATERIAL_REFACTOR_REQUIRED в bounded scope. Setup/founding mutation, experiment model и projection разделены. UI selection/speed отсутствуют в biological state. Рисуется полный X/Y/Z, не старая XY-only проекция. Модель не хранит дублируемый simulated phenotype; каждый отчёт производен и detached. Ни один mutable event не считается causal proof. Replay затратен и ограничен горизонтом; production performance не заявляется.

Дисковые snapshots content-addressed, но manifest остаётся caller-owned и не является production journal. Malformed/partial load не мутирует model. Преднамеренно нет live genome edit и automated descendant materialization — это обошло бы accepted A5 provenance. Clone common-garden и founder mutation controls не выдаются за selection/speciation/multigeneration evolution.

## Точные доказательства

Prepublication core/UI tests и viewport получены локально на pinned double Godot. Они ещё не означают PASS опубликованного SHA. Final source HEAD/TREE, original logs/digests, self-hosted run/artifact и independent reviewer публикуются отдельно в validation evidence/PR после freeze. Не переписывать этот snapshot для ретроспективного PASS.

Research acceptance, main-owned checkpoint activation и runtime merge различны. Main-owned A7 execution не был объявлен; этот user-authorized isolated Work Order не меняет registry/catalog/scheduler и не утверждает global PC0 GREEN. После exact verification и independent review — отдельное решение о research acceptance; A8 не запускается молча.
