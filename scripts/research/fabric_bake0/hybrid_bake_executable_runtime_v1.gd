extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ModeDescriptor = preload("res://scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd")
const P0Cache = preload("res://scripts/research/fabric_bake0/lazy_mode_cache_entry_v1.gd")
const P0Preflight = preload("res://scripts/research/fabric_bake0/hybrid_bake_preflight_v1.gd")
const P0Transition = preload("res://scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd")
const ExecutableMode = preload("res://scripts/research/fabric_bake0/hybrid_executable_mode_v1.gd")
const ExecutableCache = preload("res://scripts/research/fabric_bake0/hybrid_executable_cache_entry_v1.gd")
const ExecutableTransition = preload("res://scripts/research/fabric_bake0/hybrid_executable_transition_v1.gd")
const PhysicalBridge = preload("res://scripts/research/fabric_bake0/dynamic_rom_physical_bake_bridge_v1.gd")
const ExecutionRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_runtime_v1.gd")

const COMPILER_VERSION := "FABRIC-BAKE/B0.5-A/EXECUTABLE-HYBRID-R1"
const PACKAGE_SCHEMA := "planet_simulator.fabric_bake_hybrid_executable_mode_package.v1"
const SESSION_SCHEMA := "planet_simulator.fabric_bake_hybrid_executable_session.v1"
const EVENT_TIME_TOLERANCE := 1.0e-8

const PACKAGE_FIELDS: Array[String] = [
	"schema", "mode_contract", "mode_descriptor", "p0_cache_entry",
	"executable_cache_entry", "physical_bundle", "full_model",
	"rom_descriptor", "reduction_binding", "certification",
	"package_hash", "checksum",
]
const SESSION_FIELDS: Array[String] = [
	"schema", "current_cache_key", "current_mode_hash", "current_mode_id",
	"physical_session", "event_ledger", "transition_count",
	"last_event_hash", "checksum",
]
const EVENT_LEDGER_FIELDS: Array[String] = [
	"event_id", "event_hash", "transition_contract_hash",
]

static func preview_mode(blueprint: Dictionary) -> Dictionary:
	var checked := _validate_blueprint(blueprint)
	if not bool(checked.get("success", false)):
		return checked
	var bundle: Dictionary = blueprint["physical_bundle"]
	var physical: Dictionary = bundle["physical_artifact"]
	var signature := ModeSignature.create(
		String(physical["source_binding"]["frontier_hash"]),
		String(physical["source_binding"]["fabric_graph_hash"]),
		blueprint["active_relation_ids"],
		blueprint["complementarity_active_ids"],
		String(physical["boundary_contract"]["contract_hash"]),
		blueprint["dependency_versions"],
		COMPILER_VERSION
	)
	if signature.is_empty():
		return Utils.failure("B0_5_A_MODE_SIGNATURE_CREATE_FAILED")
	var binding := ModeDescriptor.resolved_rom_binding(
		String(physical["checksum"]),
		String(physical["reduced_state_schema_hash"]),
		String(physical["state_mapping"]["checksum"]),
		String(physical["reconstruction_descriptor"]["checksum"])
	)
	var descriptor := ModeDescriptor.create(
		String(blueprint["mode_descriptor_id"]),
		signature,
		physical["validated_domain"],
		binding,
		int(physical["build_generation"])
	)
	if descriptor.is_empty():
		return Utils.failure("B0_5_A_MODE_DESCRIPTOR_CREATE_FAILED")
	return Utils.success({
		"mode_signature": signature,
		"mode_descriptor": descriptor,
		"cache_key": descriptor["cache_key"],
	})

