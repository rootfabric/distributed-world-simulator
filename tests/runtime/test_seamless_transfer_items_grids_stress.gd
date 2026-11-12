extends SceneTree

# L0 in-process seamless transfer stress test: 20 alternating A<->B authority
# transfers over a real Item Graph (backpack container items, world/ground
# items, construction grid attachments) with per-stage timing metrics.
#
# Modelled on tests/runtime/test_v0_sm1_world_mutations_around_handoff.gd.

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const Item = preload("res://scripts/items/domain/item_instance.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const ItemGraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")
const Aggregate = preload("res://scripts/construction/domain/construct_aggregate.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const ConstructStore = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const ConstructMutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ConstructionProjection = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ConstructionPlanner = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const M0Bridge = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const ConstructionAuthority = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P6Projection = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const P6Shadow = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const P6PersistenceOwner = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const WorldContinuity = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_world_state_continuity.gd")
const MutationGate = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_canonical_mutation_gate.gd")

const AUTHORITY_A := "authority/stress-a"
const AUTHORITY_B := "authority/stress-b"
const PLAYER := "player/stress-1"
const CONTAINER_ID := "container/stress-1/backpack"
const PRIMARY_CONSTRUCT := "construct/stress-1/primary"
const PRIMARY_ROOT := "item/00000000-0000-4000-8000-00000000aaa1"
const PRIMARY_PANEL_A := "item/00000000-0000-4000-8000-00000000aaa2"
const PRIMARY_PANEL_B := "item/00000000-0000-4000-8000-00000000aaa3"
const SECONDARY_CONSTRUCT := "construct/stress-1/secondary"
const SECONDARY_ROOT := "item/00000000-0000-4000-8000-00000000bbb1"
const SECONDARY_PANEL_A := "item/00000000-0000-4000-8000-00000000bbb2"
const SECONDARY_PANEL_B := "item/00000000-0000-4000-8000-00000000bbb3"

# Per-era item id bases (era n >= 1).
const BACKPACK_ITEM_BASE := 0x51000001
const GROUND_ITEM_BASE := 0x52000001
const ERA_PANEL_ITEM_BASE := 0x53000001

const BACKPACK_SLOT_BASE := 4

const DOMAIN_ITEM := "p6-domain/item-inventory"
const DOMAIN_CONSTRUCTION := "p6-domain/construction-builds"
const DOMAIN_OUTPOST := "p6-domain/outpost-world-state"

const TRANSFER_COUNT := 20
const METRICS_SCHEMA := "planet_simulator.seamless_transfer_stress_metrics.v1"
const STAGE_KEYS := [
	"begin_transfer_us",
	"prepare_transfer_us",
	"bind_and_validate_warm_us",
	"commit_ownership_us",
	"retire_source_us",
	"activate_target_us",
	"total_us",
]

var assertions := 0
var failures: Array[String] = []
var gameplay := {
	"schema": "stress.seamless_transfer.canonical_gameplay.v1",
	"revision": 1,
	"outpost_id": "outpost/stress-1",
	"phase": "BOOTSTRAP",
	"mutations": [],
}
# instance_id -> expected quantity for every item ever created.
var item_ledger: Dictionary = {}
var expected_authorized := 0
var expected_fenced := 0
var expected_reconciliations := 0
var timing_records: Array[Dictionary] = []


class ExistingRecoveryCoordinator:
	extends RefCounted

	func persist_checkpoint(_checkpoint_id: String, _generation: int, _previous_generation: int, _committed_operation_id: String = "") -> Dictionary:
		return {"success": true, "details": {"checkpoint": {}, "repository": {}}}

	func recover_latest() -> Dictionary:
		return {"success": true, "details": {"checkpoint": {}, "repository": {}}}


