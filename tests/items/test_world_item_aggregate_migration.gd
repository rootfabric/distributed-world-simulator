extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const GraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")
const Presenter = preload("res://scripts/items/presentation/item_representation_system.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var legacy_domain := _legacy_fixture()
	var legacy_world_item = _find_world_item(legacy_domain)
	var legacy_spatial: Dictionary = Relations.spatial_ref_from_relation(legacy_world_item.relation)
	var legacy_snapshot: Dictionary = {
		"schema": GraphPersistence.LEGACY_SCHEMA,
		"schema_version": GraphPersistence.LEGACY_SCHEMA_VERSION,
		"items": legacy_domain.items.to_dict(),
		"containers": legacy_domain.containers.to_dict(),
		"attachments": legacy_domain.attachments.to_dict(),
		"operations": legacy_domain.operations.to_dict(),
		"metadata": {"checkpoint": "legacy-world-relation"},
	}

	var restored := Factory.create()
	var persistence = GraphPersistence.new()
	persistence.setup(restored, null, "migration")
	var migration_result: Dictionary = persistence.load_snapshot(legacy_snapshot)
	_assert_success(migration_result, "Legacy graph must migrate")
	_assert(int(migration_result.get("source_schema_version", 0)) == 1, "Migration must report source schema v1")
	_assert(int(migration_result.get("migrated_relation_count", 0)) == 1, "Exactly one WORLD relation must migrate")
	_assert(restored.world_entities.size() == 1, "Migration must create one world aggregate")
	var migrated_item = restored.items.get_item(legacy_world_item.instance_id)
	_assert(migrated_item != null, "Migrated WORLD item must exist")
	_assert(Relations.is_entity_world_relation(migrated_item.relation), "WORLD relation must become entity reference")
	_assert(not migrated_item.relation.has("spatial_ref"), "Canonical WORLD relation must not duplicate spatial_ref")
	_assert(not migrated_item.relation.has("transform"), "Canonical WORLD relation must not duplicate transform")
	_assert(migrated_item.relation.keys().size() == 2, "Canonical WORLD relation must contain only kind and entity_id")
	var aggregate = restored.world_entities.get_for_item(migrated_item.instance_id)
	_assert(aggregate != null, "WORLD item must resolve aggregate")
	_assert(aggregate.item_instance_id == migrated_item.instance_id, "Aggregate back-reference must match item")
	var canonical_legacy = JSON.parse_string(JSON.stringify(legacy_spatial, "", true, true))
	_assert(canonical_legacy is Dictionary and aggregate.spatial_ref == Dictionary(canonical_legacy), "Migration must preserve canonical SpatialRef")
	_assert_success(restored.world_entities.validate_item_bindings(restored.items), "Migrated bindings must validate")

	var current_snapshot: Dictionary = persistence.create_snapshot({"checkpoint": "v16.3.3"})
	_assert(String(current_snapshot.get("schema", "")) == GraphPersistence.SCHEMA, "New snapshot must use v2 graph schema")
	_assert(int(current_snapshot.get("schema_version", 0)) == 2, "New snapshot must use graph version 2")
	_assert(current_snapshot.has("world_entities"), "New snapshot must persist world entities")
	var json_roundtrip = JSON.parse_string(JSON.stringify(current_snapshot, "", true, true))
	_assert(json_roundtrip is Dictionary, "Graph snapshot must survive JSON")
	var roundtrip_domain := Factory.create()
	var roundtrip_persistence = GraphPersistence.new()
	roundtrip_persistence.setup(roundtrip_domain, null, "roundtrip")
	_assert_success(roundtrip_persistence.load_snapshot(Dictionary(json_roundtrip)), "v2 graph must load after JSON")
	var roundtrip_snapshot: Dictionary = roundtrip_persistence.create_snapshot()
	_assert(roundtrip_snapshot == current_snapshot, "v2 graph round-trip must be exact")

	var stable_before: String = JSON.stringify(roundtrip_persistence.create_snapshot(), "", true, true)
	var missing_entity: Dictionary = roundtrip_persistence.create_snapshot()
	missing_entity["world_entities"]["entities"].clear()
	missing_entity["world_entities"]["entity_count"] = 0
	var missing_result: Dictionary = roundtrip_persistence.load_snapshot(missing_entity)
	_assert(not bool(missing_result.get("success", false)), "Missing referenced world aggregate must fail closed")
	_assert(String(missing_result.get("error_code", "")) == "WORLD_ENTITY_NOT_FOUND", "Missing aggregate must preserve precise error")
	_assert(JSON.stringify(roundtrip_persistence.create_snapshot(), "", true, true) == stable_before, "Failed aggregate load must be transactional")

	var orphan: Dictionary = roundtrip_persistence.create_snapshot()
	var orphan_row: Dictionary = Dictionary(orphan["world_entities"]["entities"][0]).duplicate(true)
	orphan_row["entity_id"] = "entity/item/00000000-0000-4000-8000-ffffffffffff"
	orphan_row["item_instance_id"] = "item/00000000-0000-4000-8000-ffffffffffff"
	orphan["world_entities"]["entities"].append(orphan_row)
	orphan["world_entities"]["entity_count"] = 2
	var orphan_result: Dictionary = roundtrip_persistence.load_snapshot(orphan)
	_assert(not bool(orphan_result.get("success", false)), "Orphan aggregate must fail closed")
	_assert(String(orphan_result.get("error_code", "")) == "ORPHAN_WORLD_ENTITY", "Orphan aggregate must preserve precise error")
	_assert(JSON.stringify(roundtrip_persistence.create_snapshot(), "", true, true) == stable_before, "Orphan rejection must be transactional")

	var holder := Node3D.new()
	get_root().add_child(holder)
	var world_root := Node3D.new()
	var attachment_root := Node3D.new()
	holder.add_child(world_root)
	holder.add_child(attachment_root)
	var presenter = Presenter.new()
	holder.add_child(presenter)
	presenter.setup(
		roundtrip_domain.items,
		world_root,
		attachment_root,
		false,
		roundtrip_domain.mass,
		null,
		"scenario/test/local",
		"",
		roundtrip_domain.world_entities
	)
	var world_item = _find_world_item(roundtrip_domain)
	var world_aggregate = roundtrip_domain.world_entities.get_for_item(world_item.instance_id)
	presenter.synchronize_item(world_item.instance_id)
	var body: RigidBody3D = presenter.get_world_node(world_item.instance_id)
	_assert(body != null, "Presenter must create WORLD body from aggregate")
	_assert(body.transform.origin.is_equal_approx(SpatialRef.get_position(world_aggregate.spatial_ref)), "Presenter must read canonical aggregate position")
	var relation_before: Dictionary = world_item.relation.duplicate(true)
	var item_revision_before: int = int(world_item.revision)
	var aggregate_revision_before: int = int(world_aggregate.state_revision)
	body.transform.origin += Vector3(3.0, 4.0, 5.0)
	body.linear_velocity = Vector3(7.0, 8.0, 9.0)
	_assert(presenter.capture_world_state(world_item.instance_id), "Presenter must capture body into aggregate")
	_assert(world_item.relation == relation_before, "Physics capture must not mutate item relation")
	_assert(int(world_item.revision) == item_revision_before, "Physics capture must not mutate item revision")
	_assert(int(world_aggregate.state_revision) == aggregate_revision_before + 1, "Physics capture must increment aggregate revision")
	_assert(SpatialRef.get_position(world_aggregate.spatial_ref).is_equal_approx(body.transform.origin), "Aggregate must capture body position")
	_assert(SpatialRef.get_linear_velocity(world_aggregate.spatial_ref).is_equal_approx(Vector3(7, 8, 9)), "Aggregate must capture body velocity")
	presenter.synchronize_all()
	_assert(body.transform.origin.is_equal_approx(SpatialRef.get_position(world_aggregate.spatial_ref)), "Synchronization must not replay stale item relation")

	holder.queue_free()
	_finish()


func _legacy_fixture() -> Dictionary:
	var domain := Factory.create()
	domain.items.register_definition(Definition.new({
		"id": "beacon",
		"display_name": "Beacon",
		"max_stack": 5,
		"unit_mass_kg": 2.0,
		"external_volume_l": 1.0,
		"tags": ["beacon"],
	}))
	var backpack = ContainerState.new({
		"container_id": "backpack",
		"owner_kind": "ACTOR",
		"owner_id": "player",
		"storage_mode": ContainerState.STORAGE_BULK,
		"slot_count": 8,
	})
	domain.containers.add_container(backpack)
	var world_relation := Relations.world(
		Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(12, 3, -4)),
		Vector3(1, 2, 3),
		"scenario/test/local",
		8.5,
		"main",
		"scenario",
		"migration-test",
		Vector3(0.2, 0.3, 0.4)
	)
	domain.items.create_item("beacon", 1, {}, world_relation)
	var carried = domain.items.create_item("beacon", 2, {}, Relations.container("backpack"))
	backpack.assign_item(carried.instance_id)
	return domain


func _find_world_item(domain: Dictionary):
	for item in domain.items.all_items():
		if Relations.kind_of(item.relation) == Relations.WORLD:
			return item
	return null


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("WORLD item aggregate migration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WORLD item aggregate migration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

