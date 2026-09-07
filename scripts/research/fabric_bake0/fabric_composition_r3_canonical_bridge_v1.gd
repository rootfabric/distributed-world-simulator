extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_runtime_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const JOURNAL_SCHEMA := "planet_simulator.fabric_composition_r3_canonical_replay.v1"
const MAX_COMMANDS := 20000

var _store = Store.new()
var _runtime = Runtime.new()
var _ids: Array = []
var _batches: Dictionary = {}
var _genesis: Dictionary = {}
var _journal: Array = []

func initialize(sources: Dictionary, authority: Dictionary) -> Dictionary:
	if not _ids.is_empty(): return U.failure("R3_BRIDGE_ALREADY_INITIALIZED")
	var runtime = Runtime.new()
	var checked: Dictionary = runtime.initialize(sources, authority)
	if not checked.success: return checked
	var staged = Store.new()
	for key in ["mechanical", "electrical"]:
		checked = staged.apply_mutation(Mutation.create(Mutation.OP_CREATE, sources[key].construct_id, {}, sources[key]))
		if not checked.success: return checked
	_ids = [sources.mechanical.construct_id, sources.electrical.construct_id]
	_batches = {"mechanical_matter": sources.mechanical_matter.duplicate(true), "electrical_matter": sources.electrical_matter.duplicate(true)}
	_store = staged
	_runtime = runtime
	_genesis = sources.duplicate(true)
	return U.success()

func sources() -> Dictionary:
	if _ids.is_empty(): return {}
	var result: Dictionary = _batches.duplicate(true)
	result["mechanical"] = _store.get_snapshot(_ids[0])
	result["electrical"] = _store.get_snapshot(_ids[1])
	return result

func canonical_state() -> Dictionary:
	return _store.to_dict()

func inspect() -> Dictionary:
	return _runtime.inspect()

func make_command(action: String, payload: Dictionary, authority: Dictionary) -> Dictionary:
	return {"action": action, "payload": payload.duplicate(true), "expected_store_checksum": _store.to_dict().checksum, "expected_authority_checksum": authority.get("checksum", "")}

func execute(command: Dictionary, current_authority: Dictionary, commit_allowed: bool = true) -> Dictionary:
	if _ids.is_empty(): return U.failure("R3_NOT_INITIALIZED")
	if _journal.size() >= MAX_COMMANDS: return U.failure("R3_JOURNAL_BUDGET")
	if not U.validate_exact_fields(command, ["action", "payload", "expected_store_checksum", "expected_authority_checksum"]).success or not command.payload is Dictionary:
		return U.failure("R3_COMMAND_SHAPE")
	var current := sources()
	var checked: Dictionary = _runtime.fence(current, current_authority)
	if not checked.success: return checked
	if command.expected_store_checksum != _store.to_dict().checksum or command.expected_authority_checksum != current_authority.checksum:
		return U.failure("R3_COMMAND_PRECONDITION")
	var action: String = str(command.action)
	var payload: Dictionary = command.payload
	match action:
		"advance":
			if not U.validate_exact_fields(payload, ["dt_s"]).success or not U.is_finite_number(payload.dt_s): return U.failure("R3_COMMAND_DT")
			checked = _runtime.advance(float(payload.dt_s), current, current_authority)
		"fidelity":
			if not U.validate_exact_fields(payload, ["target", "certificate"]).success or not payload.target is String or not payload.certificate is Dictionary: return U.failure("R3_COMMAND_FIDELITY")
			checked = _runtime.set_fidelity(payload.target, current, current_authority, payload.certificate)
		"input", "load", "commit_failure":
			if not commit_allowed: return U.failure("R3_EXTERNAL_COMMIT_DENIED")
			var successor := _successor(current, action, payload)
			if not successor.success: return successor
			var kind := "failure" if action == "commit_failure" else action
			var prepared: Dictionary = _runtime.prepare_successor(current, successor.details.sources, current_authority, kind)
			if not prepared.success: return prepared
			var staged = Store.new()
			checked = staged.load_dict(_store.to_dict())
			if not checked.success: return checked
			var changed_key: String = successor.details.changed_key
			checked = staged.apply_mutation(Mutation.create(Mutation.OP_UPDATE, current[changed_key].construct_id, current[changed_key], successor.details.sources[changed_key]))
			if not checked.success: return checked
			# Neither side can fail after staging; publish in one synchronous owner turn.
			_store.replace_from(staged)
			_runtime._adopt_prepared(prepared.prepared)
		_: return U.failure("R3_COMMAND_UNSUPPORTED")
	if not checked.success: return checked
	_journal.append({"command": command.duplicate(true), "after_store_checksum": _store.to_dict().checksum})
	return U.success({"snapshot": inspect(), "canonical_checksum": _store.to_dict().checksum})