func _init() -> void:
	var rt := _make_runtime()
	var domain: Dictionary = rt.domain
	var construction = rt.construction
	var item_persistence = rt.item_persistence

	var projection = P6Projection.new()
	var shadow = P6Shadow.new()
	var persistence = P6PersistenceOwner.new()
	_assert(_ok(persistence.configure(ExistingRecoveryCoordinator.new())), "stress persistence adapter configured")

	var coordinator = TransferCoordinator.new()
	_assert(_ok(coordinator.configure(AUTHORITY_A, 1, {
		"logical_player_id": PLAYER,
		"player_entity_id": "entity/stress-1",
		"last_input_sequence": 0,
		"last_operation_id": "operation/stress-1/bootstrap",
	})), "stress transfer coordinator configured")
	var gate = MutationGate.new()
	_assert(_ok(gate.configure(coordinator)), "stress canonical mutation gate configured")
	var world = WorldContinuity.new()

	_refresh_projection(projection, shadow, item_persistence, construction)
	_assert(_ok(world.configure(item_persistence, construction, persistence, projection, coordinator)), "stress world continuity configured")

	for i in range(1, TRANSFER_COUNT + 1):
		_run_era_and_transfer(i, domain, construction, item_persistence, projection, shadow, world, gate, coordinator)

	# Final canonical state checks.
	_refresh_projection(projection, shadow, item_persistence, construction)
	_assert(_ok(domain.validator.validate_graph()), "stress final canonical Item Graph validates")
	var final_item_snapshot := _canonical_item_snapshot(item_persistence)
	var final_construction_snapshot: Dictionary = construction.export_state()
	_assert(NetworkUtils.payload_hash(projection.get_source("item_graph")) == NetworkUtils.payload_hash(final_item_snapshot), "stress final projection reads canonical Item Graph exactly")
	_assert(NetworkUtils.payload_hash(projection.get_source("construction")) == NetworkUtils.payload_hash(final_construction_snapshot), "stress final projection reads canonical Construction exactly")
	_assert(NetworkUtils.payload_hash(projection.get_source("gameplay")) == NetworkUtils.payload_hash(gameplay), "stress final projection reads canonical gameplay exactly")

	var gate_report: Dictionary = gate.get_report()
	var gate_counters: Dictionary = Dictionary(gate_report.get("counters", {}))
	_assert(int(gate_counters.get("authorized", -1)) == expected_authorized, "stress authorized mutation count %d == %d" % [int(gate_counters.get("authorized", -1)), expected_authorized])
	_assert(int(gate_counters.get("fenced", -1)) == expected_fenced, "stress fenced mutation count %d == %d" % [int(gate_counters.get("fenced", -1)), expected_fenced])
	_assert(int(gate_counters.get("world_entity_reconciliations", -1)) == expected_reconciliations, "stress world entity reconciliation count %d == %d" % [int(gate_counters.get("world_entity_reconciliations", -1)), expected_reconciliations])
	_assert(not bool(gate_report.get("private_item_graph", true)), "stress mutation gate owns no Item Graph")
	_assert(not bool(gate_report.get("private_construction_truth", true)), "stress mutation gate owns no Construction truth")
	_assert(int(world.get_report().get("completed_count", -1)) == TRANSFER_COUNT, "stress world continuity completed all %d transfers" % TRANSFER_COUNT)
	var final_snapshot: Dictionary = coordinator.snapshot()
	_assert(int(final_snapshot.get("authority_epoch", -1)) == TRANSFER_COUNT + 1, "stress final epoch is %d" % (TRANSFER_COUNT + 1))
	_assert(String(final_snapshot.get("active_authority_id", "")) == AUTHORITY_A, "stress final authority returns to A")

	_report_metrics()
	_finish()


