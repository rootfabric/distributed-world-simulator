extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const R1 = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const R4 = preload("res://scripts/research/ecology/v2/body_construction_binding_v1.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const DamageRecord = preload("res://scripts/construction/damage/construction_damage_record.gd")
const RepairPlan = preload("res://scripts/construction/damage/construction_repair_plan.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_R4_FAIL " + message)

func _module(id: String, parent: String, role: String, start: Array, finish: Array, area: int = 0, reach: int = 0) -> Dictionary:
	var m := {
		"id": id, "parent": parent, "role": role,
		"start_mm": start.duplicate(), "end_mm": finish.duplicate(),
		"radius_mm": 1, "area_mm2": area, "reach_mm": reach,
		"cost": Body.stock(),
	}
	m["cost"] = Body.cost(m)
	return m

func _body() -> Array:
	return [
		Body.root(),
		_module("m000001", "m000000", "support", [0,0,0], [0,100,0]),
		_module("m000002", "m000001", "collector", [0,100,0], [50,150,0], 500, 0),
		_module("m000003", "m000000", "absorber", [0,0,0], [0,-100,0], 0, 100),
	]

func _parts() -> Array:
	return [
		Part.create("part/support", "item/support", "BIO_PROXY", "support", 1.0, [0.0, 0.5, 0.0]),
		Part.create("part/leaf", "item/leaf", "BIO_PROXY", "collector", 0.2, [0.25, 1.25, 0.0]),
		Part.create("part/root", "item/root-part", "BIO_PROXY", "absorber", 0.3, [0.0, -0.5, 0.0]),
	]

func _damage_event(source_snapshot: Dictionary, body_modules: Array, conditions: Dictionary, damage_id: String = "damage/a10-r4") -> Dictionary:
	var request := DamageRequest.create(
		damage_id, "construct/tree", source_snapshot["checksum"], "part/root", [], [], conditions
	)
	if not bool(DamageRequest.validate(request).get("success", false)):
		return {}
	var target := Snapshot.create("construct/tree", "item/tree-root", 2, "DAMAGED", _parts(), [], {})
	var repair := RepairPlan.create("repair/" + damage_id.trim_prefix("damage/"), damage_id, target, [], [], [], [], request["checksum"])
	if not bool(RepairPlan.validate(repair).get("success", false)):
		return {}
	var record := DamageRecord.create(damage_id, request["checksum"], "d".repeat(64), repair, [], 5)
	if not bool(DamageRecord.validate(record).get("success", false)):
		return {}
	var projected := R1.project_construction_damage(
		request, record, source_snapshot, body_modules,
		{"part/support": "m000001", "part/leaf": "m000002", "part/root": "m000003"}
	)
	return projected.get("event", {}) if bool(projected.get("success", false)) else {}

func _run() -> void:
	var body_modules := _body()
	_check(Body.validate(body_modules).is_empty(), "BodyGraph fixture valid")
	var body_hash_before := C.digest(body_modules)
	var source_snapshot := Snapshot.create("construct/tree", "item/tree-root", 1, "OPERATIONAL", _parts(), [], {})
	_check(bool(Snapshot.validate(source_snapshot).get("success", false)), "Construction source snapshot valid")

	var binding := R4.create_binding(
		body_modules, source_snapshot,
		{"part/support": "m000001", "part/leaf": "m000002", "part/root": "m000003"}
	)
	_check(not binding.is_empty(), "exact BodyGraph/Construction binding created")
	_check(R4.validate_binding(binding, body_modules, source_snapshot).is_empty(), "binding validates against exact sources")
	_check(binding["mapped_module_ids"] == ["m000001", "m000002", "m000003"], "mapped modules explicit")
	_check(binding["unmapped_module_ids"] == ["m000000"], "unmapped root remains explicit")

	var overlay := R4.create_overlay(binding, body_modules, source_snapshot)
	_check(not overlay.is_empty() and overlay["revision"] == 0, "persistent overlay genesis")
	var initial_function := R4.effective_function(binding, overlay, body_modules, source_snapshot)
	_check(initial_function["collector_area_mm2"] == 500, "initial collector active")
	_check(initial_function["absorber_reach_mm"] == 100, "initial absorber active")
	_check(initial_function["active_module_count"] == 4, "initial body fully active")

	var event := _damage_event(source_snapshot, body_modules, {
		"part/root": "DEGRADED",
		"part/support": "DESTROYED",
	})
	_check(not event.is_empty(), "R1 produces exact C9-derived damage event")
	var applied := R4.apply_damage(binding, overlay, body_modules, source_snapshot, event)
	_check(bool(applied.get("success", false)) and not bool(applied.get("replay", false)), "R4 applies damage once")
	if not bool(applied.get("success", false)):
		_finish()
		return
	var damaged: Dictionary = applied["overlay"]
	_check(R4.validate_overlay(damaged, binding, body_modules, source_snapshot).is_empty(), "damaged overlay validates")
	_check(damaged["revision"] == 1 and damaged["applied_damage"].size() == 1, "damage receipt persisted")
	_check(damaged["destroyed_modules"] == ["m000001"], "direct destroyed module recorded")
	_check(damaged["disabled_modules"] == ["m000001", "m000002"], "destroyed support disables collector descendant")
	_check(damaged["degraded_modules"] == ["m000003"], "unrelated absorber remains only degraded")

	var function_after := R4.effective_function(binding, damaged, body_modules, source_snapshot)
	_check(function_after["collector_area_mm2"] == 0, "disabled collector contributes no area")
	_check(function_after["absorber_reach_mm"] == 100, "degraded absorber remains active")
	_check(function_after["active_module_ids"] == ["m000000", "m000003"], "effective body excludes disabled subtree")
	_check(function_after["active_module_count"] == 2, "effective module count reduced")
	_check(String(function_after["functional_hash"]).length() == 64, "effective function sealed")
	_check(C.digest(body_modules) == body_hash_before, "historical BodyGraph bytes are not mutated")

	var replay := R4.apply_damage(binding, damaged, body_modules, source_snapshot, event)
	_check(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "same damage event is idempotent")
	_check(replay["overlay"] == damaged, "idempotent replay changes no overlay bytes")

	var conflict_event := _damage_event(source_snapshot, body_modules, {
		"part/root": "DESTROYED",
	}, "damage/a10-r4")
	_check(not conflict_event.is_empty(), "conflicting same-id event fixture valid")
	var conflict := R4.apply_damage(binding, damaged, body_modules, source_snapshot, conflict_event)
	_check(not bool(conflict.get("success", false)) and conflict.get("error") == "A10_R4_DAMAGE_ID_CONFLICT", "same damage id with different bytes fails closed")

	var wrong_source := Snapshot.create("construct/tree", "item/tree-root", 2, "OPERATIONAL", _parts(), [], {})
	var wrong_binding_use := R4.apply_damage(binding, overlay, body_modules, wrong_source, event)
	_check(not bool(wrong_binding_use.get("success", false)) and wrong_binding_use.get("error") == "A10_R4_SNAPSHOT_BINDING", "binding cannot be replayed over another construct revision")

	var forged_event := event.duplicate(true)
	forged_event["events"] = Array(event["events"]).duplicate(true)
	forged_event["events"][0] = Dictionary(forged_event["events"][0]).duplicate(true)
	forged_event["events"][0]["module_id"] = "m000003"
	var forged := R4.apply_damage(binding, overlay, body_modules, source_snapshot, forged_event)
	_check(not bool(forged.get("success", false)), "tampered damage event rejected")

	var tampered_overlay := damaged.duplicate(true)
	tampered_overlay["disabled_modules"] = ["m000001"]
	_check(not R4.validate_overlay(tampered_overlay, binding, body_modules, source_snapshot).is_empty(), "overlay tamper rejected")

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_R4_DAMAGE_OVERLAY checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_R4_DAMAGE_OVERLAY PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_R4_FAILURE " + failure)
		quit(1)
