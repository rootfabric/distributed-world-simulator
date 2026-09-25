extends RefCounted
## T12 composition manifest. Existing capsules stay derived; caller anchors trust.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const SCHEMA := "planet_simulator.fabric_ship_matryoshka_plan.v1"
const MAX_MODULES := 4
const ARTIFACTS := {
	"BATTERY_PACK": preload("res://scripts/research/fabric_bake0/battery_execution_artifact_v1.gd"),
	"POWER_STAGE": preload("res://scripts/research/fabric_bake0/power_stage_execution_artifact_v1.gd"),
	"LASER_EMITTER": preload("res://scripts/research/fabric_bake0/laser_emitter_execution_artifact_v1.gd"),
	"COOLING_LOOP": preload("res://scripts/research/fabric_bake0/cooling_loop_execution_artifact_v1.gd"),
	"LASER_CANNON": preload("res://scripts/research/fabric_bake0/laser_cannon_execution_artifact_v1.gd"),
	"SMART_SERVO": preload("res://scripts/research/fabric_bake0/smart_servo_execution_artifact_v1.gd"),
	"MOTOR_GENERATOR": preload("res://scripts/research/fabric_bake0/motor_generator_execution_artifact_v1.gd"),
	"GEARBOX": preload("res://scripts/research/fabric_bake0/gearbox_execution_artifact_v1.gd"),
}

static func graph_hash(kind: String, children: Dictionary) -> String:
	var bindings := {}
	for slot in children:
		bindings[String(slot)] = children[slot].capsule.checksum
	return U.canonical_hash({"kind": kind, "children": bindings, "version": 1})

static func compile(kind: String, children: Dictionary, request: Dictionary) -> Dictionary:
	var normalized := {}
	for slot in children: normalized[String(slot)] = children[slot]
	children = normalized
	if not kind in ["T12_TURRET", "T12_BANK", "T12_SHIP"]:
		return U.failure("T12_KIND_INVALID")
	var keys: Array = children.keys(); keys.sort()
	if kind == "T12_TURRET" and keys != ["cannon", "drive", "servo"]:
		return U.failure("T12_TURRET_SLOTS_INVALID", {"keys":keys})
	if kind == "T12_SHIP" and keys != ["bank", "battery"]:
		return U.failure("T12_SHIP_SLOTS_INVALID")
	if children.is_empty() or children.size() > MAX_MODULES:
		return U.failure("T12_CHILD_COUNT_INVALID")
	var roles := {"cannon":"LASER_CANNON", "drive":"POWER_STAGE", "servo":"SMART_SERVO", "bank":"T12_BANK", "battery":"BATTERY_PACK"}
	var components := 0
	var full_ops := 32
	var eval_ops := 32
	var bindings := {}
	for slot in keys:
		if typeof(children[slot]) != TYPE_DICTIONARY: return U.failure("T12_CHILD_BUNDLE_INVALID")
		var child: Dictionary = children[slot]
		var checked := verify(child, String(child.get("capsule", {}).get("checksum", "")))
		if not checked.success: return checked
		var required: String = "T12_TURRET" if kind == "T12_BANK" else String(roles[slot])
		if child.capsule.executable_kind != required: return U.failure("T12_CHILD_KIND_MISMATCH", {"slot":slot})
		bindings[slot] = child.capsule.checksum
		components += int(child.capsule.source_component_count)
		full_ops += int(child.capsule.full_operation_count)
		eval_ops += int(child.capsule.executable_operation_count)
	for field in ["canonical_source_frontier", "authority_envelope", "dependency_set"]:
		if typeof(request.get(field)) != TYPE_DICTIONARY: return U.failure("T12_REQUEST_INVALID")
	var checked := Frontier.validate(request.canonical_source_frontier)
	if not checked.success: return checked
	checked = Authority.validate_b0_safety(request.authority_envelope)
	if not checked.success: return checked
	checked = Dependencies.validate(request.dependency_set)
	if not checked.success: return checked
	var graph := graph_hash(kind, children)
	var source_bound := false
	for source in request.canonical_source_frontier.sources:
		if source.source_domain == "CONSTRUCTION" and source.source_hash == graph: source_bound = true
	if not source_bound: return U.failure("T12_GRAPH_FRONTIER_MISMATCH")
	var plan := {
		"schema":SCHEMA, "kind":kind, "child_checksums":bindings, "graph_hash":graph,
		"canonical_source_frontier":request.canonical_source_frontier.duplicate(true),
		"authority_envelope":request.authority_envelope.duplicate(true),
		"dependency_set":request.dependency_set.duplicate(true),
		"source_components":components, "full_ops_per_evaluation":full_ops,
		"compiled_ops_per_evaluation":eval_ops, "checksum":"",
	}
	plan.checksum = U.compute_checksum(plan)
	var cap := Capsule.create(String(request.artifact_id), kind, "NESTED_COMPOSITION",
		String(plan.canonical_source_frontier.frontier_hash), graph,
		U.canonical_hash({"kind":kind, "boundary":"ENERGY_AND_CALLER_STATE_V1"}),
		kind, String(plan.checksum), String(plan.checksum),
		U.canonical_hash({"kind":kind, "state_slots":keys}), components, full_ops, eval_ops,
		0, int(request.get("build_generation", 1)), ["HIERARCHICAL", "STATEFUL"],
		U.canonical_hash({"compiler":"T12_R1", "plan":plan.checksum}))
	if cap.is_empty(): return U.failure("T12_CAPSULE_CREATE_FAILED")
	var bundle := {"capsule":cap, "plan":plan, "children":children.duplicate(true)}
	checked = verify(bundle, String(cap.checksum))
	return U.success(bundle) if checked.success else checked