func _successor(current: Dictionary, action: String, payload: Dictionary) -> Dictionary:
	var next: Dictionary = current.duplicate(true)
	var key := "mechanical"
	match action:
		"commit_failure":
			if not U.validate_exact_fields(payload, ["event_id"]).success: return U.failure("R3_FAILURE_COMMAND_SHAPE")
			var pending: Dictionary = _runtime.inspect().pending_proposal
			if pending.is_empty() or payload.event_id != pending.event_id: return U.failure("R3_FAILURE_PROPOSAL_MISMATCH")
			for bond in next.mechanical.bonds:
				if bond.bond_id == pending.bond_id: bond.state = "BROKEN"
			next.mechanical.build_state = "DAMAGED"
		"input":
			if not U.validate_exact_fields(payload, ["field", "value"]).success or not payload.field in ["source_voltage_v", "external_force_n"] or not U.is_finite_number(payload.value): return U.failure("R3_INPUT_COMMAND_SHAPE")
			next.mechanical.compiled_facets.composition_r3[payload.field] = float(payload.value)
		"load":
			if not U.validate_exact_fields(payload, ["resistance_ohm"]).success or not U.is_positive_number(payload.resistance_ohm) or float(payload.resistance_ohm) < 1.0e-9: return U.failure("R3_LOAD_COMMAND_SHAPE")
			key = "electrical"
			var model := Runtime.C.R2.compile_electrical(current.electrical, current.electrical_matter)
			if not model.success: return model
			for i in range(next.electrical.bonds.size()):
				var bond: Dictionary = next.electrical.bonds[i]
				if bond.metadata.composition_r3_role == "LOAD_RESISTANCE":
					# Canonical geometry changes; coefficients are always rederived by R2.
					bond.metadata.area_m2 *= float(model.details.model.elements[i].resistance_ohm) / float(payload.resistance_ohm)
	var snapshot: Dictionary = next[key]
	next[key] = Snapshot.create(snapshot.construct_id, snapshot.root_item_instance_id, int(snapshot.state_revision) + 1, snapshot.build_state, snapshot.parts, snapshot.bonds, snapshot.compiled_facets)
	return U.success({"sources": next, "changed_key": key})

func export_replay() -> Dictionary:
	# No DAE state, compiled coefficients or BAKE capsule is persisted as truth.
	var value := {"schema": JOURNAL_SCHEMA, "genesis_sources": _genesis.duplicate(true), "journal": _journal.duplicate(true), "terminal_store_checksum": _store.to_dict().checksum, "terminal_snapshot_hash": U.canonical_hash(inspect()), "checksum": ""}
	value.checksum = U.compute_checksum(value)
	return value

func replay(document: Dictionary, current_store: Dictionary, current_matter: Dictionary, current_authority: Dictionary, expected_replay_checksum: String) -> Dictionary:
	if not _ids.is_empty(): return U.failure("R3_REPLAY_REQUIRES_FRESH_INSTANCE")
	if not U.is_lower_hex_64(expected_replay_checksum) or expected_replay_checksum != document.get("checksum", ""):
		return U.failure("R3_REPLAY_UNTRUSTED_JOURNAL")
	if not U.validate_exact_fields(document, ["schema", "genesis_sources", "journal", "terminal_store_checksum", "terminal_snapshot_hash", "checksum"]).success or document.get("schema") != JOURNAL_SCHEMA or not U.validate_checksum(document).success:
		return U.failure("R3_REPLAY_DOCUMENT_INVALID")
	if not document.genesis_sources is Dictionary or not document.journal is Array or document.journal.size() > MAX_COMMANDS:
		return U.failure("R3_REPLAY_BUDGET_OR_SHAPE")
	if not Store.validate_state(current_store).success or current_store.checksum != document.terminal_store_checksum or not U.validate_exact_fields(current_matter, ["mechanical_matter", "electrical_matter"]).success:
		return U.failure("R3_REPLAY_EXTERNAL_SOURCE_MISMATCH")
	var trial = get_script().new()
	var checked: Dictionary = trial.initialize(document.genesis_sources, current_authority)
	if not checked.success: return checked
	for entry in document.journal:
		if not entry is Dictionary or not U.validate_exact_fields(entry, ["command", "after_store_checksum"]).success or not entry.command is Dictionary:
			return U.failure("R3_REPLAY_ENTRY_INVALID")
		checked = trial.execute(entry.command, current_authority)
		if not checked.success: return checked
		if trial.canonical_state().checksum != entry.after_store_checksum: return U.failure("R3_REPLAY_COMMIT_DIVERGENCE")
	if U.canonical_hash(trial.canonical_state()) != U.canonical_hash(current_store) or U.canonical_hash(trial.inspect()) != document.terminal_snapshot_hash:
		return U.failure("R3_REPLAY_TERMINAL_DIVERGENCE")
	for key in ["mechanical_matter", "electrical_matter"]:
		if U.canonical_hash(trial.sources()[key]) != U.canonical_hash(current_matter[key]): return U.failure("R3_REPLAY_CURRENT_MATTER_MISMATCH")
	_store = trial._store
	_runtime = trial._runtime
	_ids = trial._ids
	_batches = trial._batches
	_genesis = trial._genesis
	_journal = trial._journal
	return U.success({"snapshot": inspect(), "replayed_commands": _journal.size(), "derived_capsules_restored": 0})
