extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")
const Selector = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_selector_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const SCHEMA := "planet_simulator.fabric_bake_adaptive_fidelity_controller.v1"
const DEFAULT_CONFIG := {"safe_window": 3, "cooldown_ticks": 2}
const CONFIG_FIELDS: Array[String] = ["safe_window", "cooldown_ticks"]
const FIELDS: Array[String] = ["schema", "source_revision", "current_fidelity",
	"candidate_target", "safe_streak", "transition_epoch", "cooldown_remaining",
	"last_transition_reason", "last_evaluation_tick", "last_input_hash",
	"transition_hash", "transition_count", "configuration", "checksum"]

static func validate_config(config: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(config, CONFIG_FIELDS)
	if not checked.get("success", false):
		return checked
	for field in CONFIG_FIELDS:
		if not Utils.is_json_integer(config[field]) or int(config[field]) < (1 if field == "safe_window" else 0):
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_HYSTERESIS_CONFIG")
	return Utils.success()

static func create(source: Dictionary, current: String = "FULL_FABRIC", config: Dictionary = DEFAULT_CONFIG, base_tick: int = 0) -> Dictionary:
	var checked := Utils.validate_source_revision(source)
	if not checked.get("success", false):
		return checked
	checked = validate_config(config)
	if not checked.get("success", false):
		return checked
	if not Envelope.LEVELS.has(current) or not Utils.is_json_integer(base_tick) or base_tick < 0:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_INITIAL_STATE")
	var state := {"schema": SCHEMA, "source_revision": source.duplicate(true),
		"current_fidelity": current, "candidate_target": "", "safe_streak": 0,
		"transition_epoch": base_tick, "cooldown_remaining": 0, "last_transition_reason": "INITIAL",
		"last_evaluation_tick": base_tick, "last_input_hash": "", "transition_hash": Utils.canonical_hash([]),
		"transition_count": 0, "configuration": config.duplicate(true)}
	return Utils.success({"state": seal(state)})

static func validate_state(state: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(state, FIELDS)
	if not checked.get("success", false):
		return checked
	if typeof(state.get("schema")) != TYPE_STRING or state["schema"] != SCHEMA:
		return Utils.failure("UNSUPPORTED_ADAPTIVE_FIDELITY_CONTROLLER_SCHEMA")
	if typeof(state.get("source_revision")) != TYPE_DICTIONARY or typeof(state.get("configuration")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CONTROLLER_BINDING")
	checked = Utils.validate_source_revision(state["source_revision"])
	if not checked.get("success", false):
		return checked
	checked = validate_config(state["configuration"])
	if not checked.get("success", false):
		return checked
	for field in ["current_fidelity", "candidate_target", "last_transition_reason", "last_input_hash", "transition_hash"]:
		if typeof(state.get(field)) != TYPE_STRING:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CONTROLLER_FIELD", {"field": field})
	var current_index := Envelope.LEVELS.find(state["current_fidelity"])
	if current_index < 0 or not ["INITIAL", "UNSAFE_PROMOTION", "POLICY_PROMOTION", "STABLE_DEMOTION", "SOURCE_REBIND"].has(state["last_transition_reason"]):
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CONTROLLER_MODE")
	for field in ["safe_streak", "transition_epoch", "cooldown_remaining", "last_evaluation_tick", "transition_count"]:
		if not Utils.is_json_integer(state.get(field)) or int(state[field]) < 0:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CONTROLLER_COUNTER", {"field": field})
	if state["transition_epoch"] > state["last_evaluation_tick"] or state["transition_count"] > state["transition_epoch"]:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_TRANSITION_EPOCH")
	if state["safe_streak"] >= state["configuration"]["safe_window"] or state["cooldown_remaining"] > state["configuration"]["cooldown_ticks"]:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_HYSTERESIS_COUNTER")
	if state["candidate_target"].is_empty():
		if state["safe_streak"] != 0:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_SAFE_STREAK")
	elif current_index == 4 or state["candidate_target"] != Envelope.LEVELS[current_index + 1] or state["safe_streak"] == 0:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_DEMOTION_CANDIDATE")
	if not Utils.is_lower_hex_64(state["transition_hash"]) or (not state["last_input_hash"].is_empty() and not Utils.is_lower_hex_64(state["last_input_hash"])):
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CONTROLLER_HASH")
	return Utils.validate_checksum(state)

# Pure prepare/commit value: caller publishes the returned state atomically into
# its ONE execution slot. No artifact/ownership side effects occur while preparing.
static func evaluate(state: Dictionary, envelope: Dictionary, decision: Dictionary, tick, source: Dictionary = {}) -> Dictionary:
	var checked := validate_state(state)
	if not checked.get("success", false):
		return checked
	checked = Selector.validate_decision(decision, envelope)
	if not checked.get("success", false):
		return checked
	if not Utils.is_json_integer(tick) or int(tick) < 1:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_EVALUATION_TICK")
	var live_source: Dictionary = state["source_revision"] if source.is_empty() else source
	checked = Utils.validate_source_revision(live_source)
	if not checked.get("success", false):
		return checked
	var old_source: Dictionary = state["source_revision"]
	if live_source["source_domain"] != old_source["source_domain"] or live_source["source_id"] != old_source["source_id"]:
		return Utils.failure("ADAPTIVE_FIDELITY_FOREIGN_SOURCE")
	if live_source["source_revision"] < old_source["source_revision"] or live_source["authority_epoch"] < old_source["authority_epoch"]:
		return Utils.failure("ADAPTIVE_FIDELITY_SOURCE_REGRESSION")
	var fingerprint := Utils.canonical_hash({"envelope": envelope["checksum"],
		"decision": decision["checksum"], "source": live_source["checksum"], "tick": tick})
	if tick == state["last_evaluation_tick"] and fingerprint == state["last_input_hash"]:
		return Utils.success({"state": state, "transition": {}, "applied": false, "blocked_demotion": false, "source_rebound": false})
	if tick <= state["last_evaluation_tick"]:
		return Utils.failure("ADAPTIVE_FIDELITY_TICK_REPLAY_CONFLICT")
	if envelope["current_fidelity"] != state["current_fidelity"]:
		return Utils.failure("ADAPTIVE_FIDELITY_CURRENT_MISMATCH")
	var next := state.duplicate(true)
	var current: String = state["current_fidelity"]
	var target: String = decision["target_fidelity"]
	var from_index := Envelope.LEVELS.find(current)
	var to_index := Envelope.LEVELS.find(target)
	var rebound: bool = live_source["checksum"] != old_source["checksum"]
	var reason := ""
	var blocked := false
	next["source_revision"] = live_source.duplicate(true)
	next["last_evaluation_tick"] = int(tick)
	next["last_input_hash"] = fingerprint
	next["cooldown_remaining"] = maxi(0, int(state["cooldown_remaining"]) - 1)
	if tick != int(state["last_evaluation_tick"]) + 1 or rebound:
		next["safe_streak"] = 0
		next["candidate_target"] = ""
	if rebound:
		target = "FULL_FABRIC"
		reason = "SOURCE_REBIND"
	elif not envelope["admissible_fidelities"].has(current):
		target = envelope["minimum_safe_fidelity"]
		reason = "UNSAFE_PROMOTION"
	elif to_index < from_index:
		reason = "POLICY_PROMOTION"
	elif to_index > from_index:
		var candidate := Envelope.LEVELS[from_index + 1]
		blocked = true
		target = current
		if int(state["cooldown_remaining"]) == 0:
			next["safe_streak"] = int(next["safe_streak"]) + 1 if next["candidate_target"] == candidate else 1
			next["candidate_target"] = candidate
			if int(next["safe_streak"]) >= int(state["configuration"]["safe_window"]):
				target = candidate
				reason = "STABLE_DEMOTION"
				blocked = false
		else:
			next["safe_streak"] = 0
			next["candidate_target"] = ""
	else:
		next["safe_streak"] = 0
		next["candidate_target"] = ""
	var transition := {}
	if target != current:
		if not envelope["admissible_fidelities"].has(target):
			return Utils.failure("UNSAFE_ADAPTIVE_FIDELITY_TRANSITION")
		transition = {"source_binding": live_source["checksum"], "transition_epoch": int(tick),
			"from": current, "to": target, "reason": reason}
		transition["transition_id"] = Utils.canonical_hash(transition)
		next["current_fidelity"] = target
		next["transition_count"] = int(state["transition_count"]) + 1
		next["transition_epoch"] = int(tick)
		next["last_transition_reason"] = reason
		next["transition_hash"] = Utils.canonical_hash({"previous": state["transition_hash"], "transition": transition})
		next["cooldown_remaining"] = state["configuration"]["cooldown_ticks"]
		next["safe_streak"] = 0
		next["candidate_target"] = ""
	next = seal(next)
	checked = validate_state(next)
	if not checked.get("success", false):
		return checked
	return Utils.success({"state": next, "transition": transition, "applied": true,
		"blocked_demotion": blocked, "source_rebound": rebound})

# Reuse the BRIDGE-2 authority contract, not a new source revision/ownership system.
# Dormancy parks HYBRID execution; its responsible owner is never discarded.
static func bind_ownership(state: Dictionary, authority: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not checked.get("success", false):
		return checked
	checked = Authority.validate_b0_safety(authority)
	if not checked.get("success", false):
		return checked
	var source: Dictionary = state["source_revision"]
	if authority["source_authority_frontier"].size() != 1 or Authority.authority_epoch_for(authority, source["source_domain"], source["source_id"]) != source["authority_epoch"]:
		return Utils.failure("ADAPTIVE_FIDELITY_AUTHORITY_BINDING_MISMATCH")
	var frontier := Frontier.create([source])
	var kind: String = state["current_fidelity"]
	if kind == "FULL_FABRIC":
		kind = "FULL"
	elif kind == "DORMANT":
		kind = "HYBRID_BAKE"
	var representation_id: String = source["source_id"] + "/physical"
	checked = Ownership.compile(frontier, authority, [{"representation_id": representation_id,
		"representation_kind": kind, "derived_only": true, "canonical_write_authorized": false,
		"source_frontier_hash": frontier["frontier_hash"], "authority_epoch_binding": authority["authority_epoch_binding"]}],
		[{"region_id": source["source_id"] + "/region", "representation_id": representation_id, "ownership_role": "ACTIVE_EXECUTION"}])
	if not checked.get("success", false):
		return checked
	return Utils.success({"contract": checked["details"]["contract"], "execution_enabled": state["current_fidelity"] != "DORMANT"})

static func seal(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	# JSON decoders produce integral floats. Keep the runtime DTO typed and
	# hash-equivalent without altering canonical revision semantics.
	for field in ["safe_streak", "transition_epoch", "cooldown_remaining", "last_evaluation_tick", "transition_count"]:
		if Utils.is_json_integer(result.get(field)):
			result[field] = int(result[field])
	if typeof(result.get("configuration")) == TYPE_DICTIONARY:
		for field in CONFIG_FIELDS:
			if Utils.is_json_integer(result["configuration"].get(field)):
				result["configuration"][field] = int(result["configuration"][field])
	if typeof(result.get("source_revision")) == TYPE_DICTIONARY:
		for field in ["authority_epoch", "source_revision"]:
			if Utils.is_json_integer(result["source_revision"].get(field)):
				result["source_revision"][field] = int(result["source_revision"][field])
	result["checksum"] = Utils.compute_checksum(result)
	return result
