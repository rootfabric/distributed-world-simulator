extends RefCounted
## Prepared logic lookup runtime. State is explicit input/output; runtime owns no evolving canonical truth.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/logic_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/logic_lookup_descriptor_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _interface_hash := ""
var _input_bits := 0
var _output_bits := 0
var _state_bits := 0
var _input_mask := 0
var _output_mask := 0
var _state_mask := 0
var _initial_state_word := 0
var _table := PackedInt32Array()

func prepare(capsule: Dictionary, artifact: Dictionary, descriptor: Dictionary, live: Dictionary) -> Dictionary:
	_ready = false
	var checked := Capsule.validate(capsule)
	if not checked.success:
		return checked
	checked = Artifact.verify_descriptor(artifact, descriptor)
	if not checked.success:
		return checked
	checked = Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if String(capsule.executable_artifact_kind) != "LOGIC_LOOKUP":
		return U.failure("LOGIC_RUNTIME_CAPSULE_KIND_MISMATCH")
	if String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("LOGIC_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("LOGIC_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if String(capsule.source_graph_hash) != String(artifact.graph_hash):
		return U.failure("LOGIC_RUNTIME_CAPSULE_GRAPH_MISMATCH")
	if String(capsule.interface_contract_hash) != String(artifact.interface_contract.interface_hash):
		return U.failure("LOGIC_RUNTIME_CAPSULE_INTERFACE_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("LOGIC_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
	checked = _full_live_gate(artifact, live)
	if not checked.success:
		return checked
	_capsule_id = String(capsule.capsule_id)
	_frontier_hash = String(artifact.canonical_source_frontier.frontier_hash)
	_authority_checksum = String(artifact.authority_envelope.checksum)
	_dependency_hash = String(artifact.dependency_set.dependency_hash)
	_graph_hash = String(artifact.graph_hash)
	_interface_hash = String(artifact.interface_contract.interface_hash)
	_input_bits = int(descriptor.input_bit_count)
	_output_bits = int(descriptor.output_bit_count)
	_state_bits = int(descriptor.state_bit_count)
	_input_mask = (1 << _input_bits) - 1
	_output_mask = (1 << _output_bits) - 1
	_state_mask = (1 << _state_bits) - 1 if _state_bits > 0 else 0
	_initial_state_word = int(descriptor.initial_state_word)
	_table.resize(descriptor.table.size())
	for index in range(descriptor.table.size()):
		_table[index] = int(descriptor.table[index])
	_ready = true
	return U.success({
		"capsule_id": _capsule_id,
		"initial_state_word": _initial_state_word,
		"lookup_entries": _table.size(),
		"lookup_bytes": _table.size() * 4,
	})

func execute(live: Dictionary, input_word: int, state_word: int) -> Dictionary:
	if not _ready:
		return U.failure("LOGIC_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if input_word < 0 or input_word > _input_mask:
		return U.failure("LOGIC_RUNTIME_INPUT_OUT_OF_RANGE")
	if _state_bits == 0:
		if state_word != 0:
			return U.failure("LOGIC_RUNTIME_STATE_OUT_OF_RANGE")
	elif state_word < 0 or state_word > _state_mask:
		return U.failure("LOGIC_RUNTIME_STATE_OUT_OF_RANGE")
	var address := input_word | (state_word << _input_bits)
	var packed := int(_table[address])
	var output_word := packed & _output_mask
	var next_state_word := (packed >> _output_bits) & _state_mask if _state_bits > 0 else 0
	return U.success({
		"capsule_id": _capsule_id,
		"output_word": output_word,
		"next_state_word": next_state_word,
		"event_order": ["OUTPUT_EVALUATED", "REGISTER_COMMIT"] if _state_bits > 0 else ["OUTPUT_EVALUATED"],
		"runtime_source_component_traversals": 0,
		"compiled_operations": 3,
	})

func initial_state_word() -> int:
	return _initial_state_word

func invalidate() -> void:
	_ready = false

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("LOGIC_RUNTIME_NOT_READY_STATE")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("LOGIC_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("LOGIC_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("LOGIC_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("LOGIC_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("LOGIC_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("LOGIC_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("LOGIC_RUNTIME_NOT_READY_STATE")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("LOGIC_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("LOGIC_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("LOGIC_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("LOGIC_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("LOGIC_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("LOGIC_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
