extends RefCounted
## T13: one immutable compiled T12 model, many caller-owned instance bindings/states.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const Ship = preload("res://scripts/research/fabric_bake0/r5_t12_ship_runtime_v1.gd")

const BINDING_SCHEMA := "planet_simulator.fabric_t13_instance_binding.v1"
const STATE_SCHEMA := "planet_simulator.fabric_t13_instance_state.v1"
const MODEL_SCHEMA := "planet_simulator.fabric_t13_shared_compiled_model.v1"

var runtime = Ship.new()
var compiled_bundle: Dictionary = {}
var live: Dictionary = {}
var compiled_model_checksum := ""
var compiled_model_hash := ""
var state_signature_hash := ""
var prepare_count := 0
var ready := false

func prepare(bundle: Dictionary, trusted_capsule_checksum: String) -> Dictionary:
	if ready:
		return U.failure("T13_MODEL_ALREADY_PREPARED")
	var checked := C.verify(bundle, trusted_capsule_checksum)
	if not checked.success:
		return checked
	if String(bundle.capsule.executable_kind) != "T12_SHIP":
		return U.failure("T13_MODEL_KIND_INVALID")
	var prepared: Dictionary = runtime.prepare(bundle, trusted_capsule_checksum)
	if not prepared.success:
		return prepared
	compiled_bundle = bundle
	live = C.live_tree(bundle)
	compiled_model_checksum = trusted_capsule_checksum
	compiled_model_hash = U.canonical_hash(bundle)
	state_signature_hash = runtime.state_signature()
	prepare_count += 1
	ready = true
	return U.success({
		"schema": MODEL_SCHEMA,
		"compiled_model_checksum": compiled_model_checksum,
		"compiled_model_hash": compiled_model_hash,
		"state_signature": state_signature_hash,
		"prepare_count": prepare_count,
		"source_component_count": int(bundle.capsule.source_component_count),
		"state_scalars_per_instance": int(prepared.details.state_scalars),
	})

func model_identity() -> Dictionary:
	return {
		"schema": MODEL_SCHEMA,
		"compiled_model_checksum": compiled_model_checksum,
		"compiled_model_hash": compiled_model_hash,
		"state_signature": state_signature_hash,
		"prepare_count": prepare_count,
	}

func model_intact() -> bool:
	return ready and prepare_count == 1 and not compiled_bundle.is_empty() and U.canonical_hash(compiled_bundle) == compiled_model_hash

func create_binding(instance_id: String, world_slot: String) -> Dictionary:
	if not model_intact():
		return U.failure("T13_COMPILED_MODEL_MUTATED")
	if instance_id.is_empty() or instance_id.length() > 128 or world_slot.is_empty() or world_slot.length() > 128:
		return U.failure("T13_BINDING_ID_INVALID")
	var binding := {
		"schema": BINDING_SCHEMA,
		"instance_id": instance_id,
		"world_slot": world_slot,
		"compiled_model_checksum": compiled_model_checksum,
		"state_signature": state_signature_hash,
		"checksum": "",
	}
	binding.checksum = U.compute_checksum(binding)
	var checked := validate_binding(binding)
	return U.success(binding) if checked.success else checked

func validate_binding(binding: Dictionary) -> Dictionary:
	if not model_intact():
		return U.failure("T13_COMPILED_MODEL_MUTATED")
	if binding.size() != 6 or binding.get("schema") != BINDING_SCHEMA:
		return U.failure("T13_BINDING_SHAPE_INVALID")
	if String(binding.get("instance_id", "")).is_empty() or String(binding.get("world_slot", "")).is_empty():
		return U.failure("T13_BINDING_ID_INVALID")
	if binding.get("compiled_model_checksum") != compiled_model_checksum or binding.get("state_signature") != state_signature_hash:
		return U.failure("T13_BINDING_MODEL_MISMATCH")
	var checked := U.validate_checksum(binding)
	if not checked.success:
		return U.failure("T13_BINDING_CHECKSUM_INVALID")
	return U.success()