func _run_era_and_transfer(i: int, domain: Dictionary, construction, item_persistence, projection, shadow, world, gate, coordinator) -> void:
	var source := AUTHORITY_A if i % 2 == 1 else AUTHORITY_B
	var target := AUTHORITY_B if i % 2 == 1 else AUTHORITY_A
	var source_epoch := i
	var target_epoch := i + 1

	# Era mutations before the transfer: one backpack item, one ground item,
	# one new grid part (assembled through the sanctioned Construction path).
	_authorized_item_add(gate, domain, source, source_epoch, _era_item_id(BACKPACK_ITEM_BASE, i), 7, "operation/stress-1/e%d/pack" % i, "ore", true)
	_authorized_item_add(gate, domain, source, source_epoch, _era_item_id(GROUND_ITEM_BASE, i), 5, "operation/stress-1/e%d/ground" % i, "ore", false)
	_authorized_item_add(gate, domain, source, source_epoch, _era_item_id(ERA_PANEL_ITEM_BASE, i), 1, "operation/stress-1/e%d/panel" % i, "panel", false)
	_authorized_construct_teardown(gate, domain, construction, source, source_epoch, "operation/stress-1/e%d/teardown" % i)
	_authorized_construct_assemble(gate, domain, construction, source, source_epoch, i, "operation/stress-1/e%d/build" % i)
	_refresh_projection(projection, shadow, item_persistence, construction)

	# Timed transfer critical path.
	var transfer_id := "transfer/stress-1/e%d" % i
	var record := {}
	for key in STAGE_KEYS:
		record[key] = 0

	var t0 := Time.get_ticks_usec()
	_assert(_ok(coordinator.begin_transfer(transfer_id, source, target, source_epoch)), "stress e%d begin (%s->%s)" % [i, source, target])
	record["begin_transfer_us"] = Time.get_ticks_usec() - t0

	var t1 := Time.get_ticks_usec()
	_assert(_ok(world.prepare_transfer(transfer_id)), "stress e%d world capture" % i)
	record["prepare_transfer_us"] = Time.get_ticks_usec() - t1

	# Zero-writer gap: fenced writes in the first/last gaps plus samples in the
	# middle; canonical world state must not change during any sampled gap.
	if i == 1 or i == TRANSFER_COUNT or i % 5 == 1:
		var frozen := _fingerprints(item_persistence, construction, projection)
		_assert(_fenced(gate.authorize(source, source_epoch, DOMAIN_ITEM, "operation/stress-1/e%d/frozen/source-item" % i)), "stress e%d gap fences frozen source Item write" % i)
		_assert(_fenced(gate.authorize(target, target_epoch, DOMAIN_ITEM, "operation/stress-1/e%d/frozen/target-item" % i)), "stress e%d gap fences premature target Item write" % i)
		_assert(_fenced(gate.authorize(source, source_epoch, DOMAIN_CONSTRUCTION, "operation/stress-1/e%d/frozen/source-build" % i)), "stress e%d gap fences frozen source Construction write" % i)
		_assert(_fingerprints(item_persistence, construction, projection) == frozen, "stress e%d gap changes no canonical world state" % i)

	var t2 := Time.get_ticks_usec()
	var warm: Dictionary = world.bind_to_warm(transfer_id, shadow.get_report())
	_assert(_ok(warm), "stress e%d WARM binding" % i)
	if _ok(warm):
		var warm_report: Dictionary = Dictionary(warm.get("details", {}).get("warm_report", {}))
		_assert(_ok(coordinator.validate_warm_target(transfer_id, target, warm_report)), "stress e%d target WARM validation" % i)
	record["bind_and_validate_warm_us"] = Time.get_ticks_usec() - t2

	var t3 := Time.get_ticks_usec()
	var commit: Dictionary = coordinator.commit_ownership(transfer_id, source, target, source_epoch, target_epoch)
	_assert(_ok(commit), "stress e%d ownership commit" % i)
	record["commit_ownership_us"] = Time.get_ticks_usec() - t3

	var t4 := Time.get_ticks_usec()
	if _ok(commit):
		var token := String(commit.get("details", {}).get("commit_token", ""))
		_assert(_ok(coordinator.retire_source(transfer_id, source, token)), "stress e%d source retire" % i)
	record["retire_source_us"] = Time.get_ticks_usec() - t4

	var t5 := Time.get_ticks_usec()
	if _ok(commit):
		var token := String(commit.get("details", {}).get("commit_token", ""))
		_assert(_ok(coordinator.activate_target(transfer_id, target, target_epoch, token)), "stress e%d target activate" % i)
	record["activate_target_us"] = Time.get_ticks_usec() - t5

	for key in STAGE_KEYS.slice(0, 6):
		record["total_us"] += int(record[key])
	timing_records.append(record)
	print("[seamless-stress] transfer %d %s total_us=%d" % [i, ("A->B" if i % 2 == 1 else "B->A"), int(record["total_us"])])

	# Post-transfer invariants.
	_assert(_ok(world.validate_after_activation(transfer_id, coordinator)), "stress e%d world continuity after activation" % i)
	_assert(_ok(domain.validator.validate_graph()), "stress e%d Item Graph validates after transfer" % i)
	var snapshot: Dictionary = coordinator.snapshot()
	_assert(int(snapshot.get("authority_epoch", -1)) == target_epoch, "stress e%d active epoch is %d" % [i, target_epoch])
	_assert(String(snapshot.get("active_authority_id", "")) == target, "stress e%d active authority is %s" % [i, target])
	_assert(_verify_ledger(domain), "stress e%d all previously created items survive with same ids/quantities" % i)
	var primary_snapshot: Dictionary = construction.get_construct_snapshot(PRIMARY_CONSTRUCT)
	var secondary_snapshot: Dictionary = construction.get_construct_snapshot(SECONDARY_CONSTRUCT)
	_assert(not primary_snapshot.is_empty() and String(primary_snapshot.get("construct_id", "")) == PRIMARY_CONSTRUCT, "stress e%d primary grid keeps identity" % i)
	_assert(not secondary_snapshot.is_empty() and String(secondary_snapshot.get("construct_id", "")) == SECONDARY_CONSTRUCT, "stress e%d secondary grid keeps identity" % i)
	_assert(int(primary_snapshot.get("parts", []).size()) == 2, "stress e%d primary grid part count stays 2" % i)
	_assert(int(secondary_snapshot.get("parts", []).size()) == 2 + i, "stress e%d secondary grid part count grew to %d" % [i, 2 + i])