static func compile_mode(blueprint: Dictionary) -> Dictionary:
	var preview := preview_mode(blueprint)
	if not bool(preview.get("success", false)):
		return preview
	var descriptor: Dictionary = preview["details"]["mode_descriptor"]
	var contract := ExecutableMode.create(
		String(blueprint["mode_id"]),
		descriptor,
		blueprint["physical_bundle"],
		String(blueprint["rom_descriptor"]["descriptor_hash"]),
		String(blueprint["certification"]["certification_hash"])
	)
	if contract.is_empty():
		return Utils.failure("B0_5_A_EXECUTABLE_MODE_CREATE_FAILED")
	var p0_cache := P0Cache.create(descriptor)
	if p0_cache.is_empty():
		return Utils.failure("B0_5_A_P0_CACHE_CREATE_FAILED")
	var executable_cache := ExecutableCache.create(p0_cache, contract)
	if executable_cache.is_empty():
		return Utils.failure("B0_5_A_EXECUTABLE_CACHE_CREATE_FAILED")
	var package: Dictionary = {
		"schema": PACKAGE_SCHEMA,
		"mode_contract": contract,
		"mode_descriptor": descriptor,
		"p0_cache_entry": p0_cache,
		"executable_cache_entry": executable_cache,
		"physical_bundle": blueprint["physical_bundle"].duplicate(true),
		"full_model": blueprint["full_model"].duplicate(true),
		"rom_descriptor": blueprint["rom_descriptor"].duplicate(true),
		"reduction_binding": blueprint["reduction_binding"].duplicate(true),
		"certification": blueprint["certification"].duplicate(true),
		"package_hash": "",
		"checksum": "",
	}
	package["package_hash"] = Utils.canonical_hash(_package_identity(package))
	package["checksum"] = Utils.compute_checksum(package)
	var checked := validate_package(package)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"package": package,
		"status": "B0_5_A_EXECUTABLE_MODE_COMPILED",
		"cache_key": descriptor["cache_key"],
	})

