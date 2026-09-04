extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Moon = preload("res://scripts/simulation/matter/generation/moon_geology_sampler.gd")
const Features = preload("res://scripts/simulation/matter/generation/moon_surface_feature_catalog.gd")
const Grid = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Materializer = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const Kernel = preload("res://scripts/simulation/matter/mutation/matter_excavation_kernel.gd")
const ExcavationService = preload("res://scripts/simulation/matter/mutation/matter_excavation_service.gd")
const QueryService = preload("res://scripts/simulation/matter/query/matter_continuous_query_service.gd")
const MatterRequest = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const Participant = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_participant.gd")
const DistributedMassLedger = preload("res://scripts/simulation/matter/transactions/distributed/matter_distributed_mass_ledger.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const MW10AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const MW10Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")
const HandoffInterlock = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_handoff_interlock.gd")
const PhysicalOutput = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_physical_output.gd")
const ItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const P7Gate = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd")
const Router = preload("res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd")
const Delivery = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd")
const Slice = preload("res://scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd")

const PLAYER := "miner"
const ACTOR := "player/miner"
const PRODUCT_AUTHORITY := "authority/p7-7-c3"
const REGION_A := "matter-region/p7-7-c3-a"
const REGION_B := "matter-region/p7-7-c3-b"
const OWNER_A := "simulation-node/p7-7-c3-a"
const OWNER_B := "simulation-node/p7-7-c3-b"
const GLOBAL_OPERATION_ID := "matter-operation/p7-7-c3"
const TRANSACTION_ID := "matter-transaction/p7-7-c3"
const CHECKPOINT_ID := "matter-cross-region-checkpoint/p7-7-c3"
const SURFACE_RADIUS_M := 1737425.0
const ROOT_CENTER_Y_M := 1737429.0

var assertions := 0
var failures: Array[String] = []
var temp_roots: Array[String] = []


class GameplayPort extends RefCounted:
	var position_body_fixed_m := Vector3.ZERO

	func get_player(logical_player_id: String) -> Dictionary:
		if logical_player_id != PLAYER:
			return {}
		return {
			"logical_player_id": PLAYER,
			"player_entity_id": ACTOR,
			"connected": true,
			"position": {
				"x": position_body_fixed_m.x,
				"y": position_body_fixed_m.y,
				"z": position_body_fixed_m.z,
			},
		}


class SM1Port extends RefCounted:
	func authorize_write(authority_id: String, authority_epoch: int) -> Dictionary:
		if authority_id != PRODUCT_AUTHORITY or authority_epoch != 1:
			return MatterUtils.failure("P7_7_C3_SM1_TUPLE_MISMATCH")
		return MatterUtils.success()


class RegionalGate extends RefCounted:
	func authorize_mutation(_request: Dictionary) -> Dictionary:
		return MatterUtils.success({"region_id": REGION_A})

	func owner_id() -> String:
		return OWNER_A

	func authority_epoch() -> int:
		return 1


class RegionResolver extends RefCounted:
	func resolve_brick_address(address: Dictionary) -> Dictionary:
		var path: Array = Array(Dictionary(address.get("cell_address", {})).get("path", []))
		if path.is_empty():
			return {}
		if int(path[0]) == 0:
			return {"region_id": REGION_A}
		if int(path[0]) == 1:
			return {"region_id": REGION_B}
		return {}


class LeaseProvider extends RefCounted:
	var leases: Dictionary = {}

	func _init(values: Array) -> void:
		for raw_value in values:
			var value: Dictionary = raw_value
			leases[String(value["region_id"])] = value.duplicate(true)

	func lease(region_id: String) -> Dictionary:
		return Dictionary(leases.get(region_id, {})).duplicate(true)