static func verify(bundle: Dictionary, expected_checksum: String) -> Dictionary:
	if not _shape(bundle, 0): return U.failure("T12_BUNDLE_SHAPE_INVALID")
	if typeof(bundle.get("capsule")) != TYPE_DICTIONARY: return U.failure("T12_BUNDLE_INVALID")
	var cap: Dictionary = bundle.capsule
	if cap.get("checksum") != expected_checksum or not U.is_lower_hex_64(expected_checksum):
		return U.failure("T12_EXTERNAL_ANCHOR_MISMATCH")
	var checked := Capsule.validate(cap)
	if not checked.success: return checked
	if bundle.has("plan"):
		var p: Dictionary = bundle.plan
		checked = U.validate_checksum(p)
		if not checked.success: return checked
		if p.get("schema") != SCHEMA or cap.executable_descriptor_hash != p.checksum or cap.executable_artifact_checksum != p.checksum:
			return U.failure("T12_PLAN_BINDING_MISMATCH")
		if p.graph_hash != graph_hash(String(p.kind), bundle.get("children", {})):
			return U.failure("T12_PLAN_CHILD_BINDING_MISMATCH")
		if p.kind != cap.executable_kind or cap.source_graph_hash != p.graph_hash:
			return U.failure("T12_PLAN_KIND_MISMATCH")
		var actual := {}
		for slot in bundle.children: actual[slot] = bundle.children[slot].capsule.checksum
		if actual != p.child_checksums: return U.failure("T12_CHILD_BINDING_MISMATCH")
	else:
		if not ARTIFACTS.has(cap.executable_kind): return U.failure("T12_UNSUPPORTED_CHILD")
		if typeof(bundle.get("artifact")) != TYPE_DICTIONARY or typeof(bundle.get("descriptor")) != TYPE_DICTIONARY:
			return U.failure("T12_CHILD_BUNDLE_INVALID")
		checked = ARTIFACTS[cap.executable_kind].verify_descriptor(bundle.artifact, bundle.descriptor)
		if not checked.success: return checked
		if cap.executable_artifact_checksum != bundle.artifact.checksum or cap.executable_descriptor_hash != bundle.descriptor.checksum:
			return U.failure("T12_CHILD_EXECUTABLE_MISMATCH")
	var identities := {}; var sources := {}
	return _walk(bundle, "root", identities, sources, "")

static func _shape(b: Dictionary, depth: int) -> bool:
	if depth > 8 or typeof(b.get("capsule")) != TYPE_DICTIONARY or typeof(b.get("children", {})) != TYPE_DICTIONARY: return false
	if b.get("children", {}).size() > MAX_MODULES: return false
	if b.has("plan"):
		if typeof(b.plan) != TYPE_DICTIONARY: return false
	else:
		if typeof(b.get("artifact")) != TYPE_DICTIONARY or typeof(b.get("descriptor")) != TYPE_DICTIONARY: return false
	for value in b.get("children", {}).values():
		if typeof(value) != TYPE_DICTIONARY or not _shape(value, depth + 1): return false
	return true

