extends "res://scripts/research/fabric_bake0/r5_4_mixed_complexity_machine_v1.gd"
## R5.5 R1: amortize canonical successor construction and isolate scratch
## structural range-index ownership without changing any closed R5.4/R5.3 kernel.
## This fixture supports exactly the canonical one-bond local successor.
const U55 = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const S55 = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")
const L55 = preload("res://scripts/research/fabric_bake0/r5_indexed_sparse_damage_lifecycle_v1.gd")

var _prepared_successor: Dictionary = {}
var _prepared_successor_hash := ""
var _private_stage_index: Dictionary = {}
var successor_full_builds := 0
var successor_attempt_full_builds := 0
var successor_cached_attempts := 0

func initialize() -> Dictionary:
    var initialized: Dictionary = super.initialize()
    if not initialized.success:
        return initialized
    # Work outside the event path: exactly one canonical full digest build.
    var canonical: Dictionary = S55.create_subject(MACHINE_PARTS, true)
    if not bool(canonical.get("success", false)):
        return U55.failure("R5_5_SUCCESSOR_PREPARE_FAILED")
    if not S55.is_successor(structural_source, canonical):
        return U55.failure("R5_5_SUCCESSOR_BINDING_INVALID")
    _prepared_successor = canonical.duplicate(true)
    _prepared_successor_hash = U55.canonical_hash(_prepared_successor)
    # Copy once: no live/staged prefix-array alias, and no per-attempt clone.
    _private_stage_index = structural_index.duplicate(true)
    successor_full_builds = 1
    return U55.success(status())

func _stage_structural_local_event() -> Dictionary:
    if _prepared_successor.is_empty() or _private_stage_index.is_empty():
        return U55.failure("R5_5_SUCCESSOR_NOT_PREPARED")
    if U55.canonical_hash(_prepared_successor) != _prepared_successor_hash:
        return U55.failure("R5_5_SUCCESSOR_CACHE_MUTATED")
    if not S55.is_successor(structural_source, _prepared_successor):
        return U55.failure("R5_5_SUCCESSOR_BINDING_DRIFT")
    var captured: Dictionary = structural_runtime.capture_capsule()
    if not captured.success:
        return U55.failure("R5_4_STRUCTURAL_STAGE_CAPTURE_FAILED", {"cause": captured})
    var staged = _new_structural_stage()
    # Stage has its own durable prefix storage; the R5.1 index is read-only
    # by convention, so a stage may share ONLY this scratch-owned instance.
    var staged_source: Dictionary = structural_source.duplicate(true)
    var attached: Dictionary = staged.attach_range_index(_private_stage_index, staged_source)
    if not attached.success:
        return U55.failure("R5_4_STRUCTURAL_STAGE_INDEX_FAILED", {"cause": attached})
    var restored: Dictionary = staged.restore_capsule(staged_source, captured.details.capsule)
    if not restored.success:
        return U55.failure("R5_4_STRUCTURAL_STAGE_RESTORE_FAILED", {"cause": restored})
    var local: Dictionary = staged.local_unbake(1, L55.IMPACT_LOAD)
    if not local.success:
        return U55.failure("R5_4_STRUCTURAL_LOCAL_UNBAKE_FAILED", {"cause": local})
    # No create_subject(100000,true) on the event path.
    var successor: Dictionary = _prepared_successor.duplicate(true)
    var observed: Dictionary = staged.observe_canonical_break(successor, "topology-event/r5-4-local-break", 2)
    if not observed.success:
        return U55.failure("R5_4_STRUCTURAL_MUTATION_FAILED", {"cause": observed})
    var rebaked: Dictionary = staged.rebake_after_settle(true)
    if not rebaked.success:
        return U55.failure("R5_4_STRUCTURAL_REBAKE_FAILED", {"cause": rebaked})
    successor_cached_attempts += 1
    return U55.success({"runtime": staged, "source": successor, "local": local, "rebaked": rebaked})

func status() -> Dictionary:
    var s: Dictionary = super.status()
    s["r5_5_successor_full_builds"] = successor_full_builds
    s["r5_5_successor_attempt_full_builds"] = successor_attempt_full_builds
    s["r5_5_successor_cached_attempts"] = successor_cached_attempts
    s["r5_5_stage_index_isolated"] = not _private_stage_index.is_empty() and not _private_stage_index.is_same(structural_index)
    return s