class RegionRuntime extends RefCounted:
	var services: Dictionary
	var shared_store
	var commit_counts: Dictionary = {}
	var publish_calls := 0

	func _init(values: Dictionary, store) -> void:
		services = values
		shared_store = store

	func prepare_region(participant: Dictionary, context: Dictionary) -> Dictionary:
		var previous: Dictionary = participant["previous_source_revision"]
		var source: Dictionary = SourceRevision.create(
			"MATTER",
			String(previous["source_id"]),
			int(previous["authority_epoch"]),
			int(previous["source_revision"]) + 1,
			MatterUtils.payload_hash([
				participant["region_id"], "c3-prepared", String(shared_store.content_hash()),
			]),
			MatterUtils.payload_hash([
				context["transaction_id"], participant["checksum"], "c3-dependency",
			])
		)
		return MatterUtils.success({
			"source_revision": source,
			"runtime_state_hash": MatterUtils.payload_hash([
				participant["region_id"], "c3-prepared-state", source["checksum"],
			]),
		})

	func commit_region(
		participant: Dictionary,
		prepare_receipt: Dictionary,
		context: Dictionary
	) -> Dictionary:
		var region_id := String(participant["region_id"])
		var request_value = Dictionary(participant["mutation_payload"]).get("matter_request", null)
		if not services.has(region_id) or typeof(request_value) != TYPE_DICTIONARY:
			return MatterUtils.failure("P7_7_C3_REGION_RUNTIME_BINDING_INVALID")
		var service = services[region_id]
		var result: Dictionary = service.execute(request_value)
		if String(result.get("status", "")) != "COMMITTED":
			return MatterUtils.failure("P7_7_C3_REAL_MATTER_COMMIT_FAILED", {
				"region_id": region_id,
				"matter_result": result,
			})
		var ids: Array = Array(result.get("created_aggregate_ids", []))
		if ids.size() != 1:
			return MatterUtils.failure("P7_7_C3_REAL_BATCH_CARDINALITY_INVALID")
		var batch: Dictionary = service.material_receiver().get_batch(String(ids[0]))
		if batch.is_empty():
			return MatterUtils.failure("P7_7_C3_REAL_BATCH_MISSING")
		commit_counts[region_id] = int(commit_counts.get(region_id, 0)) + 1
		return MatterUtils.success({
			"source_revision": prepare_receipt["source_revision"],
			"runtime_state_hash": MatterUtils.payload_hash([
				region_id,
				"c3-committed-state",
				result["checksum"],
				String(shared_store.content_hash()),
				context["global_commit_hash"],
			]),
			"matter_result": result,
			"material_batch": batch,
		})

	func rollback_region(
		participant: Dictionary,
		_prepare_receipt: Dictionary,
		_context: Dictionary
	) -> Dictionary:
		return MatterUtils.success({
			"source_revision": participant["previous_source_revision"],
			"runtime_state_hash": MatterUtils.payload_hash([
				participant["region_id"], "c3-rollback",
			]),
		})

	func publish_invalidation(_outbox_record: Dictionary) -> Dictionary:
		publish_calls += 1
		return MatterUtils.success({"published": true})


