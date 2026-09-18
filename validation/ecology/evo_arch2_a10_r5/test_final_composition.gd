extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const World = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const ResourceMap = preload("res://scripts/research/ecology/v2/matter_resource_mapping_v1.gd")
const SeamBridge = preload("res://scripts/research/ecology/v2/world_seam_binding_v1.gd")
const DamageOverlay = preload("res://scripts/research/ecology/v2/body_construction_binding_v1.gd")
const Seam = preload("res://scripts/research/ecology/v2/snapshot_seam_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Cell = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Brick = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Sample = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const Query = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
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
		push_error("A10_R5_FAIL " + message)

func _region(owner: String, epoch: int, lifecycle: String, revision: int) -> Dictionary:
	return Region.create(
		"region/a", "u", "i", "surface", "octree", 1,
		{"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []},
		owner, epoch, lifecycle, revision
	)

func _command(seam, op_id: String, kind: String, args: Dictionary, actor: String = "", epoch: int = -1) -> Dictionary:
	var c: Dictionary = seam.cursor()
	return {
		"op_id": op_id, "kind": kind,
		"actor": String(c["owner_id"]) if actor.is_empty() else actor,
		"epoch": int(c["owner_epoch"]) if epoch < 0 else epoch,
		"revision": int(c["revision"]), "clock": int(c["clock"]) + 1,
		"args": args.duplicate(true),
	}

func _matter_query() -> Dictionary:
	var cell := Cell.create("u", "i", "surface", "grid", 1, "root")
	var brick := Brick.create(cell, 0, 0, 0, 0)
	var composition := Composition.create([
		{"material_id": "matter/regolith-loose", "mass_fraction": 0.75},
		{"material_id": "matter/water-ice", "mass_fraction": 0.25},
	])
	var sample := Sample.create(-0.2, 1.0, 1400.0, composition, 0.95, 275.0, 0.30, ["matter-state/solid"])
	return Query.create({
		"query_id": "matter-query/a10-r5", "body_id": "body/moon", "body_frame_id": "frame/moon",
		"body_definition_hash": "a".repeat(64), "grid_profile_hash": "b".repeat(64),
		"generator_version": "1.0.0", "generator_seed": 42, "local_position_m": Vector3(1.0, -0.2, 2.0),
		"requested_level": 0, "source": "MATERIALIZED_BRICK", "cell_address": cell, "brick_address": brick,
		"sample_lattice_index": [0,0,0], "state_revision": 12, "sample": sample,
	})

func _module(id: String, parent: String, role: String, start: Array, finish: Array, area: int = 0, reach: int = 0) -> Dictionary:
	var m := {"id": id, "parent": parent, "role": role, "start_mm": start.duplicate(), "end_mm": finish.duplicate(),
		"radius_mm": 1, "area_mm2": area, "reach_mm": reach, "cost": Body.stock()}
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
		Part.create("part/support", "item/support", "BIO_PROXY", "support", 1.0, [0.0,0.5,0.0]),
		Part.create("part/leaf", "item/leaf", "BIO_PROXY", "collector", 0.2, [0.25,1.25,0.0]),
		Part.create("part/root", "item/root-part", "BIO_PROXY", "absorber", 0.3, [0.0,-0.5,0.0]),
	]

func _damage_event(source_snapshot: Dictionary, body_modules: Array) -> Dictionary:
	var request := DamageRequest.create(
		"damage/a10-r5", "construct/tree", source_snapshot["checksum"], "part/root", [], [],
		{"part/root": "DEGRADED", "part/support": "DESTROYED"}
	)
	if not bool(DamageRequest.validate(request).get("success", false)):
		return {}
	var target := Snapshot.create("construct/tree", "item/tree-root", 2, "DAMAGED", _parts(), [], {})
	var repair := RepairPlan.create("repair/a10-r5", "damage/a10-r5", target, [], [], [], [], request["checksum"])
	var record := DamageRecord.create("damage/a10-r5", request["checksum"], "d".repeat(64), repair, [], 5)
	if not bool(DamageRecord.validate(record).get("success", false)):
		return {}
	var projected := World.project_construction_damage(
		request, record, source_snapshot, body_modules,
		{"part/support": "m000001", "part/leaf": "m000002", "part/root": "m000003"},
		record["checksum"]
	)
	return projected.get("event", {}) if bool(projected.get("success", false)) else {}

func _run() -> void:
	var protocol := Protocol.manifest()
	var treatment := Protocol.treatment()
	_check(not protocol.is_empty() and Protocol.valid_treatment(treatment, protocol), "A7/A8 treatment valid")
	var seam = Seam.new()
	_check(seam.start(treatment, "organism/a", "region/a", "node/a", 1), "A8 seam genesis")
	var source_cursor := seam.cursor()
	var biology_before := seam.ecology_text()
	var source_region := _region("node/a", 1, "ACTIVE", 10)
	var target_warm := _region("node/b", 2, "WARM", 11)
	var target_active := _region("node/b", 2, "ACTIVE", 12)

	var query := _matter_query()
	_check(bool(Query.validate(query).get("success", false)), "production Matter query valid")
	var source_site := World.bind_matter_site(query, source_region, source_cursor)
	_check(bool(source_site.get("success", false)), "source world site binding")
	if not bool(source_site.get("success", false)):
		_finish(); return
	var site_before: Dictionary = source_site["binding"]
	_check(site_before["owner_node_id"] == "node/a" and site_before["authority_epoch"] == 1, "site starts on source authority")

	var catalog := Catalog.default_catalog()
	var mapping := ResourceMap.create(catalog, "eco-map/a10-r5-explicit-water", [
		{"material_id": "matter/water-ice", "resource": "water_mg"},
	])
	var batch := Batch.create({
		"batch_id": "batch/a10-r5", "container_id": "container/a10-r5", "source_body_id": "body/moon",
		"source_operation_id": "operation/a10-r5", "total_mass_kg": 0.001, "bulk_volume_m3": 0.000001,
		"composition": Composition.create([
			{"material_id": "matter/regolith-loose", "mass_fraction": 0.75},
			{"material_id": "matter/water-ice", "mass_fraction": 0.25},
		]), "temperature_k": 273.15,
	})
	var admitted := ResourceMap.admit_material_batch(batch, catalog, mapping)
	_check(bool(admitted.get("success", false)), "R2 explicit resource admission")
	if not bool(admitted.get("success", false)):
		_finish(); return
	var resource_before: Dictionary = admitted["admission"]
	_check(resource_before["resources"]["water_mg"] == 250, "explicit mapped water mass")
	_check(resource_before["resources"]["nutrient_mg"] == 0 and resource_before["resources"]["organic_mg"] == 0, "no guessed biological materials")
	_check(resource_before["mapped_mass_mg"] + resource_before["unmapped_mass_mg"] == resource_before["total_mass_mg"], "resource mass conserved")

	var body_modules := _body()
	var body_hash_before := C.digest(body_modules)
	var source_snapshot := Snapshot.create("construct/tree", "item/tree-root", 1, "OPERATIONAL", _parts(), [], {})
	var body_binding := DamageOverlay.create_binding(
		body_modules, source_snapshot,
		{"part/support": "m000001", "part/leaf": "m000002", "part/root": "m000003"}
	)
	var overlay := DamageOverlay.create_overlay(body_binding, body_modules, source_snapshot)
	var event := _damage_event(source_snapshot, body_modules)
	_check(not body_binding.is_empty() and not overlay.is_empty() and not event.is_empty(), "R1/R4 damage fixtures bound")
	var damaged_result := DamageOverlay.apply_damage(body_binding, overlay, body_modules, source_snapshot, event)
	_check(bool(damaged_result.get("success", false)), "persistent physical damage applied")
	if not bool(damaged_result.get("success", false)):
		_finish(); return
	var damaged: Dictionary = damaged_result["overlay"]
	var function_before := DamageOverlay.effective_function(body_binding, damaged, body_modules, source_snapshot)
	_check(function_before["collector_area_mm2"] == 0 and function_before["absorber_reach_mm"] == 100, "damage changes effective function")
	var overlay_checksum_before := String(damaged["checksum"])
	var function_hash_before := String(function_before["functional_hash"])
	var encoded_overlay := C.encode(damaged)
	var decoded_overlay := C.decode(encoded_overlay)
	_check(not encoded_overlay.is_empty() and bool(decoded_overlay.get("success", false)) and decoded_overlay["value"] == damaged, "damage overlay canonical persistence roundtrip")

	var prepared := SeamBridge.prepare_ticket(
		source_cursor, source_region, target_warm,
		int(source_cursor["clock"]) + 1, int(source_cursor["clock"]) + 100
	)
	_check(bool(prepared.get("success", false)), "R3 prepares production ticket")
	if not bool(prepared.get("success", false)):
		_finish(); return
	var begin := _command(seam, "a10.r5.begin", "BEGIN", {"ticket": prepared["ticket"]})
	var step := seam.apply(begin, seam.snapshot_hash())
	_check(bool(step.get("success", false)), "A8 BEGIN")
	for state in ["PREPARING", "FROZEN", "SNAPSHOT_READY", "TARGET_PREPARED", "COMMITTED"]:
		var live_ticket := seam.ticket_snapshot()
		var target_ack := state == "TARGET_PREPARED"
		var cmd := _command(
			seam, "a10.r5." + state.to_lower(), "TRANSITION",
			{"ticket_id": String(live_ticket["ticket_id"]), "state": state,
			 "payload_hash": String(live_ticket.get("snapshot_hash", "")) if target_ack else ""},
			"node/b" if target_ack else String(seam.cursor()["owner_id"]),
			2 if target_ack else int(seam.cursor()["owner_epoch"])
		)
		step = seam.apply(cmd, seam.snapshot_hash(), seam.ecology_text() if target_ack else "")
		_check(bool(step.get("success", false)), "A8 transition " + state)

	var target_cursor := seam.cursor()
	var committed := seam.ticket_snapshot()
	_check(committed["state"] == "COMMITTED" and bool(Ticket.validate(committed).get("success", false)), "production ticket committed")
	_check(target_cursor["owner_id"] == "node/b" and target_cursor["owner_epoch"] == 2, "A8 cursor moved to target")
	_check(seam.ecology_text() == biology_before and target_cursor["ecology_step"] == source_cursor["ecology_step"], "handoff preserves biology")
	_check(not bool(World.admit_cursor(target_cursor, source_region).get("success", false)), "old owner fenced")
	_check(bool(SeamBridge.admit_committed(target_cursor, target_active, committed).get("success", false)), "target owner admitted")

	var target_site := World.bind_matter_site(query, target_active, target_cursor)
	_check(bool(target_site.get("success", false)), "same Matter site rebinds after handoff")
	if bool(target_site.get("success", false)):
		var site_after: Dictionary = target_site["binding"]
		_check(site_after["owner_node_id"] == "node/b" and site_after["authority_epoch"] == 2, "site authority follows target")
		_check(site_after["physical_sample"] == site_before["physical_sample"], "handoff does not alter Matter sample")
		_check(site_after["query_id"] == site_before["query_id"] and site_after["matter_state_revision"] == site_before["matter_state_revision"], "Matter provenance remains exact")

	var admitted_after := ResourceMap.admit_material_batch(batch, catalog, mapping)
	_check(bool(admitted_after.get("success", false)) and admitted_after["admission"]["accounting_hash"] == resource_before["accounting_hash"], "resource accounting stable across seam")
	_check(DamageOverlay.validate_overlay(damaged, body_binding, body_modules, source_snapshot).is_empty(), "persistent damage remains valid after seam")
	var function_after := DamageOverlay.effective_function(body_binding, damaged, body_modules, source_snapshot)
	_check(String(damaged["checksum"]) == overlay_checksum_before, "damage overlay bytes unchanged by handoff")
	_check(String(function_after["functional_hash"]) == function_hash_before, "effective body function unchanged by handoff")
	_check(C.digest(body_modules) == body_hash_before, "historical BodyGraph unchanged end-to-end")

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_R5_FINAL_COMPOSITION checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_R5_FINAL_COMPOSITION PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_R5_FAILURE " + failure)
		quit(1)
