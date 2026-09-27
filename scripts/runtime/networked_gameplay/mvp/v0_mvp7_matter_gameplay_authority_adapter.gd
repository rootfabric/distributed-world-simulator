extends "res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd"

# Native M6 checkpoint is the commit record for this quiescent M6+MW5 cut.
# Each referenced MW5 generation has a separate immutable repository directory:
# an interrupted later prepare cannot overwrite the previous acknowledged cut.
# No world state is restored from test witnesses, projections or fresh output.
const SharedMatter7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_shared_dig_authority.gd")
const CUT_SCHEMA7 := "distributed_world_simulator.mvp7_matter_gameplay_cut.v1"
const CUT_FIELD7 := "mvp7_matter_cut"
var _shared_matter7 = null
var _world_root7 := ""
var _decisions7: Dictionary = {}
var _sessions7: Dictionary = {}
var _matter_cut7: Dictionary = {}

func configure_matter7(shared_matter, decisions: Dictionary, sessions: Dictionary, world_root: String) -> Dictionary:
	if _service == null or _shared_matter7 != null or shared_matter == null or not shared_matter is SharedMatter7 or world_root.strip_edges().is_empty():
		return _failure("MVP7_MATTER_GAMEPLAY_BINDING_REQUIRED")
	for actor in ["a", "b"]:
		if not decisions.has(actor) or not sessions.has(actor): return _failure("MVP7_MATTER_ACTOR_BINDING_REQUIRED")
	_shared_matter7 = shared_matter
	_decisions7 = decisions.duplicate()
	_sessions7 = sessions.duplicate(true)
	_world_root7 = world_root.trim_suffix("/")
	return _success()

func get_shared_matter7():
	return _shared_matter7

func prepare_checkpoint7(generation: int) -> Dictionary:
	if _shared_matter7 == null or generation < 1 or (not _matter_cut7.is_empty() and generation <= int(_matter_cut7["world_generation"])):
		return _failure("MVP7_NEW_WORLD_GENERATION_REQUIRED")
	var relative_root := "matter/generation-%d" % generation
	var destination := _world_root7 + "/" + relative_root
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination)):
		return _failure("MVP7_IMMUTABLE_MATTER_GENERATION_ALREADY_EXISTS")
	# Called synchronously after the process has stopped new command admission.
	var sealed: Dictionary = _service.seal_recovery_cut7()
	if not bool(sealed.get("success", false)): return sealed
	var durable: Dictionary = _service.export_durable_state()
	if durable.is_empty(): return _failure("MVP7_SEALED_GAMEPLAY_SNAPSHOT_REQUIRED")
	var saved: Dictionary = _shared_matter7.seal_and_save_matter7(destination, int(durable["server_tick"]))
	if not bool(saved.get("success", false)): return saved
	_matter_cut7 = Utils.finalize_json_checksum({"schema": CUT_SCHEMA7, "world_generation": generation, "relative_root": relative_root, "gameplay_checksum": String(durable["checksum"]), "receipt": saved["details"]})
	return _success({"matter_cut": _matter_cut7.duplicate(true), "outer_checkpoint_committed": false})

func export_recovery_state() -> Dictionary:
	var state: Dictionary = super.export_recovery_state()
	if state.is_empty() or _matter_cut7.is_empty(): return state
	if String(state.get("durable_state_checksum", "")) != String(_matter_cut7.get("gameplay_checksum", "")): return {}
	var report: Dictionary = _shared_matter7.report()
	var receipt: Dictionary = _matter_cut7["receipt"]
	for field in ["store_hash", "state_hash", "stream_sequence"]:
		if report.get(field) != receipt.get(field): return {}
	var durable: Dictionary = _service.export_durable_state()
	var components: Dictionary = state["current_snapshot"]["domain_components"].duplicate(true)
	components[CUT_FIELD7] = _matter_cut7.duplicate(true)
	var snapshot: Dictionary = EntitySnapshot.normalize(EntitySnapshot.create("snapshot/m6/dedicated/%d" % int(durable["revision"]), ENTITY_ID, ENTITY_TYPE, int(durable["revision"]), String(durable["authority_owner_id"]), int(durable["authority_epoch"]), int(durable["server_tick"]), _spatial_ref(int(durable["server_tick"])), {"region_id": String(durable["region_id"])}, {}, components))
	if snapshot.is_empty(): return {}
	state["current_snapshot"] = snapshot
	return state