func _authorized_item_add(gate, domain: Dictionary, authority_id: String, epoch: int, item_id: String, quantity: int, operation_id: String, definition_id: String, to_backpack: bool) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_ITEM, operation_id)
	_assert(_ok(admitted), "stress Item mutation %s admitted for %s/%d" % [operation_id, authority_id, epoch])
	expected_authorized += 1
	if not _ok(admitted):
		return
	if to_backpack:
		var slot := BACKPACK_SLOT_BASE + int(operation_id.trim_prefix("operation/stress-1/e").split("/")[0])
		_add_item_to_container(domain, item_id, definition_id, "stress item", quantity, slot)
	else:
		var ground := Item.new({
			"instance_id": item_id, "definition_id": definition_id, "display_name": "stress world item", "quantity": quantity,
			"relation": Relations.world(Transform3D(Basis.IDENTITY, Vector3(float(slot_of(item_id)), 0.0, 0.0))), "components": {}, "revision": 0,
		})
		_assert(domain.items.add_item(ground), "stress world item add %s" % item_id)
	item_ledger[item_id] = quantity
	_assert(_ok(domain.validator.validate_graph()), "stress Item mutation %s leaves graph valid" % operation_id)


func _authorized_construct_teardown(gate, domain: Dictionary, construction, authority_id: String, epoch: int, operation_id: String) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_CONSTRUCTION, operation_id)
	_assert(_ok(admitted), "stress Construction teardown %s admitted" % operation_id)
	expected_authorized += 1
	if not _ok(admitted):
		return
	var snapshot: Dictionary = construction.get_construct_snapshot(SECONDARY_CONSTRUCT)
	var root_source := ConstructionProjection.from_item_instance_dict(domain.items.get_item(SECONDARY_ROOT).to_dict())
	var part_projections: Array = []
	for part in snapshot.get("parts", []):
		var item_id := String(part["item_instance_id"])
		var source := ConstructionProjection.from_item_instance_dict(domain.items.get_item(item_id).to_dict())
		if not _ok(source):
			_assert(false, "stress teardown projection for %s" % item_id)
			return
		part_projections.append(source.projection)
	if not _ok(root_source):
		_assert(false, "stress teardown root projection")
		return
	var planned := ConstructionPlanner.build_deconstruction_plan(
		"plan/%s" % operation_id.replace("/", "-"), operation_id,
		snapshot, root_source.projection, part_projections,
		Relations.world(Transform3D(Basis.IDENTITY, Vector3(90.0, 0.0, 0.0)))
	)
	_assert(_ok(planned), "stress teardown plan %s built" % operation_id)
	if _ok(planned):
		var applied: Dictionary = construction.apply_plan(planned.plan)
		_assert(_ok(applied), "stress teardown %s committed: %s" % [operation_id, applied])
		if _ok(applied):
			_assert(_ok(gate.reconcile_item_world_entities(domain)), "stress teardown reconciles world entities")
			expected_reconciliations += 1