class VisualInvalidator extends RefCounted:
	var calls := 0
	var addresses: Array = []

	func invalidate(values: Array) -> Dictionary:
		calls += 1
		addresses = values.duplicate(true)
		return MatterUtils.success({
			"invalidated": values.size(),
			"root_set": _roots(values),
		})

	func _roots(values: Array) -> Array:
		var unique: Dictionary = {}
		for raw_value in values:
			var path: Array = Array(
				Dictionary(raw_value).get("cell_address", {}).get("path", [])
			)
			if not path.is_empty():
				unique[int(path[0])] = true
		var result: Array = unique.keys()
		result.sort()
		return result


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := _build_world()
	_assert(not world.is_empty(), "C3 real Moon Matter world configured")
	if world.is_empty():
		_finish()
		return

	var graph := ItemGraph.new()
	_assert_ok(graph.setup("authority/p7-7-c3-item-graph", 1), "C3 Item Graph setup")
	graph.ensure_player(PLAYER)
	var tool_created: Dictionary = graph.apply_server_output(
		"operation/p7-7-c3/tool",
		PLAYER,
		"item/tool/mining",
		1,
		"source/p7-7-c3/tool"
	)
	_assert_ok(tool_created, "C3 canonical tool created")
	var tool_id := String(tool_created.get("details", {}).get("output_item_id", ""))
	_assert(not tool_id.is_empty(), "C3 tool id available")
	_assert_ok(graph.execute(
		PLAYER,
		1,
		"operation/p7-7-c3/equip",
		"item.equip",
		{"item_id": tool_id, "slot_id": "tool/main"}
	), "C3 canonical tool equipped")

	var root_center: Vector3 = world["root_center"]
	var query_origin := root_center + Vector3(-0.1, 6.0, -2.5)
	var query_result: Dictionary = world["query"].raycast(
		query_origin, Vector3.DOWN, 12.0, 2, 0.2, 0.15, 512
	)
	_assert(
		bool(query_result.get("success", false))
			and bool(query_result.get("details", {}).get("hit", false)),
		"C3 canonical query hits real Matter"
	)
	if not bool(query_result.get("success", false)) 			or not bool(query_result.get("details", {}).get("hit", false)):
		_finish()
		return

	var hit: Vector3 = query_result["details"]["position_m"]
	var global_request: Dictionary = world["planner"].create_excavation_request(
		GLOBAL_OPERATION_ID,
		ACTOR,
		tool_id,
		hit + Vector3.UP * 0.25,
		hit + Vector3.DOWN * 1.5,
		0.35,
		1000000000.0,
		1
	)
	_assert_ok(MatterRequest.validate(global_request), "C3 global Matter request")
	_assert(_roots_from_request(global_request) == [0, 1], "C3 global target is exactly A+B")

	var root_a := _region_root(world["grid"], 0)
	var root_b := _region_root(world["grid"], 1)
	var service_a = _region_service(world, "container/p7-7-c3-a", root_a)
	var service_b = _region_service(world, "container/p7-7-c3-b", root_b)
	_assert(service_a != null and service_b != null, "C3 regional MW4 executors configured")
	if service_a == null or service_b == null:
		_finish()
		return

	var request_a: Dictionary = service_a.create_excavation_request(
		"matter-operation/p7-7-c3/region-a",
		ACTOR,
		tool_id,
		hit + Vector3.UP * 0.25,
		hit + Vector3.DOWN * 1.5,
		0.35,
		1000000000.0,
		1
	)
	var request_b: Dictionary = service_b.create_excavation_request(
		"matter-operation/p7-7-c3/region-b",
		ACTOR,
		tool_id,
		hit + Vector3.UP * 0.25,
		hit + Vector3.DOWN * 1.5,
		0.35,
		1000000000.0,
		1
	)
	_assert_ok(MatterRequest.validate(request_a), "C3 A request")
	_assert_ok(MatterRequest.validate(request_b), "C3 B request")
	_assert(_roots_from_request(request_a) == [0], "C3 A request scoped to region root 0")
	_assert(_roots_from_request(request_b) == [1], "C3 B request scoped to region root 1")
	var partition_ids := _address_ids(request_a)
	partition_ids.append_array(_address_ids(request_b))
	partition_ids.sort()
	_assert(partition_ids == _address_ids(global_request), "C3 A+B requests partition global target")

	var preview_a := _preview(world, request_a)
	var preview_b := _preview(world, request_b)
	_assert_ok(preview_a, "C3 A real kernel preview")
	_assert_ok(preview_b, "C3 B real kernel preview")
	_assert(float(preview_a.get("details", {}).get("removed_mass_kg", 0.0)) > 0.0, "C3 A preview removes mass")
	_assert(float(preview_b.get("details", {}).get("removed_mass_kg", 0.0)) > 0.0, "C3 B preview removes mass")

	var leases := [
		_make_lease(REGION_A, OWNER_A, root_a, world["grid"]),
		_make_lease(REGION_B, OWNER_B, root_b, world["grid"]),
	]
	var participants := [
		_make_participant(REGION_A, OWNER_A, root_a, leases[0], request_a),
		_make_participant(REGION_B, OWNER_B, root_b, leases[1], request_b),
	]
	_assert(not Dictionary(leases[0]).is_empty() and not Dictionary(leases[1]).is_empty(), "C3 leases valid")
	_assert(not Dictionary(participants[0]).is_empty() and not Dictionary(participants[1]).is_empty(), "C3 participants valid")
	var ledger := _make_ledger(preview_a, preview_b)
	_assert(not ledger.is_empty(), "C3 distributed ledger derives from real preview")
	var plan := Plan.create({
		"transaction_id": TRANSACTION_ID,
		"operation_id": GLOBAL_OPERATION_ID,
		"body_id": world["body"]["body_id"],
		"created_tick": 30,
		"participants": participants,
		"mass_ledger": ledger,
	})
	_assert_ok(Plan.validate(plan), "C3 real MW10 plan")
	_assert(Plan.participant_region_ids(plan) == [REGION_A, REGION_B], "C3 plan regions exactly A+B")

	var player_port := GameplayPort.new()
	player_port.position_body_fixed_m = query_origin
	var product_gate := P7Gate.new()
	_assert_ok(product_gate.configure(
		player_port,
		graph,
		SM1Port.new(),
		RegionalGate.new(),
		PRODUCT_AUTHORITY,
		1,
		50.0,
		Callable(self, "_project_player_position")
	), "C3 P7.1 product gate")

	var authority_gate := MW10AuthorityGate.new()
	_assert_ok(authority_gate.configure(LeaseProvider.new(leases)), "C3 MW10 authority gate")
	var runtime := RegionRuntime.new(
		{REGION_A: service_a, REGION_B: service_b},
		world["store"]
	)
	var mw10 := MW10Coordinator.new()
	_assert_ok(mw10.configure(_temp_root("mw10"), authority_gate, runtime), "C3 MW10 coordinator")
	_assert_ok(mw10.initialize(CHECKPOINT_ID, 20), "C3 MW10 checkpoint")
	var interlock := HandoffInterlock.new()
	_assert_ok(interlock.configure(mw10), "C3 reservation interlock")

	var router := Router.new()
	_assert_ok(router.configure(
		product_gate,
		RegionResolver.new(),
		Callable(self, "_single_forbidden"),
		Callable(self, "_handoff_forbidden"),
		mw10,
		interlock
	), "C3 real P7.6 router")
	var delivery := Delivery.new()
	_assert_ok(delivery.configure(world["planner"], graph), "C3 P7.3 delivery")
	var visual := VisualInvalidator.new()
	var slice := Slice.new()
	_assert_ok(slice.configure(router, delivery, Callable(visual, "invalidate")), "C3 graphical slice")

	var store_before := String(world["store"].content_hash())
	var graph_before: Dictionary = graph.create_snapshot()
	var binding := {
		"query_result": query_result,
		"request": global_request,
		"mw10_plan": plan,
		"server_tick": 40,
		"transition_prefix": "transition/p7-7-c3",
	}
	var executed: Dictionary = slice.execute_aimed_dig(binding)
	_assert_ok(executed, "C3 true A+B end-to-end dig")
	var details: Dictionary = Dictionary(executed.get("details", {}))
	_assert(String(details.get("route", "")) == Router.ROUTE_MULTI_REGION, "C3 route is P7.6→MW10")
	_assert(bool(details.get("mw10_invoked", false)), "C3 MW10 invoked")
	_assert(String(details.get("visible_hole_source", "")) == "CANONICAL_MW10_PHYSICAL_OUTPUT", "C3 visible source canonical")
	_assert(String(details.get("inventory_source", "")) == "CANONICAL_ITEM_GRAPH", "C3 inventory owner canonical")
	_assert(_roots_from_addresses(Array(details.get("changed_brick_addresses", []))) == [0, 1], "C3 canonical changed bricks cover A+B")
	_assert(visual.calls == 1 and _roots_from_addresses(visual.addresses) == [0, 1], "C3 visual invalidation covers A+B once")
	_assert(String(world["store"].content_hash()) != store_before, "C3 shared canonical Matter store changed")
	_assert(int(runtime.commit_counts.get(REGION_A, 0)) == 1, "C3 A real MW4 commit exactly once")
	_assert(int(runtime.commit_counts.get(REGION_B, 0)) == 1, "C3 B real MW4 commit exactly once")
	_assert(runtime.publish_calls == 1, "C3 MW10 invalidation published once")

	var durable := mw10.physical_output(GLOBAL_OPERATION_ID)
	_assert_ok(PhysicalOutput.validate(durable), "C3 durable physical output")
	var out_a := PhysicalOutput.participant_output_by_region(durable, REGION_A)
	var out_b := PhysicalOutput.participant_output_by_region(durable, REGION_B)
	_assert(String(out_a.get("matter_result", {}).get("operation_id", "")) == String(request_a["operation_id"]), "C3 A result is real regional operation")
	_assert(String(out_b.get("matter_result", {}).get("operation_id", "")) == String(request_b["operation_id"]), "C3 B result is real regional operation")
	_assert(String(out_a.get("material_batch", {}).get("source_operation_id", "")) == String(request_a["operation_id"]), "C3 A batch real MW4 provenance")
	_assert(String(out_b.get("material_batch", {}).get("source_operation_id", "")) == String(request_b["operation_id"]), "C3 B batch real MW4 provenance")
	_assert(String(out_a.get("material_batch", {}).get("batch_id", "")) != String(out_b.get("material_batch", {}).get("batch_id", "")), "C3 regional batch ids distinct")

	var material: Dictionary = Dictionary(details.get("material_delivery", {}))
	_assert(int(material.get("participant_delivery_count", 0)) == 2, "C3 P7.3 delivers A+B batches")
	_assert(int(material.get("fresh_delivery_count", 0)) == 2, "C3 first delivery fresh twice")
	_assert(int(material.get("replay_delivery_count", -1)) == 0, "C3 first delivery no replay")
	_assert(int(material.get("total_output_quantity", 0)) > 0, "C3 real material reaches Item Graph")
	var graph_after := graph.create_snapshot()
	_assert(String(graph_after.get("checksum", "")) != String(graph_before.get("checksum", "")), "C3 Item Graph changed")
	_assert(_player_ore(graph_after) == int(material.get("total_output_quantity", -1)), "C3 player ore equals P7.3 quantity")

	var store_after := String(world["store"].content_hash())
	var replay := slice.execute_aimed_dig(binding)
	_assert_ok(replay, "C3 exact replay")
	var replay_material: Dictionary = Dictionary(replay.get("details", {}).get("material_delivery", {}))
	_assert(int(replay_material.get("fresh_delivery_count", -1)) == 0, "C3 replay has no fresh delivery")
	_assert(int(replay_material.get("replay_delivery_count", 0)) == 2, "C3 replay reuses both batches")
	_assert(String(world["store"].content_hash()) == store_after, "C3 replay does not mutate Matter again")
	_assert(graph.create_snapshot() == graph_after, "C3 replay does not duplicate inventory")
	_assert(int(runtime.commit_counts.get(REGION_A, 0)) == 1, "C3 replay does not recommit A")
	_assert(int(runtime.commit_counts.get(REGION_B, 0)) == 1, "C3 replay does not recommit B")

	_cleanup()
	_finish()