func initial_state(binding: Dictionary, soc: float = 0.8, temperature_k: float = 300.0) -> Dictionary:
	var checked := validate_binding(binding)
	if not checked.success:
		return {}
	var physical := runtime.initial_state(soc, temperature_k)
	if physical.is_empty():
		return {}
	return {
		"schema": STATE_SCHEMA,
		"binding_checksum": binding.checksum,
		"compiled_model_checksum": compiled_model_checksum,
		"state_signature": state_signature_hash,
		"state_revision": 0,
		"damage_revision": 0,
		"disabled": false,
		"physical": physical,
	}

func state_valid(binding: Dictionary, state: Dictionary) -> bool:
	if not validate_binding(binding).success:
		return false
	if state.size() != 8 or state.get("schema") != STATE_SCHEMA:
		return false
	if state.get("binding_checksum") != binding.checksum or state.get("compiled_model_checksum") != compiled_model_checksum:
		return false
	if state.get("state_signature") != state_signature_hash:
		return false
	if typeof(state.get("state_revision")) != TYPE_INT or int(state.state_revision) < 0:
		return false
	if typeof(state.get("damage_revision")) != TYPE_INT or int(state.damage_revision) < 0:
		return false
	if typeof(state.get("disabled")) != TYPE_BOOL or typeof(state.get("physical")) != TYPE_DICTIONARY:
		return false
	return runtime.state_valid(state.physical)

func apply_damage(binding: Dictionary, state: Dictionary, disabled: bool = true) -> Dictionary:
	if not state_valid(binding, state):
		return U.failure("T13_INSTANCE_STATE_INVALID")
	var next: Dictionary = state.duplicate(true)
	next.disabled = disabled
	next.damage_revision = int(next.damage_revision) + 1
	next.state_revision = int(next.state_revision) + 1
	return U.success({"next_state": next, "recompile_events": 0, "prepare_count": prepare_count})

func _masked_commands(state: Dictionary, commands: Dictionary) -> Dictionary:
	var masked: Dictionary = commands.duplicate(true)
	if not bool(state.disabled):
		return masked
	for slot in masked:
		if typeof(masked[slot]) != TYPE_DICTIONARY:
			continue
		if not state.physical.bank.has(slot):
			continue
		masked[slot].laser_current_a = 0.0
		masked[slot].target_position_rad = float(state.physical.bank[slot].servo.output_position_rad)
		masked[slot].target_velocity_rad_s = 0.0
		masked[slot].external_torque_nm = 0.0
	return masked

func execute(binding: Dictionary, state: Dictionary, commands: Dictionary, ambient_k: float, dt: float) -> Dictionary:
	if not model_intact():
		return U.failure("T13_COMPILED_MODEL_MUTATED")
	if not state_valid(binding, state):
		return U.failure("T13_INSTANCE_STATE_INVALID")
	var before := state.duplicate(true)
	var effective := _masked_commands(state, commands)
	var step: Dictionary = runtime.execute(live, state.physical, effective, ambient_k, dt)
	if not step.success:
		return step
	if state != before:
		return U.failure("T13_CALLER_STATE_MUTATED")
	var next: Dictionary = state.duplicate(true)
	next.physical = step.details.next_state
	next.state_revision = int(next.state_revision) + 1
	return U.success({
		"next_state": next,
		"physical": step.details,
		"compiled_model_checksum": compiled_model_checksum,
		"compiled_model_hash": compiled_model_hash,
		"binding_checksum": binding.checksum,
		"damage_masked": bool(state.disabled),
		"prepare_count": prepare_count,
		"recompile_events": 0,
	})

func snapshot_instance(binding: Dictionary, state: Dictionary) -> Dictionary:
	if not state_valid(binding, state):
		return U.failure("T13_INSTANCE_STATE_INVALID")
	var physical := runtime.snapshot(state.physical)
	if not physical.success:
		return physical
	var envelope := {
		"schema": "t13.instance.snapshot.v1",
		"binding_checksum": binding.checksum,
		"compiled_model_checksum": compiled_model_checksum,
		"state_revision": int(state.state_revision),
		"damage_revision": int(state.damage_revision),
		"disabled": bool(state.disabled),
		"physical_text": physical.details.text,
		"physical_sha256": physical.details.sha256,
	}
	var text := JSON.stringify(envelope, "", true)
	return U.success({"text": text, "sha256": text.sha256_text()})