static func _walk(b: Dictionary, path: String, ids: Dictionary, sources: Dictionary, owner: String) -> Dictionary:
	var a: Dictionary = b.get("plan", b.get("artifact", {}))
	var checked := Capsule.validate(b.get("capsule", {}))
	if not checked.success: return checked
	if b.has("plan"):
		checked = U.validate_checksum(a)
		if not checked.success: return checked
		var bindings := {}; var count := 0; var full := 32; var cost := 32
		for slot in b.get("children", {}):
			bindings[slot] = b.children[slot].capsule.checksum
			count += int(b.children[slot].capsule.source_component_count)
			full += int(b.children[slot].capsule.full_operation_count)
			cost += int(b.children[slot].capsule.executable_operation_count)
		if bindings != a.get("child_checksums") or a.get("graph_hash") != graph_hash(String(a.get("kind", "")), b.get("children", {})):
			return U.failure("T12_CHILD_BINDING_MISMATCH", {"path":path})
		if count != int(a.get("source_components", -1)) or full != int(a.get("full_ops_per_evaluation", -1)) or cost != int(a.get("compiled_ops_per_evaluation", -1)):
			return U.failure("T12_COMPLEXITY_RELATION_MISMATCH")
		if b.capsule.executable_descriptor_hash != a.checksum or b.capsule.executable_artifact_checksum != a.checksum:
			return U.failure("T12_PLAN_BINDING_MISMATCH")
	else:
		if not ARTIFACTS.has(b.capsule.executable_kind): return U.failure("T12_UNSUPPORTED_CHILD")
		checked = ARTIFACTS[b.capsule.executable_kind].verify_descriptor(a, b.get("descriptor", {}))
		if not checked.success: return checked
		if b.capsule.executable_artifact_checksum != a.checksum or b.capsule.executable_descriptor_hash != b.descriptor.checksum:
			return U.failure("T12_CHILD_EXECUTABLE_MISMATCH", {"path":path})
		var fields := {}
		if b.capsule.executable_kind == "LASER_CANNON":
			fields = {"power":"power_stage_capsule_checksum", "emitter":"laser_emitter_capsule_checksum", "cooling":"cooling_capsule_checksum"}
		elif b.capsule.executable_kind == "SMART_SERVO":
			fields = {"motor":"motor_capsule_checksum", "gearbox":"gearbox_capsule_checksum"}
		if fields.size() != b.get("children", {}).size(): return U.failure("T12_CHILD_COVERAGE_MISMATCH")
		for slot in fields:
			if not b.children.has(slot) or b.children[slot].capsule.checksum != b.descriptor[fields[slot]]:
				return U.failure("T12_CHILD_BINDING_MISMATCH", {"path":path + "/" + slot})
	if b.capsule.source_graph_hash != a.get("graph_hash") or b.capsule.canonical_source_frontier_hash != a.get("canonical_source_frontier", {}).get("frontier_hash"):
		return U.failure("T12_CAPSULE_SOURCE_MISMATCH")
	for slot in b.get("children", {}):
		var found := false
		for dep in a.get("dependency_set", {}).get("dependencies", []):
			if dep.dependency_hash == b.children[slot].capsule.checksum: found = true
		if not found: return U.failure("T12_CHILD_DEPENDENCY_MISSING", {"path":path + "/" + slot})
	checked = Frontier.validate(a.get("canonical_source_frontier", {}))
	if not checked.success: return checked
	checked = Authority.validate_b0_safety(a.get("authority_envelope", {}))
	if not checked.success: return checked
	checked = Dependencies.validate(a.get("dependency_set", {}))
	if not checked.success: return checked
	var current_owner: String = a.authority_envelope.execution_owner
	if not owner.is_empty() and current_owner != owner: return U.failure("T12_CROSS_AUTHORITY", {"path":path})
	if ids.has(b.capsule.capsule_id): return U.failure("T12_ALIASED_INSTANCE", {"path":path})
	ids[b.capsule.capsule_id] = true
	for source in a.canonical_source_frontier.sources:
		if source.source_domain != "CONSTRUCTION": continue
		if sources.has(source.source_id): return U.failure("T12_ALIASED_MUTABLE_SOURCE", {"path":path})
		sources[source.source_id] = true
		if Authority.authority_epoch_for(a.authority_envelope, source.source_domain, source.source_id) != int(source.authority_epoch):
			return U.failure("T12_AUTHORITY_SOURCE_MISMATCH")
	for slot in b.get("children", {}):
		var child: Dictionary = b.children[slot]
		checked = _walk(child, path + "/" + slot, ids, sources, current_owner)
		if not checked.success: return checked
	return U.success()

static func own_live(b: Dictionary) -> Dictionary:
	var a: Dictionary = b.get("plan", b.get("artifact", {}))
	var r := {"artifact_state":"READY", "invalidations":[],
		"canonical_source_frontier":a.canonical_source_frontier.duplicate(true),
		"authority_envelope":a.authority_envelope.duplicate(true),
		"dependency_set":a.dependency_set.duplicate(true), "graph_hash":a.graph_hash,
		"interface_hash":b.capsule.interface_contract_hash}
	if a.has("material_catalog_hash"): r.material_catalog_hash = a.material_catalog_hash
	return r

static func live_tree(b: Dictionary, path: String = "root") -> Dictionary:
	var records := {path:own_live(b)}
	for slot in b.get("children", {}): records.merge(live_tree(b.children[slot], path + "/" + slot))
	return records

static func gate(live: Dictionary, anchors: Dictionary) -> Dictionary:
	if live.size() != anchors.size(): return U.failure("T12_LIVE_COVERAGE_MISMATCH")
	for path in anchors:
		if not live.has(path) or live[path] != anchors[path]:
			var ancestors: Array = []; var parts := String(path).split("/")
			for n in range(parts.size() - 1, 0, -1): ancestors.append("/".join(parts.slice(0, n)))
			return U.failure("T12_DEPENDENCY_INVALIDATED", {"refine_path":path, "rebuild_ancestors":ancestors,
				"unaffected_siblings_must_remain_compact":true})
	return U.success()