func _build_world() -> Dictionary:
	var catalog := Catalog.default_catalog()
	var profile := Moon.create_profile({"canonical_surface_radius_m": SURFACE_RADIUS_M})
	var features := Features.default_catalog(int(profile.get("generator_seed", 0)))
	var body := Moon.default_body_definition(catalog, profile, features)
	var root_center := Vector3(0.0, ROOT_CENTER_Y_M, 0.0)
	var grid := Grid.create({
		"universe_id": "main",
		"instance_id": "p7-c3",
		"space_id": "moon",
		"grid_id": "p7-c3-matter",
		"grid_revision": 1,
		"root_id": "p7-c3-root",
		"body_id": body.get("body_id", ""),
		"body_frame_id": body.get("body_frame_id", ""),
		"root_center_m": [root_center.x, root_center.y, root_center.z],
		"root_half_extent_m": 8.0,
		"max_level": 2,
		"brick_interior_resolution": 4,
		"ghost_border_samples": 1,
	})
	if body.is_empty() or grid.is_empty():
		return {}
	var planner := ExcavationService.new()
	if not bool(planner.configure(
		body, catalog, profile, features, grid, 2,
		"container/p7-7-c3-planner", 1000000000.0, 1000000.0,
		null, null, null, Moon
	).get("success", false)):
		return {}
	var query := QueryService.new()
	if not bool(query.configure(
		body, catalog, profile, features, grid, planner.snapshot_store(), Moon
	).get("success", false)):
		return {}
	return {
		"catalog": catalog,
		"profile": profile,
		"features": features,
		"body": body,
		"grid": grid,
		"root_center": root_center,
		"planner": planner,
		"query": query,
		"store": planner.snapshot_store(),
	}


