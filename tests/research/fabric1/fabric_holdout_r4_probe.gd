extends SceneTree

# Measurement adapter only. No expected values, case-family selection, solver or
# series/parallel topology reduction is allowed on this side of the boundary.
const B = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const U = C.U

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0] in ["measure", "replay"]:
		push_error("R4_USAGE: measure|replay input.json output.json")
		quit(2)
		return
	var input = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not input is Array or input.is_empty():
		push_error("R4_EMPTY_OR_MALFORMED_INPUT")
		quit(2)
		return
	var results: Array = []
	for entry in input:
		print("R4_PROBE_CASE=", entry.get("id", "invalid"))
		results.append(_measure(entry) if args[0] == "measure" else _replay(entry))
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		push_error("R4_OUTPUT_UNWRITABLE")
		quit(2)
		return
	file.store_string(JSON.stringify(results, "", true, true) + "\n")
	file.close()
	print("R4_PROBE_COMPLETED=", results.size(), " MODE=", args[0])
	quit(0) # Transport success, NOT a physics/holdout verdict.

func _sources(input: Dictionary) -> Dictionary:
	var result := {}
	for domain in ["mechanical", "electrical"]:
		var spec: Dictionary = input[domain]
		var parts: Array = []
		var bonds: Array = []
		var mass := 0.0
		for node in spec.nodes:
			var metadata := {"physics_r2_anchor": node.anchored} if domain == "mechanical" else {}
			parts.append(Part.create(node.id, "item/" + node.id, "BEAM", domain, node.mass_kg, node.position_m, metadata))
			mass += float(node.mass_kg)
		for edge in spec.edges:
			bonds.append(Bond.create(edge.id, edge.a, edge.b, edge.kind, edge.capacity_n, "INTACT", edge.metadata))
		var facets := {"composition_r3": input.controls} if domain == "mechanical" else {"holdout_boundary_voltages_v": input.ports}
		result[domain] = Snapshot.create("construct/r4-" + domain, "item/r4-" + domain, 1, "OPERATIONAL", parts, bonds, facets)
		result[domain + "_matter"] = Batch.create({"batch_id": "batch/r4-" + domain, "container_id": "container/r4-" + domain, "source_body_id": "body/r4", "source_operation_id": "operation/r4-" + domain, "total_mass_kg": mass, "bulk_volume_m3": mass * 0.001, "composition": Composition.create([{"material_id": spec.material, "mass_fraction": 1.0}]), "temperature_k": 293.15})
	return result

func _authority(sources: Dictionary, owner: String = "server/holdout-r4") -> Dictionary:
	var records: Array = []
	var mutable: Array = []
	var readonly: Array = []
	for domain in ["mechanical", "electrical"]:
		var id: String = sources[domain].construct_id
		records.append({"source_domain": "CONSTRUCTION", "source_id": id, "authority_epoch": 17, "owner_id": owner})
		mutable.append(U.source_key("CONSTRUCTION", id))
		id = sources[domain + "_matter"].batch_id
		records.append({"source_domain": "MATTER", "source_id": id, "authority_epoch": 17, "owner_id": owner})
		readonly.append(U.source_key("MATTER", id))
	return C.A.create(owner, records, mutable, readonly)

func _command(bridge, authority: Dictionary, action: String, payload: Dictionary) -> Dictionary:
	return bridge.execute(bridge.make_command(action, payload, authority), authority)

func _measure(input: Dictionary) -> Dictionary:
	var sources := _sources(input)
	var authority := _authority(sources)
	var source_hash := U.canonical_hash(sources)
	var compiled := C.compile(sources, authority)
	var result := {"id": input.id, "source_hash": source_hash, "sources": sources, "compile": compiled.duplicate(true), "r2_mechanical": C.R2.compile_mechanical(sources.mechanical, sources.mechanical_matter), "r2_electrical": C.R2.compile_electrical(sources.electrical, sources.electrical_matter), "runs": {}}
	# Do not leak compiled internals into the reference side; keep just outcomes
	# and max-step evidence. The immutable source archive contains model code.
	for key in ["compile", "r2_mechanical", "r2_electrical"]:
		if result[key].get("success", false):
			result[key] = {"success": true}
	if not compiled.success:
		result["source_unchanged"] = source_hash == U.canonical_hash(sources)
		return result
	result["max_step_s"] = compiled.details.model.max_step_s
	for fidelity in ["FULL", "BAKE"]:
		var bridge = B.new()
		var initialized: Dictionary = bridge.initialize(sources, authority)
		var run := {"initialize": initialized, "samples": [], "steps_done": 0}
		if not initialized.success:
			result.runs[fidelity] = run
			continue
		if fidelity == "BAKE":
			run["initial_bake"] = _command(bridge, authority, "fidelity", {"target": "BAKE", "certificate": {}})
			if not run.initial_bake.success:
				result.runs[fidelity] = run
				continue
		for step_index in range(int(input.steps)):
			if not bridge.inspect().pending_proposal.is_empty(): break
			var before: Dictionary = bridge.inspect()
			var advanced := _command(bridge, authority, "advance", {"dt_s": input.dt_s})
			if not advanced.success:
				run["advance_error"] = advanced
				run["failed_advance_atomic"] = before == bridge.inspect()
				break
			run.samples.append(bridge.inspect())
			run.steps_done += 1
		run["final"] = bridge.inspect()
		run["bake_at_end"] = _command(bridge, authority, "fidelity", {"target": "BAKE", "certificate": {}})
		var saved: Dictionary = bridge.inspect()
		var canonical: Dictionary = bridge.canonical_state()
		var wrong_owner := _authority(sources, "server/other")
		var cmd: Dictionary = bridge.make_command("input", {"field": "source_voltage_v", "value": 0.0}, authority)
		run["wrong_owner_rejected"] = not bridge.execute(cmd, wrong_owner).success
		run["denied_rejected"] = not bridge.execute(cmd, authority, false).success
		run["rejection_atomic"] = saved == bridge.inspect() and canonical == bridge.canonical_state()
		if not saved.pending_proposal.is_empty():
			cmd = bridge.make_command("commit_failure", {"event_id": saved.pending_proposal.event_id}, authority)
			run["denied_failure_rejected"] = not bridge.execute(cmd, authority, false).success
			run["denied_failure_atomic"] = saved == bridge.inspect() and canonical == bridge.canonical_state()
			run["commit_failure"] = bridge.execute(cmd, authority)
			run["post_commit"] = bridge.inspect()
			run["duplicate_rejected"] = not bridge.execute(cmd, authority).success
		var document: Dictionary = bridge.export_replay()
		run["replay_package"] = {"id": input.id + "/" + fidelity, "document": document, "store": bridge.canonical_state(), "matter": {"mechanical_matter": bridge.sources().mechanical_matter, "electrical_matter": bridge.sources().electrical_matter}, "authority": authority, "trusted_checksum": document.checksum, "snapshot_hash": U.canonical_hash(bridge.inspect())}
		result.runs[fidelity] = run
	result["source_unchanged"] = source_hash == U.canonical_hash(sources)
	return result

func _replay(package: Dictionary) -> Dictionary:
	var bridge = B.new()
	var checked: Dictionary = bridge.replay(package.document, package.store, package.matter, package.authority, package.trusted_checksum)
	var observed := U.canonical_hash(bridge.inspect()) if checked.success else ""
	return {"id": package.id, "result": checked, "snapshot_hash": observed, "matches": observed == package.snapshot_hash}
