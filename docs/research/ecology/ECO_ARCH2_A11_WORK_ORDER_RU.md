# ECO ARCH2 A11 — Visible Persistent Evolving Habitat

## Identity / execution

- Work Order: `ECO-ARCH2-A11-R1-WO-001`.
- Epoch: `E2026-09-26-ECO-ARCH2-A11-R1`.
- BASE_MAIN: `6b336af8faeadbd7f69c96b62dc30d25150f45a7`.
- BASE_TREE: `70ef1302b6e0fab6b4569778b18daf9757f6b493`.
- Branch: `feature/eco-arch2-a11-persistent-habitat-r1`.
- Predecessor: A10.5 R2, merged PR #685; frozen product `4198f11222adb7ce78a335e2a6569ea9cbe4f577` / `4545f66e4d56f2fb9b158dcd5ecb42a135e248c0`.
- Risk: HIGH (persistence, public orchestration boundary), no ownership promotion.
- State: IMPLEMENTATION_IN_PROGRESS. Implementer does not self-accept.

## Scope reconciliation / Design Brief

Каноническая roadmap R2 определяет A11 как **Visible persistent evolving habitat acceptance**. Предварительный набросок в чате о A12–A15 не является заменой этой roadmap. A11 переносит уже принятый A10.5 Workbench в запускаемый persistent habitat; не строит ещё один ecological simulator и не обещает бесконечную жизнь при bounded A5/A6 contracts.

Текущее поведение: Polygon имеет единый canonical runtime, UI, checkpoints внутри процесса, canonical mutation, WORLD_COMPAT adapters и bounded tests. Нет цельной persistent habitat scene с явным cross-process restore receipt, failure-safe disk transport и acceptance такой пользовательской сессии.

Выбранное решение: небольшой composition/orchestration слой над ExperimentController + EcologyWorkbench, versioned habitat preset, durable transport существующего shared-runtime checkpoint, caller-owned external SHA admission, видимая scene с save/resume/status и bounded acceptance. Биология, field, lineage, BodyGraph, mutation и Matter/Region остаются у существующих owners. State staging при restore не создаёт второго живого habitat.

Отклонены: сериализация Node tree как biological truth; свой формат biological state; самоподписанный save без внешнего якоря; невидимый reset при corrupt save; поднятие population/corpse caps ради PASS; UI-owned evolution; изменение production world/authority.

## Predicates P0–P7

P0. Exact base, scope, owner map, Design Brief и durable execution record.

P1. WORLD_COMPAT field-patch hardening: direct live patch не может mint stocks или обойти ACTIVE admission; LAB edits остаются разрешёнными. Regression/adversarial coverage. Не ослаблять A10.5 tests.

P2. Версионированный self-contained habitat preset: FREE, canonical founders, wet/dry/dark, explicit seed/horizon, genuine inherited mutation и feedback. Preset — данные, не новый biological owner.

P3. Persistent session: checkpoint transport использует controller.serialize_state/load_state и shared ecology_runtime_checkpoint_v1; full bundle bound к caller-owned SHA. Failed restore не меняет live controller. Wrong hash, fully rehashed alternate save, invalid manifest/state и missing anchor отвергаются. Disk saves immutable/content-addressed, bounded reads/writes; no silent fallback/reset.

P4. Visible habitat scene: existing Workbench instance, Generic Realizer, pause/step/speed/inspector, save/resume actions и explicit restore receipt. One live controller. UI/LOD не меняют canonical hash. Startup restore через external receipt, new experiment — только явное действие.

P5. Deterministic continuation: uninterrupted trajectory == save/reload/new-process continuation at same tick. Full physical WORLD_COMPAT envelope сохраняется через existing adapter; no free zone stocks. Production ownership не активируется.

P6. Bounded longer experiment и causal observations: growth/resources/birth/inherited mutation/death-return через canonical transitions; honest population/corpse/horizon limits, failure не выдаётся за extinction/успех. No silent culling, cap increase or lineage loss.

P7. Exact Godot tests + A10.5 regression + Project Control, evidence hashes, post-build critique, independent whole-diff Reviewer/Verifier before acceptance. Runtime merge is a separate human gate.

## Allowed / forbidden paths

Allowed: `scripts/ecology/habitat/**`, `scenes/ecology/habitat/**`, `validation/ecology/evo_arch2_a11/**`, `scripts/ecology/workbench/experiment_controller_v1.gd` (only canonical field-patch admission hardening), A10.5 owner/architecture doc errata, A11 docs/launcher/exact-CI support. Existing Workbench may receive only a minimal presentation/host integration hook if needed and tested.

Forbidden: main-owned registry/scheduler/acceptance fabrication; changes to historical frozen refs; new Region/Matter/Terrain/Construction authority; alternative A3/A4/A5/A6 biology; raising canonical caps; relaxing SHA/version/assertion gates; automatic merge or force-push.

## Validation / recovery

Use repository-owned exact CI on canonical Godot 4.7.1 double. Windows SHA: `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`; Linux SHA: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Current container Git DNS route failed (`Could not resolve host: github.com`); GitHub connector works. Edit/commit through connector, execute in repository-owned CI. Do not retry failed clone route or use Actions as Git transport. Recover from branch + exact commits and this Work Order, not ephemeral tool handles.

Next action: implement bounded persistent session, preset, scene and tests, run exact evidence. Independent review and verifier remain pending until explicit durable verdicts; no A11 CLOSED claim from implementation alone.