func _region_service(world: Dictionary, container_id: String, scope_root: Dictionary):
	var service := ExcavationService.new()
	var result: Dictionary = service.configure(
		world["body"], world["catalog"], world["profile"], world["features"],
		world["grid"], 2, container_id, 1000000000.0, 1000000.0,
		world["store"], null, null, Moon, scope_root
	)
	if not bool(result.get("success", false)):
		failures.append("C3 regional MW4 configure failed: %s" % String(result.get("error_code", "")))
		return null
	return service


func _preview(world: Dictionary, request: Dictionary) -> Dictionary:
	var masses: Dictionary = {}
	var total := 0.0
	for raw_address in Array(request.get("target_bricks", [])):
		var address: Dictionary = raw_address
		var store = world["store"]
		if not store.has(address):
			var snapshot := Materializer.materialize(
				world["body"], world["catalog"], world["profile"], world["features"],
				world["grid"], address["cell_address"], 0, Moon
			)
			if snapshot.is_empty() or not bool(store.put(snapshot).get("success", false)):
				return MatterUtils.failure("P7_7_C3_PREVIEW_MATERIALIZATION_FAILED")
		var mutation := Kernel.apply_excavation(
			store.get_snapshot(address), world["grid"], request["shape"]
		)
		if not bool(mutation.get("success", false)):
			return mutation
		if not bool(mutation.get("details", {}).get("changed", false)):
			continue
		var details: Dictionary = mutation["details"]
		total += float(details.get("removed_mass_kg", 0.0))
		for material_id in Dictionary(details.get("material_mass_kg", {})).keys():
			masses[material_id] = float(masses.get(material_id, 0.0)) 				+ float(details["material_mass_kg"][material_id])
	if total <= 0.0 or masses.is_empty():
		return MatterUtils.failure("P7_7_C3_PREVIEW_NO_EFFECT")
	return MatterUtils.success({"removed_mass_kg": total, "material_mass_kg": masses})


