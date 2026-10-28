# EVO ARCH2 A6 — Evidence Map / Post-build critique R1

Work Order: `EVO-ARCH2-A6-20260912-R1`. Risk: HIGH. Статус: IMPLEMENTED, pending final exact self-hosted verification and fresh independent review. Этот документ не является acceptance.

## Изменение и владельцы

Один новый research orchestrator `scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd`. Public entrypoints: `create`, `advance`, `validate`, `serialize`, `deserialize`, `balance`. A4 field/typed-effect и A5 lifecycle/parent-witness contracts используются без изменений. Ни один существующий runtime/test A0–A5 или VIS5 не редактировался. Production ecology, simulation, network, config/control, architecture и main не менялись. Новый global owner не создан.

Цепочка вызовов: A6.advance -> replay admission -> A5.step_population(living only) -> capture exact paid emission/death -> A4.apply_effects(corpse deposit) -> A4.apply_effects(organic sink + nutrient deposit) -> A4.advance_tick -> cross-compartment conservation -> one candidate state. Dead A5 snapshot остаётся неизменным доказательством, не вторым расходуемым запасом. Нехватка ёмкости оставляет вещество в corpse; ошибка позднего этапа не возвращает частично изменённое состояние.

## Карта проверок

| Поверхность | Проверка |
|---|---|
| Empty/extinct abiotic continuation | `arch2_a6_exact_acceptance.gd`, `_empty_abiotic`, `_death_inventory_and_exhaustion` |
| Paid body, decomposition and nutrient reuse | `_paid_body_and_closed_loop`, 100 мг intake против 0 при effects-off |
| Capacity and spatial locality | `_capacity_and_order`, `_spatial_locality`; permutation, saturation, negative coordinates, half-open boundary |
| Paid outbox and parent death | `_propague_outbox`; genuine A5 materialization control, persistence |
| Snapshot replay and external anchors | `_restart_and_rollback`; stale owner/epoch/revision, external genesis/revision |
| Coherent rehash forgery | `arch2_a6_adversarial.gd`; coordinated corpse/field refund сохраняет A4 hash/conservation, но отклоняется replay |
| Siblings of forge | heat refund, fake death time, mutable MODULE_CREATED, unfunded field input, duplicate/erased corpse, clock splice, duplicate/unpaid seed |
| Resource/work limits | 32 individuals, 64 cells, 64 steps, steps × max(1, initial population) <= 512, 128 pending propagules, 2 MiB canonical envelope; explicit budget failure, no biological reinterpretation |
| Partial-commit rollback | field revision/tick limits after candidate death/return; parent and source unchanged |
| Existing A5 depth boundary | `arch2_a6_lineage_energy.gd`: real funded generation 8 survives A6 envelope/restart; paid generation-8 emission remains stored, generation-9 materialization still forbidden by A5 |
| External energy vs sinks | real collector receives 5000 mJ external energy; 10000 + 5000 = 14786 remaining + 214 spent in witness |
| Cross-process recovery | `arch2_a6_restart.gd` write process exits, read process loads external manifest and snapshot; continuation hash matches uninterrupted control |

Expected A6 counters: 77 core + 76 adversarial + 11 lineage = 164 assertions, each suite twice; independent write/read recovery twice. Counter expectations and all A5 regression scripts are frozen in `validation/ecology/evo_arch2_a6/verify.py`.

Prepublication local exact run used attached Godot `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`; local source HEAD `47f943440978bd9dc9facce82596398de05fec21`, TREE `337055004191fa932e1591d15dd8241b8ce138a8`. Full local verifier PASS: A6 x2, process restart, A5 exact 69/69 x2, reviewer repairs 29/29 x2, all existing RM11–23 / RM25–30 / RM32–34 x2, A4 32/32, A0–A3 86/86, VIS5 521/521. Local source commit is not the final published commit; byte pins for seven implementation/test/verifier files are in `local-tested-blobs.v1.json`. Remote exact run and independent review must refer to the final published HEAD/TREE; their durable sink is the A6 PR and Actions artifact, not an edited retrospective PASS here.

## Post-build critique

Verdict: NO_MATERIAL_REFACTOR_REQUIRED within bounded research scope. Replay intentionally trades throughput for a checkable transition history and does not claim production scale. Serialized A5 payloads avoid adding nesting to the existing ancestry proof. No new event count is trusted as causal proof. Replay also checks byte/balance admissibility of every intermediate frame, so a later smaller state cannot validate an earlier oversized transition.

Prepublication findings were repaired without touching predecessors: (1) a removed/reinserted dictionary key needed a String rather than Godot StringName for canonical encoding; (2) two reproduction fixtures needed genuinely wet sample ratios, not just permissive minimum thresholds; (3) output preservation initially reused the child-materialization depth budget and rejected a legitimate emission from generation 8. Emission now uses the accepted witness check at parent depth zero; only actual child materialization consumes an extra generation. The dedicated lineage test retains the negative ninth-generation control. Test type annotations and verifier root/portable SHA calculation were corrected before final publication.

## Граница результата и оставшиеся gates

Не реализуются автоматическая materialization/outbox consumption, mutation/crossover, бесконечная replay history, live policy/field interventions, physical chemical calibration, shading/climate feedback, distributed ownership/seam, production disk journal. Это локальный A6 resource-feedback experiment; A7 Observatory и A8 production snapshot/seam остаются отдельными этапами.

Caller owns the trusted experiment manifest and atomically selecting its latest durable snapshot. `advance` is a pure candidate transition, not a global storage commit service. Reusing the same old source computes the same candidate; applying an old revision to the latest source fails closed. `deserialize` needs the external expected genesis hash AND revision. Editing both data and trusted external anchors declares another experiment; this is not authentication against a malicious authority.

Main-owned Harness has no A6 execution for `ECO_ARCH2_A6_PERSISTENT_ENVIRONMENTAL_FEEDBACK`; observed `ACTIVE_EXECUTION_NOT_FOUND`, not PASS. This user-authorized isolated research candidate does not activate a product worker or rewrite catalog. Required before acceptance: final pinned self-hosted verifier, fresh independent review, explicit research acceptance decision. Main/production merge remains a separate human gate; global PC0 GREEN is not inferred from these tests.
