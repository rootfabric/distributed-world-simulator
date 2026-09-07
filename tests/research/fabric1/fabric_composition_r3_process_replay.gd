extends SceneTree

const B = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const F = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_fixture_v1.gd")
const U = F.C.U
var failed := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0] in ["write", "read"]:
		_finish(false, "expected write/read and evidence directory")
		return
	var folder: String = args[1]
	if args[0] == "write": _write_fixture(folder)
	else: _read_fixture(folder)
	_finish(not failed, args[0])

func _step(b, authority: Dictionary, action: String, payload: Dictionary) -> bool:
	var result: Dictionary = b.execute(b.make_command(action, payload, authority), authority)
	if not result.success:
		print("REPLAY_COMMAND_FAILED=", result)
		failed = true
	return result.success

func _write_fixture(folder: String) -> void:
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		failed = true
		return
	var sources := F.create()
	var authority := F.authority(sources)
	var b = B.new()
	if not b.initialize(sources, authority).success:
		failed = true
		return
	_step(b, authority, "fidelity", {"target": "BAKE", "certificate": {}})
	for i in range(100):
		if not b.inspect().pending_proposal.is_empty(): break
		if not _step(b, authority, "advance", {"dt_s": 0.005}): return
	var pending: Dictionary = b.inspect().pending_proposal
	if pending.is_empty():
		failed = true
		return
	_checkpoint(folder, "pending", b, sources, authority)
	_step(b, authority, "commit_failure", {"event_id": pending.event_id})
	_checkpoint(folder, "committed", b, sources, authority)
	_step(b, authority, "input", {"field": "source_voltage_v", "value": 8.0})
	_step(b, authority, "load", {"resistance_ohm": 4.0})
	_step(b, authority, "fidelity", {"target": "BAKE", "certificate": {}})
	for i in range(20):
		if not _step(b, authority, "advance", {"dt_s": 0.005}): return
	var document: Dictionary = b.export_replay()
	_save(folder.path_join("journal.json"), document)
	# Independent owner persistence input, not fields trusted from the journal.
	_save(folder.path_join("owner.json"), {"store": b.canonical_state(), "matter": {"mechanical_matter": sources.mechanical_matter, "electrical_matter": sources.electrical_matter}, "authority": authority, "expected_journal_checksum": document.checksum, "expected_snapshot_hash": U.canonical_hash(b.inspect())})
	for i in range(20):
		if not _step(b, authority, "advance", {"dt_s": 0.005}): return
	_save(folder.path_join("continuous-reference.json"), {"snapshot_hash": U.canonical_hash(b.inspect()), "snapshot": b.inspect()})

func _read_fixture(folder: String) -> void:
	var document := _load(folder.path_join("journal.json"))
	var owner := _load(folder.path_join("owner.json"))
	var reference := _load(folder.path_join("continuous-reference.json"))
	if failed: return
	for phase in ["pending", "committed"]:
		var stage_document := _load(folder.path_join(phase + "-journal.json"))
		var stage_owner := _load(folder.path_join(phase + "-owner.json"))
		if failed: return
		var stage = B.new()
		var stage_result: Dictionary = stage.replay(stage_document, stage_owner.store, stage_owner.matter, stage_owner.authority, stage_owner.expected_journal_checksum)
		if not stage_result.success or U.canonical_hash(stage.inspect()) != stage_owner.expected_snapshot_hash:
			print("CRASH_PHASE_FAILED=", phase, " ", stage_result)
			failed = true
			return
		if phase == "pending":
			var pending: Dictionary = stage.inspect().pending_proposal
			if pending.is_empty() or not _step(stage, stage_owner.authority, "commit_failure", {"event_id": pending.event_id}):
				failed = true
				return
			var committed_owner := _load(folder.path_join("committed-owner.json"))
			if U.canonical_hash(stage.inspect()) != committed_owner.expected_snapshot_hash:
				failed = true
				return
		print("R3_CRASH_", phase.to_upper(), "_REPLAY=PASS")
	var b = B.new()
	var result: Dictionary = b.replay(document, owner.store, owner.matter, owner.authority, owner.expected_journal_checksum)
	if not result.success or U.canonical_hash(b.inspect()) != owner.expected_snapshot_hash:
		print("COLD_REPLAY_FAILED=", result)
		failed = true
		return
	print("R3_COLD_REPLAY_COMMANDS=", result.details.replayed_commands, " DERIVED_CAPSULES_RESTORED=", result.details.derived_capsules_restored)
	for i in range(20):
		if not _step(b, owner.authority, "advance", {"dt_s": 0.005}): return
	if U.canonical_hash(b.inspect()) != reference.snapshot_hash:
		print("CONTINUITY_MISMATCH=", U.canonical_hash(b.inspect()), " EXPECTED=", reference.snapshot_hash)
		failed = true
	else: print("R3_FRESH_PROCESS_CONTINUITY_HASH=", reference.snapshot_hash)

func _save(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failed = true
		return
	file.store_string(JSON.stringify(value, "\t", true, true))
	if file.get_error() != OK: failed = true
	file.close()

func _load(path: String) -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		failed = true
		return {}
	return value

func _finish(ok: bool, phase: String) -> void:
	print("FABRIC-COMPOSITION-R3-PROCESS-", phase.to_upper(), ": ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _checkpoint(folder: String, phase: String, b, sources: Dictionary, authority: Dictionary) -> void:
	var document: Dictionary = b.export_replay()
	_save(folder.path_join(phase + "-journal.json"), document)
	_save(folder.path_join(phase + "-owner.json"), {"store": b.canonical_state(), "matter": {"mechanical_matter": sources.mechanical_matter, "electrical_matter": sources.electrical_matter}, "authority": authority, "expected_journal_checksum": document.checksum, "expected_snapshot_hash": U.canonical_hash(b.inspect())})