func _authorized_construct_assemble(gate, domain: Dictionary, construction, authority_id: String, epoch: int, era: int, operation_id: String) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_CONSTRUCTION, operation_id)
	_assert(_ok(admitted), "stress Construction assemble %s admitted" % operation_id)
	expected_authorized += 1
	if not _ok(admitted):
		return
	var panel_ids := [SECONDARY_PANEL_A, SECONDARY_PANEL_B]
	for n in range(1, era + 1):
		panel_ids.append(_era_item_id(ERA_PANEL_ITEM_BASE, n))
	var aggregate = _secondary_aggregate(panel_ids)
	var root := ConstructionPlanner.create_root_projection(SECONDARY_ROOT, SECONDARY_CONSTRUCT, "stress secondary outpost", Relations.world())
	var part_projections: Array = []
	for panel_id in panel_ids:
		var source := ConstructionProjection.from_item_instance_dict(domain.items.get_item(panel_id).to_dict())
		if not _ok(source):
			_assert(false, "stress assemble projection for %s" % panel_id)
			return
		part_projections.append(source.projection)
	var planned := ConstructionPlanner.build_assembly_plan(
		"plan/%s" % operation_id.replace("/", "-"), operation_id,
		aggregate.export_snapshot(), root, part_projections, {}
	)
	_assert(_ok(planned), "stress assemble plan %s built" % operation_id)
	if _ok(planned):
		var applied: Dictionary = construction.apply_plan(planned.plan)
		_assert(_ok(applied), "stress assemble %s committed: %s" % [operation_id, applied])
		if _ok(applied):
			_assert(_ok(gate.reconcile_item_world_entities(domain)), "stress assemble reconciles world entities")
			expected_reconciliations += 1
	if not item_ledger.has(SECONDARY_ROOT):
		item_ledger[SECONDARY_ROOT] = 1


func _era_item_id(base: int, era: int) -> String:
	return "item/00000000-0000-4000-8000-%012d" % (base + era - 1)


func slot_of(item_id: String) -> int:
	return int(item_id.substr(item_id.length() - 12, 12).to_int()) % 4096


func _secondary_aggregate(panel_ids: Array):
	var aggregate = Aggregate.new()
	_assert(_ok(aggregate.setup(SECONDARY_CONSTRUCT, SECONDARY_ROOT)), "stress secondary aggregate setup")
	# NOTE: all part offsets are [0,0,0] on purpose. Derived compiled facets
	# (center_of_mass_m) are persisted through M0 JSON round trips; a non-dyadic
	# COM component (e.g. 158/15) is not bit-stable across JSON round-trip in
	# the double build and breaks the M0 envelope checksum. Zero offsets keep
	# COM exactly [0,0,0] for any part count.
	for index in range(panel_ids.size()):
		var panel_id: String = panel_ids[index]
		var part_id := "part/stress/base-a" if panel_id == SECONDARY_PANEL_A else ("part/stress/base-b" if panel_id == SECONDARY_PANEL_B else "part/stress/e%d" % (index - 1))
		var part := Part.create(part_id, panel_id, "PANEL", "wall", 5.0, [0.0, 0.0, 0.0])
		_assert(_ok(aggregate.add_part("operation/stress-1/secondary-part/%s" % part_id.replace("/", ":"), aggregate.state_revision, part)), "stress secondary aggregate part %s" % part_id)
	return aggregate


func _verify_ledger(domain: Dictionary) -> bool:
	for item_id in item_ledger:
		var item = domain.items.get_item(item_id)
		if item == null:
			return false
		if int(item.quantity) != int(item_ledger[item_id]):
			return false
	return true


func _refresh_projection(projection, shadow, item_persistence, construction) -> void:
	var item_snapshot := _canonical_item_snapshot(item_persistence)
	var construction_snapshot: Dictionary = construction.export_state()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": gameplay.duplicate(true),
		"item_graph": item_snapshot,
		"construction": construction_snapshot,
	})), "stress P6 projection refreshed from canonical owners")
	_assert(_ok(shadow.configure(projection)), "stress P6 shadow refreshed")


func _fingerprints(item_persistence, construction, projection) -> Dictionary:
	return {
		"item": NetworkUtils.payload_hash(_canonical_item_snapshot(item_persistence)),
		"construction": NetworkUtils.payload_hash(construction.export_state()),
		"outpost": projection.compute_checksum(),
	}


func _fenced(result: Dictionary) -> bool:
	expected_fenced += 1
	return not _ok(result) and String(result.get("error_code", "")) == "SM1_CANONICAL_MUTATION_AUTHORITY_FENCED"