func validate_recovery_state(value: Dictionary) -> Dictionary:
	var native_check: Dictionary = super.validate_recovery_state(value)
	if not bool(native_check.get("success", false)): return native_check
	if _shared_matter7 == null: return _failure("MVP7_MATTER_GAMEPLAY_BINDING_REQUIRED")
	var components: Dictionary = value.get("current_snapshot", {}).get("domain_components", {})
	var cut_value = components.get(CUT_FIELD7)
	if not cut_value is Dictionary: return _failure("MVP7_COMMITTED_MATTER_REFERENCE_REQUIRED")
	var cut: Dictionary = cut_value
	if cut.get("schema") != CUT_SCHEMA7 or not cut.has_all(["world_generation", "relative_root", "gameplay_checksum", "receipt", "checksum"]) or not cut.get("receipt") is Dictionary:
		return _failure("MVP7_MATTER_REFERENCE_INVALID")
	if int(cut["world_generation"]) < 1 or String(cut["relative_root"]) != "matter/generation-%d" % int(cut["world_generation"]): return _failure("MVP7_MATTER_REFERENCE_PATH_INVALID")
	if Utils.finalize_json_checksum(cut).get("checksum") != cut["checksum"]: return _failure("MVP7_MATTER_REFERENCE_CHECKSUM_MISMATCH")
	if String(cut["gameplay_checksum"]) != String(value.get("durable_state_checksum", "")): return _failure("MVP7_MIXED_GAMEPLAY_MATTER_CUT")
	var receipt: Dictionary = cut["receipt"]
	if int(receipt.get("server_tick", -1)) != int(value.get("server_tick", -2)): return _failure("MVP7_MIXED_GAMEPLAY_MATTER_TICK")
	# Composition-internal wiring calls the MW5 participant's port factory;
	# actual validation remains in the native store, receiver and journal.
	var ports: Dictionary = _shared_matter7._persistence_ports7(_world_root7 + "/" + String(cut["relative_root"]))
	if not bool(ports.get("success", false)): return ports
	return ports["details"]["coordinator"].preflight_exact7(String(receipt.get("checkpoint_checksum", "")))

func restore_recovery_state(value: Dictionary) -> Dictionary:
	var checked := validate_recovery_state(value)
	if not bool(checked.get("success", false)): return checked
	var restored: Dictionary = super.restore_recovery_state(value)
	if not bool(restored.get("success", false)): return restored
	# Native M6 restore replaces the canonical M4 owner instance. Every P7
	# material output and authorization port MUST bind that new native instance.
	_shared_matter7.shutdown()
	_shared_matter7 = SharedMatter7.new()
	var configured: Dictionary = _shared_matter7.configure(_service, _decisions7, _sessions7)
	if not bool(configured.get("success", false)): return configured
	var cut: Dictionary = value["current_snapshot"]["domain_components"][CUT_FIELD7]
	var matter: Dictionary = _shared_matter7.restore_matter7(_world_root7 + "/" + String(cut["relative_root"]), cut["receipt"])
	if not bool(matter.get("success", false)): return matter
	_matter_cut7 = cut.duplicate(true)
	return _success({"gameplay": restored.get("details", {}), "matter": matter.get("details", {}), "world_generation": int(cut["world_generation"]), "outer_reference_checksum": String(cut["checksum"]), "same_restored_item_graph": true})