func _make_ledger(a: Dictionary, b: Dictionary) -> Dictionary:
	var entries: Array = []
	var outputs: Dictionary = {}
	for pair in [
		{"region": REGION_A, "preview": a},
		{"region": REGION_B, "preview": b},
	]:
		var masses: Dictionary = pair["preview"]["details"]["material_mass_kg"]
		var ids: Array = masses.keys()
		ids.sort()
		var removed: Array = []
		for material_id in ids:
			var mass := float(masses[material_id])
			removed.append({"material_id": String(material_id), "mass_kg": mass})
			outputs[material_id] = float(outputs.get(material_id, 0.0)) + mass
		entries.append({"region_id": pair["region"], "removed": removed, "added": []})
	var external: Array = []
	var output_ids: Array = outputs.keys()
	output_ids.sort()
	for material_id in output_ids:
		external.append({"material_id": String(material_id), "mass_kg": float(outputs[material_id])})
	return DistributedMassLedger.create(TRANSACTION_ID, entries, [], external, 0.001)


func _make_lease(
	region_id: String,
	owner_id: String,
	root: Dictionary,
	grid: Dictionary
) -> Dictionary:
	return Lease.create_active(
		region_id,
		String(grid["body_id"]),
		root,
		MatterUtils.payload_hash([region_id, "c3-region-state"]),
		MatterUtils.payload_hash(grid),
		owner_id,
		1,
		1,
		"transition/p7-7-c3/%s" % region_id.get_file(),
		10,
		100,
		1000
	)