func _report_metrics() -> void:
	var arrays := {}
	for key in STAGE_KEYS:
		arrays[key] = []
	for record in timing_records:
		for key in STAGE_KEYS:
			Array(arrays[key]).append(int(record[key]))

	var summary := {}
	for key in STAGE_KEYS:
		var values: Array = Array(arrays[key]).duplicate()
		values.sort()
		summary[key] = {
			"min": int(values[0]),
			"p50": _percentile(values, 0.5),
			"p95": _percentile(values, 0.95),
			"max": int(values[values.size() - 1]),
		}

	var metrics := {
		"schema": METRICS_SCHEMA,
		"pid": OS.get_process_id(),
		"transfer_count": TRANSFER_COUNT,
		"total_note": "total_us is the sum of the six per-stage timings (begin_transfer through activate_target)",
		"stages": arrays,
		"summary": summary,
	}
	var dir_path := "res://artifacts/test-results/seamless-transfer-stress"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file_path := "%s/metrics-%d.json" % [dir_path, OS.get_process_id()]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		_assert(false, "stress metrics JSON written to %s" % file_path)
		return
	file.store_string(JSON.stringify(metrics, "\t"))
	file.close()
	_assert(true, "stress metrics JSON written to %s" % file_path)

	var totals: Array = Array(arrays["total_us"]).duplicate()
	totals.sort()
	print("[seamless-stress] summary total_us min=%d p50=%d p95=%d max=%d" % [
		int(totals[0]),
		_percentile(totals, 0.5),
		_percentile(totals, 0.95),
		int(totals[totals.size() - 1]),
	])