static func validate_package(package: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(package, PACKAGE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if package.get("schema") != PACKAGE_SCHEMA:
		return Utils.failure("UNSUPPORTED_B0_5_A_MODE_PACKAGE_SCHEMA")
	if typeof(package.get("mode_descriptor")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_5_A_MODE_DESCRIPTOR")
	checked = ModeDescriptor.validate(package["mode_descriptor"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(package.get("physical_bundle")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_5_A_PHYSICAL_BUNDLE")
	checked = PhysicalBridge.validate(
		package["physical_bundle"],
		package["full_model"],
		package["rom_descriptor"],
		package["reduction_binding"],
		package["certification"]
	)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(package.get("mode_contract")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_5_A_MODE_CONTRACT")
	checked = ExecutableMode.validate(
		package["mode_contract"],
		package["mode_descriptor"],
		package["physical_bundle"]
	)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(package.get("p0_cache_entry")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_5_A_P0_CACHE_ENTRY")
	checked = P0Cache.validate_against(
		package["p0_cache_entry"],
		package["mode_descriptor"]["mode_signature"],
		package["mode_descriptor"]
	)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(package.get("executable_cache_entry")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_5_A_EXECUTABLE_CACHE_ENTRY")
	checked = ExecutableCache.validate_against(
		package["executable_cache_entry"],
		package["p0_cache_entry"],
		package["mode_contract"],
		package["mode_descriptor"],
		package["physical_bundle"]
	)
	if not bool(checked.get("success", false)):
		return checked
	if String(package["mode_contract"]["rom_descriptor_hash"]) != String(package["rom_descriptor"]["descriptor_hash"]):
		return Utils.failure("B0_5_A_PACKAGE_ROM_DESCRIPTOR_MISMATCH")
	if String(package["mode_contract"]["runtime_certification_hash"]) != String(package["certification"]["certification_hash"]):
		return Utils.failure("B0_5_A_PACKAGE_CERTIFICATION_MISMATCH")
	if not Utils.is_lower_hex_64(package.get("package_hash")):
		return Utils.failure("INVALID_B0_5_A_PACKAGE_HASH")
	if String(package["package_hash"]) != Utils.canonical_hash(_package_identity(package)):
		return Utils.failure("B0_5_A_PACKAGE_HASH_MISMATCH")
	return Utils.validate_checksum(package)

static func register_mode(registry: Dictionary, package: Dictionary) -> Dictionary:
	var checked := validate_package(package)
	if not bool(checked.get("success", false)):
		return checked
	var key := String(package["mode_descriptor"]["cache_key"])
	var next := registry.duplicate(true)
	if next.has(key):
		var existing = next[key]
		if typeof(existing) != TYPE_DICTIONARY:
			return Utils.failure("B0_5_A_REGISTRY_ENTRY_INVALID")
		if String(existing.get("package_hash", "")) != String(package["package_hash"]):
			return Utils.failure("B0_5_A_CACHE_KEY_COLLISION")
		return Utils.success({"registry": next, "changed": false, "cache_key": key})
	next[key] = package.duplicate(true)
	return Utils.success({"registry": next, "changed": true, "cache_key": key})

static func resolve_mode(blueprint: Dictionary, registry: Dictionary) -> Dictionary:
	var preview := preview_mode(blueprint)
	if not bool(preview.get("success", false)):
		return preview
	var descriptor: Dictionary = preview["details"]["mode_descriptor"]
	var key := String(descriptor["cache_key"])
	if registry.has(key):
		var package = registry[key]
		if typeof(package) != TYPE_DICTIONARY:
			return Utils.success({
				"action": "FALLBACK",
				"fallback": "FULL",
				"reason": "CACHE_ENTRY_INVALID",
				"registry": registry.duplicate(true),
			})
		var checked := validate_package(package)
		if not bool(checked.get("success", false)):
			return Utils.success({
				"action": "FALLBACK",
				"fallback": "FULL",
				"reason": String(checked.get("error_code", "CACHE_ENTRY_INVALID")),
				"registry": registry.duplicate(true),
			})
		if String(package["mode_descriptor"]["checksum"]) != String(descriptor["checksum"]):
			return Utils.success({
				"action": "FALLBACK",
				"fallback": "FULL",
				"reason": "EXACT_MODE_DESCRIPTOR_MISMATCH",
				"registry": registry.duplicate(true),
			})
		if String(package["executable_cache_entry"]["validity_state"]) != "VALID":
			return Utils.success({
				"action": "FALLBACK",
				"fallback": "FULL",
				"reason": String(package["executable_cache_entry"]["invalidation_reason"]),
				"registry": registry.duplicate(true),
			})
		return Utils.success({
			"action": "EXACT_CACHE_HIT",
			"package": package.duplicate(true),
			"registry": registry.duplicate(true),
			"cache_key": key,
		})
	var compiled := compile_mode(blueprint)
	if not bool(compiled.get("success", false)):
		return Utils.success({
			"action": "FALLBACK",
			"fallback": "NO_SAFE_BAKE",
			"reason": String(compiled.get("error_code", "MODE_COMPILE_FAILED")),
			"registry": registry.duplicate(true),
		})
	var package: Dictionary = compiled["details"]["package"]
	var registered := register_mode(registry, package)
	if not bool(registered.get("success", false)):
		return registered
	return Utils.success({
		"action": "LAZY_COMPILED",
		"package": package,
		"registry": registered["details"]["registry"],
		"cache_key": key,
	})

static func start(package: Dictionary) -> Dictionary:
	var checked := validate_package(package)
	if not bool(checked.get("success", false)):
		return checked
	var started := PhysicalBridge.start_execution(
		package["physical_bundle"],
		package["full_model"],
		package["rom_descriptor"],
		package["reduction_binding"],
		package["certification"]
	)
	if not bool(started.get("success", false)):
		return started
	var session: Dictionary = {
		"schema": SESSION_SCHEMA,
		"current_cache_key": String(package["mode_descriptor"]["cache_key"]),
		"current_mode_hash": String(package["mode_contract"]["mode_hash"]),
		"current_mode_id": String(package["mode_contract"]["mode_id"]),
		"physical_session": started["details"]["session"],
		"event_ledger": [],
		"transition_count": 0,
		"last_event_hash": "",
		"checksum": "",
	}
	session["checksum"] = Utils.compute_checksum(session)
	checked = validate_session(session, package)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"session": session, "status": "B0_5_A_HYBRID_ACTIVE"})

static func validate_session(session: Dictionary, current_package: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(session, SESSION_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if session.get("schema") != SESSION_SCHEMA:
		return Utils.failure("UNSUPPORTED_B0_5_A_SESSION_SCHEMA")
	checked = validate_package(current_package)
	if not bool(checked.get("success", false)):
		return checked
	if String(session["current_cache_key"]) != String(current_package["mode_descriptor"]["cache_key"]):
		return Utils.failure("B0_5_A_SESSION_CACHE_KEY_MISMATCH")
	if String(session["current_mode_hash"]) != String(current_package["mode_contract"]["mode_hash"]):
		return Utils.failure("B0_5_A_SESSION_MODE_HASH_MISMATCH")
	if String(session["current_mode_id"]) != String(current_package["mode_contract"]["mode_id"]):
		return Utils.failure("B0_5_A_SESSION_MODE_ID_MISMATCH")
	if typeof(session.get("physical_session")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_B0_5_A_PHYSICAL_SESSION")
	checked = ExecutionRuntime.validate(
		session["physical_session"],
		current_package["physical_bundle"]["execution_artifact"]
	)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(session.get("event_ledger")) != TYPE_ARRAY:
		return Utils.failure("INVALID_B0_5_A_EVENT_LEDGER")
	var seen := {}
	for index in range(session["event_ledger"].size()):
		var raw = session["event_ledger"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_B0_5_A_EVENT_LEDGER_ENTRY", {"index": index})
		checked = Utils.validate_exact_fields(raw, EVENT_LEDGER_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var event_id := String(raw.get("event_id", ""))
		if event_id.is_empty() or seen.has(event_id):
			return Utils.failure("DUPLICATE_B0_5_A_EVENT_LEDGER_ID")
		seen[event_id] = true
		for field in ["event_hash", "transition_contract_hash"]:
			if not Utils.is_lower_hex_64(raw.get(field)):
				return Utils.failure("INVALID_B0_5_A_EVENT_LEDGER_HASH", {"field": field})
	if not Utils.is_json_integer(session.get("transition_count")) or int(session["transition_count"]) < 0:
		return Utils.failure("INVALID_B0_5_A_TRANSITION_COUNT")
	if int(session["transition_count"]) != session["event_ledger"].size():
		return Utils.failure("B0_5_A_TRANSITION_LEDGER_COUNT_MISMATCH")
	if String(session.get("last_event_hash", "")) != "":
		if not Utils.is_lower_hex_64(session["last_event_hash"]):
			return Utils.failure("INVALID_B0_5_A_LAST_EVENT_HASH")
		if session["event_ledger"].is_empty() or String(session["event_ledger"][-1]["event_hash"]) != String(session["last_event_hash"]):
			return Utils.failure("B0_5_A_LAST_EVENT_HASH_MISMATCH")
	return Utils.validate_checksum(session)

static func flow_step(
	session: Dictionary,
	current_package: Dictionary,
	port_flows: Dictionary,
	delta_s: float,
	invalidations: Array = [],
	local_unbake_available: bool = false
) -> Dictionary:
	var checked := validate_session(session, current_package)
	if not bool(checked.get("success", false)):
		return checked
	var source_checksum := String(current_package["full_model"]["source_binding"]["checksum"])
	var stepped := PhysicalBridge.governed_step(
		current_package["physical_bundle"],
		session["physical_session"],
		current_package["full_model"],
		current_package["rom_descriptor"],
		current_package["reduction_binding"],
		current_package["certification"],
		port_flows,
		delta_s,
		source_checksum,
		invalidations,
		local_unbake_available
	)
	if not bool(stepped.get("success", false)):
		return Utils.failure("B0_5_A_MODE_EXECUTION_FAILED", {
			"cause": stepped.get("error_code", "B0_4_MODE_EXECUTION_FAILED"),
			"b0_4_result": stepped,
			"fallback": "REFINE_OR_FULL",
			"session": session,
		})
	var next := session.duplicate(true)
	next["physical_session"] = stepped["details"]["session"]
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate_session(next, current_package)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": next,
		"boundary": stepped["details"].get("boundary", []),
		"energy": stepped["details"].get("energy", {}),
		"runtime_certificate": stepped["details"].get("runtime_certificate", {}),
		"physical_bake_gate": stepped["details"].get("physical_bake_gate", {}),
		"status": "B0_5_A_FLOW_ACCEPTED",
	})

static func consume_fabric_event(
	session: Dictionary,
	current_package: Dictionary,
	p0_transition: Dictionary,
	fabric_event: Dictionary,
	target_blueprint: Dictionary,
	registry: Dictionary
) -> Dictionary:
	var checked := validate_session(session, current_package)
	if not bool(checked.get("success", false)):
		return checked
	checked = P0Transition.validate(p0_transition)
	if not bool(checked.get("success", false)):
		return checked
	var event_id := String(fabric_event.get("event_id", ""))
	if event_id.is_empty():
		return Utils.failure("B0_5_A_FABRIC_EVENT_ID_MISSING")
	for ledger_entry in session["event_ledger"]:
		if String(ledger_entry["event_id"]) == event_id:
			return Utils.failure("B0_5_A_DUPLICATE_FABRIC_PHYSICAL_EVENT", {
				"event_id": event_id,
				"session": session,
			})
	if String(p0_transition["from_mode_hash"]) != String(session["current_mode_hash"]):
		return Utils.failure("B0_5_A_TRANSITION_FROM_MODE_MISMATCH")

	var resolved := resolve_mode(target_blueprint, registry)
	if not bool(resolved.get("success", false)):
		return resolved
	var action := String(resolved["details"]["action"])
	if action == "FALLBACK":
		return Utils.failure("B0_5_A_TARGET_MODE_UNAVAILABLE", {
			"fallback": resolved["details"].get("fallback", "FULL"),
			"reason": resolved["details"].get("reason", "MODE_UNAVAILABLE"),
			"registry": resolved["details"]["registry"],
			"session": session,
		})
	var target_package: Dictionary = resolved["details"]["package"]
	if String(p0_transition["to_mode_hash"]) != String(target_package["mode_contract"]["mode_hash"]):
		return Utils.failure("B0_5_A_TRANSITION_TO_MODE_MISMATCH")

	var executable_transition := ExecutableTransition.create(
		p0_transition,
		current_package["mode_contract"],
		target_package["mode_contract"]
	)
	if executable_transition.is_empty():
		return Utils.failure("B0_5_A_EXECUTABLE_TRANSITION_CREATE_FAILED")
	checked = _validate_fabric_event(
		fabric_event,
		p0_transition,
		String(current_package["mode_contract"]["mode_id"]),
		String(target_package["mode_contract"]["mode_id"]),
		float(session["physical_session"]["elapsed_s"])
	)
	if not bool(checked.get("success", false)):
		return checked

	var handoff := ExecutionRuntime.full_handoff(
		session["physical_session"],
		current_package["physical_bundle"]["execution_artifact"],
		current_package["rom_descriptor"]
	)
	if not bool(handoff.get("success", false)):
		return Utils.failure("B0_5_A_RECONSTRUCTION_HANDOFF_FAILED", {
			"cause": handoff.get("error_code", "FULL_HANDOFF_FAILED"),
			"session": session,
		})
	var h: Dictionary = handoff["details"]
	var started := ExecutionRuntime.start_from_full_handoff(
		target_package["physical_bundle"]["execution_artifact"],
		target_package["full_model"],
		target_package["rom_descriptor"],
		target_package["reduction_binding"],
		target_package["certification"],
		h["values"],
		float(h["time_s"]),
		int(h["step_index"])
	)
	if not bool(started.get("success", false)):
		return Utils.failure("B0_5_A_TARGET_STATE_MAPPING_FAILED", {
			"cause": started.get("error_code", "TARGET_PROJECTION_FAILED"),
			"fallback": "FULL",
			"session": session,
		})

	var event_hash := Utils.canonical_hash(fabric_event)
	var next := session.duplicate(true)
	next["current_cache_key"] = String(target_package["mode_descriptor"]["cache_key"])
	next["current_mode_hash"] = String(target_package["mode_contract"]["mode_hash"])
	next["current_mode_id"] = String(target_package["mode_contract"]["mode_id"])
	next["physical_session"] = started["details"]["session"]
	next["event_ledger"].append({
		"event_id": event_id,
		"event_hash": event_hash,
		"transition_contract_hash": String(executable_transition["transition_contract_hash"]),
	})
	next["transition_count"] = int(next["transition_count"]) + 1
	next["last_event_hash"] = event_hash
	next["checksum"] = Utils.compute_checksum(next)
	checked = validate_session(next, target_package)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"session": next,
		"target_package": target_package,
		"registry": resolved["details"]["registry"],
		"cache_action": action,
		"event_id": event_id,
		"event_hash": event_hash,
		"transition_contract": executable_transition,
		"projection_error": started["details"]["projection_error"],
		"projection_error_c_norm": started["details"]["projection_error_c_norm"],
		"status": "B0_5_A_JUMP_HANDOFF_ACCEPTED",
	})

static func unknown_mode_fallback(mode_signature: Dictionary, registry: Dictionary, fallback: String = "FULL") -> Dictionary:
	var p0_entries: Array = []
	for key in registry.keys():
		var package = registry[key]
		if typeof(package) == TYPE_DICTIONARY and typeof(package.get("p0_cache_entry")) == TYPE_DICTIONARY:
			p0_entries.append(package["p0_cache_entry"])
	return P0Preflight.unknown_mode_fallback(mode_signature, p0_entries, fallback)

static func invalidate_cached_mode(registry: Dictionary, cache_key: String, reason: String) -> Dictionary:
	if not registry.has(cache_key):
		return Utils.failure("B0_5_A_CACHE_KEY_NOT_FOUND")
	var raw = registry[cache_key]
	if typeof(raw) != TYPE_DICTIONARY:
		return Utils.failure("B0_5_A_REGISTRY_ENTRY_INVALID")
	var package: Dictionary = raw.duplicate(true)
	var stale := ExecutableCache.invalidate(package["executable_cache_entry"], reason)
	if stale.is_empty():
		return Utils.failure("B0_5_A_EXECUTABLE_CACHE_INVALIDATION_FAILED")
	package["p0_cache_entry"] = stale["p0_cache_entry"]
	package["executable_cache_entry"] = stale
	package["package_hash"] = Utils.canonical_hash(_package_identity(package))
	package["checksum"] = Utils.compute_checksum(package)
	var checked := validate_package(package)
	if not bool(checked.get("success", false)):
		return checked
	var next := registry.duplicate(true)
	next[cache_key] = package
	return Utils.success({"registry": next, "package": package, "reason": reason})

static func _validate_blueprint(blueprint: Dictionary) -> Dictionary:
	for field in [
		"mode_id", "mode_descriptor_id", "active_relation_ids", "complementarity_active_ids",
		"dependency_versions", "physical_bundle", "full_model", "rom_descriptor",
		"reduction_binding", "certification",
	]:
		if not blueprint.has(field):
			return Utils.failure("B0_5_A_BLUEPRINT_FIELD_MISSING", {"field": field})
	if not Utils.is_canonical_id(blueprint.get("mode_id"), 2):
		return Utils.failure("INVALID_B0_5_A_BLUEPRINT_MODE_ID")
	if not Utils.is_canonical_id(blueprint.get("mode_descriptor_id"), 2):
		return Utils.failure("INVALID_B0_5_A_BLUEPRINT_DESCRIPTOR_ID")
	for field in ["active_relation_ids", "complementarity_active_ids", "dependency_versions"]:
		if typeof(blueprint.get(field)) != TYPE_ARRAY:
			return Utils.failure("INVALID_B0_5_A_BLUEPRINT_ARRAY", {"field": field})
	var checked := PhysicalBridge.validate(
		blueprint["physical_bundle"],
		blueprint["full_model"],
		blueprint["rom_descriptor"],
		blueprint["reduction_binding"],
		blueprint["certification"]
	)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success()

static func _validate_fabric_event(
	fabric_event: Dictionary,
	p0_transition: Dictionary,
	from_mode_id: String,
	to_mode_id: String,
	expected_time_s: float
) -> Dictionary:
	for field in ["event_id", "time", "transitions"]:
		if not fabric_event.has(field):
			return Utils.failure("B0_5_A_FABRIC_EVENT_FIELD_MISSING", {"field": field})
	if not Utils.is_finite_number(fabric_event["time"]):
		return Utils.failure("B0_5_A_FABRIC_EVENT_TIME_INVALID")
	if absf(float(fabric_event["time"]) - expected_time_s) > EVENT_TIME_TOLERANCE:
		return Utils.failure("B0_5_A_FABRIC_EVENT_TIME_MISMATCH", {
			"fabric_time": fabric_event["time"],
			"rom_time": expected_time_s,
		})
	if typeof(fabric_event["transitions"]) != TYPE_ARRAY:
		return Utils.failure("B0_5_A_FABRIC_EVENT_TRANSITIONS_INVALID")
	var matches: Array = []
	for raw in fabric_event["transitions"]:
		if typeof(raw) == TYPE_DICTIONARY and String(raw.get("transition_id", "")) == String(p0_transition["transition_id"]):
			matches.append(raw)
	if matches.size() != 1:
		return Utils.failure("B0_5_A_FABRIC_EVENT_TRANSITION_OWNERSHIP_INVALID", {"matches": matches.size()})
	var record: Dictionary = matches[0]
	if String(record.get("pre_mode", "")) != from_mode_id:
		return Utils.failure("B0_5_A_FABRIC_EVENT_PRE_MODE_MISMATCH")
	if String(record.get("post_mode", "")) != to_mode_id:
		return Utils.failure("B0_5_A_FABRIC_EVENT_POST_MODE_MISMATCH")
	return Utils.success()

static func _package_identity(package: Dictionary) -> Dictionary:
	return {
		"mode_contract_hash": package.get("mode_contract", {}).get("mode_contract_hash", ""),
		"mode_descriptor_checksum": package.get("mode_descriptor", {}).get("checksum", ""),
		"p0_cache_checksum": package.get("p0_cache_entry", {}).get("checksum", ""),
		"executable_cache_checksum": package.get("executable_cache_entry", {}).get("checksum", ""),
		"physical_bundle_hash": package.get("physical_bundle", {}).get("bundle_hash", ""),
		"full_model_hash": package.get("full_model", {}).get("model_hash", ""),
		"rom_descriptor_hash": package.get("rom_descriptor", {}).get("descriptor_hash", ""),
		"reduction_binding_hash": package.get("reduction_binding", {}).get("binding_hash", ""),
		"certification_hash": package.get("certification", {}).get("certification_hash", ""),
	}