func _make_participant(
	region_id: String,
	owner_id: String,
	root: Dictionary,
	lease: Dictionary,
	request: Dictionary
) -> Dictionary:
	var source := SourceRevision.create(
		"MATTER",
		"matter-source/%s" % region_id.get_file(),
		1,
		1,
		MatterUtils.payload_hash([region_id, "c3-source"]),
		MatterUtils.payload_hash([region_id, "c3-dependency"])
	)
	return Participant.create({
		"region_id": region_id,
		"body_id": request["body_id"],
		"region_root_address": root,
		"owner_id": owner_id,
		"authority_epoch": 1,
		"lease_revision": lease["lease_revision"],
		"fencing_token": lease["fencing_token"],
		"previous_source_revision": source,
		"mutation_payload": {"matter_request": request},
		"dirty_bounds_m": [-8.0, -8.0, -8.0, 8.0, 8.0, 8.0],
		"affected_scope_ids": ["matter-scope/%s" % region_id.get_file()],
	})


func _region_root(grid: Dictionary, child: int) -> Dictionary:
	return CellAddress.create(
		String(grid["universe_id"]),
		String(grid["instance_id"]),
		String(grid["space_id"]),
		String(grid["grid_id"]),
		int(grid["grid_revision"]),
		String(grid["root_id"]),
		[child]
	)


func _roots_from_request(request: Dictionary) -> Array:
	return _roots_from_addresses(Array(request.get("target_bricks", [])))


func _roots_from_addresses(addresses: Array) -> Array:
	var unique: Dictionary = {}
	for raw_address in addresses:
		var path: Array = Array(Dictionary(raw_address).get("cell_address", {}).get("path", []))
		if not path.is_empty():
			unique[int(path[0])] = true
	var result: Array = unique.keys()
	result.sort()
	return result


func _address_ids(request: Dictionary) -> Array:
	var result: Array = []
	for raw_address in Array(request.get("target_bricks", [])):
		result.append(String(Dictionary(raw_address).get("address_id", "")))
	result.sort()
	return result


func _player_ore(snapshot: Dictionary) -> int:
	var total := 0
	for raw_item in Array(snapshot.get("items", [])):
		if typeof(raw_item) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw_item
		var location: Dictionary = Dictionary(item.get("location", {}))
		if String(item.get("definition_id", "")) == "item/ore" 				and String(location.get("kind", "")) == "INVENTORY" 				and String(location.get("player_id", "")) == PLAYER:
			total += int(item.get("quantity", 0))
	return total


func _project_player_position(player: Dictionary, _request: Dictionary) -> Dictionary:
	var position: Dictionary = player.get("position", {})
	return {
		"success": true,
		"error_code": "",
		"position_m": [
			float(position.get("x", 0.0)),
			float(position.get("y", 0.0)),
			float(position.get("z", 0.0)),
		],
	}


func _single_forbidden(_request: Dictionary) -> Dictionary:
	return MatterUtils.failure("P7_7_C3_SINGLE_REGION_FORBIDDEN")


func _handoff_forbidden(_region_id: String, _context: Dictionary) -> Dictionary:
	return MatterUtils.failure("P7_7_C3_HANDOFF_FORBIDDEN")


func _temp_root(label: String) -> String:
	var path := ProjectSettings.globalize_path(
		"user://p7-7-c3-%s-%d" % [label, Time.get_ticks_usec()]
	)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	temp_roots.append(path)
	return path


func _cleanup() -> void:
	for path in temp_roots:
		_remove_tree(path)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P7.7-C3 true A+B end-to-end: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7-C3 true A+B end-to-end: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size(),
		])
		quit(1)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