func _percentile(sorted_values: Array, fraction: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := int(ceil(fraction * float(sorted_values.size()))) - 1
	index = clampi(index, 0, sorted_values.size() - 1)
	return int(sorted_values[index])


func _make_runtime() -> Dictionary:
	var domain: Dictionary = Factory.create()
	for row in [
		{"id": "construct_root", "display_name": "Construct root", "max_stack": 1, "unit_mass_kg": 0.1, "external_volume_l": 0.1, "tags": ["construction"]},
		{"id": "panel", "display_name": "Panel", "max_stack": 1, "unit_mass_kg": 5.0, "external_volume_l": 4.0, "tags": ["construction_part"]},
		{"id": "ore", "display_name": "Ore", "max_stack": 64, "unit_mass_kg": 1.0, "external_volume_l": 1.0, "tags": ["resource"]},
	]:
		domain.items.register_definition(Definition.new(row))
	var backpack = ContainerState.new({
		"container_id": CONTAINER_ID,
		"owner_kind": "ACTOR",
		"owner_id": PLAYER,
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 64,
		"maximum_mass_kg": 10000.0,
		"maximum_volume_l": 10000.0,
	})
	_assert(domain.containers.add_container(backpack), "stress canonical backpack created")
	_add_grid_items(domain)
	item_ledger[PRIMARY_ROOT] = 1
	item_ledger[PRIMARY_PANEL_A] = 1
	item_ledger[PRIMARY_PANEL_B] = 1
	item_ledger[SECONDARY_ROOT] = 1
	item_ledger[SECONDARY_PANEL_A] = 1
	item_ledger[SECONDARY_PANEL_B] = 1
	_assert(_ok(domain.validator.validate_graph()), "stress initial Item Graph valid")

	var constructs = ConstructStore.new()
	for entry in [
		{"construct_id": PRIMARY_CONSTRUCT, "root": PRIMARY_ROOT, "parts": [
			{"part_id": "part/stress/primary-a", "item": PRIMARY_PANEL_A, "offset": [0.0, 0.0, 0.0]},
			{"part_id": "part/stress/primary-b", "item": PRIMARY_PANEL_B, "offset": [0.0, 0.0, 0.0]},
		]},
		{"construct_id": SECONDARY_CONSTRUCT, "root": SECONDARY_ROOT, "parts": [
			{"part_id": "part/stress/base-a", "item": SECONDARY_PANEL_A, "offset": [0.0, 0.0, 0.0]},
			{"part_id": "part/stress/base-b", "item": SECONDARY_PANEL_B, "offset": [0.0, 0.0, 0.0]},
		]},
	]:
		var aggregate = Aggregate.new()
		_assert(_ok(aggregate.setup(String(entry.construct_id), String(entry.root))), "stress aggregate setup %s" % entry.construct_id)
		for part_row in entry.parts:
			var part := Part.create(String(part_row.part_id), String(part_row.item), "PANEL", "wall", 5.0, part_row.offset)
			_assert(_ok(aggregate.add_part("operation/stress-1/setup/%s" % String(part_row.part_id).replace("/", ":"), aggregate.state_revision, part)), "stress aggregate part %s" % part_row.part_id)
		_assert(_ok(constructs.apply_mutation(ConstructMutation.create(ConstructMutation.OP_CREATE, String(entry.construct_id), {}, aggregate.export_snapshot()))), "stress ConstructStore created %s" % entry.construct_id)
	var bridge = M0Bridge.new()
	_assert(_ok(bridge.setup("user://stress-seamless-%d" % Time.get_ticks_usec())), "stress M0 bridge setup")
	var construction = ConstructionAuthority.new()
	_assert(_ok(construction.setup(
		domain.items, domain.containers, domain.validator, domain.mass, domain.operations,
		constructs, bridge, "authority/construction-stress-1", 7, 0, 0, 0,
		{PRIMARY_CONSTRUCT: 1, SECONDARY_CONSTRUCT: 1}
	)), "stress canonical Construction authority setup")
	var item_persistence = ItemGraphPersistence.new()
	item_persistence.setup(domain, null, "stress-seamless-item-graph")
	return {"domain": domain, "construction": construction, "item_persistence": item_persistence}


func _add_grid_items(domain: Dictionary) -> void:
	var roots := [
		{"id": PRIMARY_ROOT, "name": "Primary root", "construct": PRIMARY_CONSTRUCT, "position": Vector3(0.0, 0.0, 0.0)},
		{"id": SECONDARY_ROOT, "name": "Secondary root", "construct": SECONDARY_CONSTRUCT, "position": Vector3(50.0, 0.0, 0.0)},
	]
	for root_row in roots:
		var root = Item.new({
			"instance_id": root_row.id, "definition_id": "construct_root", "display_name": root_row.name, "quantity": 1,
			"relation": Relations.world(Transform3D(Basis.IDENTITY, root_row.position)),
			"components": {"construction_root": {"schema": "planet_simulator.construction_root_component.v1", "construct_id": root_row.construct}}, "revision": 0,
		})
		_assert(domain.items.add_item(root), "stress root item %s added" % root_row.id)
	var panels := [
		{"id": PRIMARY_PANEL_A, "construct": PRIMARY_CONSTRUCT, "root": PRIMARY_ROOT, "part": "part/stress/primary-a"},
		{"id": PRIMARY_PANEL_B, "construct": PRIMARY_CONSTRUCT, "root": PRIMARY_ROOT, "part": "part/stress/primary-b"},
		{"id": SECONDARY_PANEL_A, "construct": SECONDARY_CONSTRUCT, "root": SECONDARY_ROOT, "part": "part/stress/base-a"},
		{"id": SECONDARY_PANEL_B, "construct": SECONDARY_CONSTRUCT, "root": SECONDARY_ROOT, "part": "part/stress/base-b"},
	]
	for panel_row in panels:
		var panel = Item.new({
			"instance_id": panel_row.id, "definition_id": "panel", "display_name": "stress panel", "quantity": 1,
			"relation": Relations.attachment(panel_row.construct, panel_row.root, panel_row.part), "components": {}, "revision": 0,
		})
		_assert(domain.items.add_item(panel), "stress panel item %s added" % panel_row.id)


func _add_item_to_container(domain: Dictionary, item_id: String, definition_id: String, display_name: String, quantity: int, slot: int) -> void:
	var item = Item.new({
		"instance_id": item_id, "definition_id": definition_id, "display_name": display_name, "quantity": quantity,
		"relation": Relations.container(CONTAINER_ID, slot), "components": {}, "revision": 0,
	})
	_assert(domain.items.add_item(item), "stress container item add %s" % item_id)
	var container = domain.containers.get_container(CONTAINER_ID)
	container.item_ids.append(item_id)
	container.slot_assignments[slot] = item_id


func _canonical_item_snapshot(item_persistence) -> Dictionary:
	var result: Dictionary = item_persistence.create_snapshot_result({})
	_assert(_ok(result), "stress Item Graph snapshot created")
	var snapshot: Dictionary = Dictionary(result.get("snapshot", {})).duplicate(true)
	snapshot["metadata"] = {}
	var validation: Dictionary = item_persistence.validate_snapshot(snapshot)
	_assert(_ok(validation), "stress Item Graph snapshot validates: %s" % validation)
	return snapshot


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("[seamless-stress] PASS: %s" % message)
	else:
		failures.append(message)
		print("[seamless-stress][FAIL] %s" % message)


func _finish() -> void:
	print("SEAMLESS_TRANSFER_STRESS Item/Construction/grid stress: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SEAMLESS_TRANSFER_STRESS_PASS")
	quit(0 if failures.is_empty() else 1)
