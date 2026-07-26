extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const Presenter = preload("res://scripts/items/presentation/item_representation_system.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_world_container_roundtrip()
	_test_stack_merge_and_split()
	_test_nested_container_transfer()
	_test_capacity_and_nesting_guards()
	_test_operation_idempotency()
	_test_same_container_move_and_operation_validation()
	_test_graph_integrity_guards()
	_test_attachment_roundtrip()
	_test_mixed_relation_cycle_guard()
	_test_mass_and_external_volume()
	_test_serialization_roundtrip()
	await _test_representation_lifecycle()
	if failures.is_empty():
		print("Item domain tests: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Item domain tests: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_world_container_roundtrip() -> void:
	var fixture = _fixture()
	var rock = fixture.items.create_item("rock", 2, {}, Relations.world(Transform3D.IDENTITY))
	var pickup: Dictionary = fixture.transfer.move_item(rock.instance_id, Relations.container("backpack"), "pickup-1")
	_assert_success(pickup, "World -> container transfer must succeed")
	_assert(Relations.kind_of(rock.relation) == Relations.CONTAINER, "Picked item relation must be CONTAINER")
	_assert(fixture.containers.get_container("backpack").item_ids.has(rock.instance_id), "Backpack must contain picked item")
	var drop_transform = Transform3D(Basis.IDENTITY, Vector3(2.0, 3.0, 4.0))
	var drop: Dictionary = fixture.transfer.move_item(rock.instance_id, Relations.world(drop_transform, Vector3(1.0, 0.0, 0.0)), "drop-1")
	_assert_success(drop, "Container -> world transfer must succeed")
	_assert(Relations.kind_of(rock.relation) == Relations.WORLD, "Dropped item relation must be WORLD")
	_assert(not fixture.containers.get_container("backpack").item_ids.has(rock.instance_id), "Dropped item must leave backpack")
	_assert(Relations.transform_from_relation(rock.relation).origin.is_equal_approx(Vector3(2.0, 3.0, 4.0)), "World transform must survive relation conversion")


func _test_stack_merge_and_split() -> void:
	var fixture = _fixture()
	var first = fixture.items.create_item(
		"rock", 10, {}, Relations.container("backpack"), "Sample A"
	)
	fixture.containers.get_container("backpack").item_ids.append(first.instance_id)
	var second = fixture.items.create_item(
		"rock", 5, {}, Relations.world(), "Sample A"
	)
	var merge: Dictionary = fixture.transfer.move_item(second.instance_id, Relations.container("backpack"), "merge-1")
	_assert_success(merge, "Compatible stacks must merge")
	_assert(bool(merge.get("merged", false)), "Merge result must report merged=true")
	_assert(first.quantity == 15, "Merged stack quantity must be 15")
	_assert(fixture.items.get_item(second.instance_id) == null, "Merged source instance must be removed")
	var split: Dictionary = fixture.transfer.split_and_move(first.instance_id, 4, Relations.world(), "split-1")
	_assert_success(split, "Partial stack split must succeed")
	_assert(first.quantity == 11, "Source stack must retain remaining quantity")
	var new_item = fixture.items.get_item(String(split.get("new_item_id", "")))
	_assert(new_item != null and new_item.quantity == 4, "Split stack must preserve moved quantity")
	_assert(new_item != null and new_item.display_name == "Sample A", "Split stack must preserve instance display name")
	_assert(Relations.kind_of(new_item.relation) == Relations.WORLD, "Split output must reach requested relation")
	var differently_named = fixture.items.create_item(
		"rock", 1, {}, Relations.world(), "Sample B"
	)
	var separate_move: Dictionary = fixture.transfer.move_item(
		differently_named.instance_id,
		Relations.container("backpack"),
		"different-name"
	)
	_assert_success(separate_move, "Differently named stack must still move to container")
	_assert(not bool(separate_move.get("merged", false)), "Stacks with different display names must not merge")
	_assert(fixture.items.get_item(differently_named.instance_id) != null, "Differently named stack must preserve its identity")
	_assert_success(
		fixture.validator.validate_graph(),
		"Split transfer must leave relationship graph valid"
	)


func _test_nested_container_transfer() -> void:
	var fixture = _fixture()
	var crate = fixture.items.create_item("crate", 1, {"container": {"container_id": "crate_contents"}}, Relations.world())
	var contents = ContainerState.new({
		"container_id": "crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id,
		"slot_count": 4, "maximum_mass_kg": 50.0, "maximum_volume_l": 20.0,
	})
	fixture.containers.add_container(contents)
	var rock = fixture.items.create_item("rock", 3, {}, Relations.container("crate_contents"))
	contents.item_ids.append(rock.instance_id)
	var original_relation: Dictionary = rock.relation.duplicate(true)
	var pickup: Dictionary = fixture.transfer.move_item(crate.instance_id, Relations.container("backpack"), "crate-pickup")
	_assert_success(pickup, "Filled container must move as one item")
	_assert(rock.relation == original_relation, "Container contents relation must not change when parent moves")
	_assert(contents.item_ids == [rock.instance_id], "Filled container must retain exact contents")
	var drop: Dictionary = fixture.transfer.move_item(crate.instance_id, Relations.world(), "crate-drop")
	_assert_success(drop, "Filled container must drop as one item")
	_assert(rock.relation == original_relation, "Dropping parent must not reparent contents")


func _test_capacity_and_nesting_guards() -> void:
	var fixture = _fixture()
	var heavy = fixture.items.create_item("heavy", 1, {}, Relations.world())
	var mass_result: Dictionary = fixture.transfer.move_item(heavy.instance_id, Relations.container("backpack"), "heavy-pickup")
	_assert_error(mass_result, "MAXIMUM_MASS_EXCEEDED", "Backpack mass limit must be enforced")
	var crate = fixture.items.create_item("crate", 1, {"container": {"container_id": "crate_contents"}}, Relations.world())
	var contents = ContainerState.new({
		"container_id": "crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id,
		"slot_count": 2, "allow_nested_containers": false,
	})
	fixture.containers.add_container(contents)
	var self_insert: Dictionary = fixture.transfer.move_item(crate.instance_id, Relations.container("crate_contents"), "self-insert")
	_assert_error(self_insert, "RELATION_CYCLE", "Container must not contain itself")
	var second_crate = fixture.items.create_item("crate", 1, {"container": {"container_id": "crate_2_contents"}}, Relations.world())
	fixture.containers.add_container(ContainerState.new({
		"container_id": "crate_2_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": second_crate.instance_id,
	}))
	var nesting: Dictionary = fixture.transfer.move_item(second_crate.instance_id, Relations.container("crate_contents"), "nested-forbidden")
	_assert_error(nesting, "NESTED_CONTAINERS_FORBIDDEN", "Container nesting policy must be enforced")


func _test_operation_idempotency() -> void:
	var fixture = _fixture()
	var rock = fixture.items.create_item("rock", 1, {}, Relations.world())
	var first: Dictionary = fixture.transfer.move_item(rock.instance_id, Relations.container("backpack"), "same-operation")
	var second: Dictionary = fixture.transfer.move_item(rock.instance_id, Relations.world(), "same-operation")
	_assert(first == second, "Repeated operation_id must return original result")
	_assert(Relations.kind_of(rock.relation) == Relations.CONTAINER, "Repeated operation must not mutate item twice")
	_assert(fixture.containers.get_container("backpack").item_ids.count(rock.instance_id) == 1, "Idempotent transfer must not duplicate membership")


func _test_same_container_move_and_operation_validation() -> void:
	var fixture = _fixture()
	var rock = fixture.items.create_item(
		"rock",
		2,
		{},
		Relations.container("backpack")
	)
	fixture.containers.get_container("backpack").item_ids.append(
		rock.instance_id
	)
	var move_inside: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.container("backpack", 3),
		"same-container-slot"
	)
	_assert_success(
		move_inside,
		"Moving inside the same container must not count mass twice"
	)
	_assert(
		fixture.containers.get_container("backpack").item_ids.count(
			rock.instance_id
		) == 1,
		"Same-container move must preserve one membership"
	)
	_assert(
		is_equal_approx(
			fixture.mass.container_mass_kg("backpack"),
			4.0
		),
		"Same-container move must preserve exact mass"
	)
	var empty_operation: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.world(),
		""
	)
	_assert_error(
		empty_operation,
		"OPERATION_ID_REQUIRED",
		"Transfer must require operation_id"
	)
	var empty_split_operation: Dictionary = (
		fixture.transfer.split_and_move(
			rock.instance_id,
			1,
			Relations.world(),
			""
		)
	)
	_assert_error(
		empty_split_operation,
		"OPERATION_ID_REQUIRED",
		"Split transfer must require operation_id"
	)


func _test_graph_integrity_guards() -> void:
	var missing_membership = _fixture()
	var orphaned = missing_membership.items.create_item(
		"rock",
		1,
		{},
		Relations.container("backpack")
	)
	var missing_result: Dictionary = (
		missing_membership.validator.validate_graph()
	)
	_assert_error(
		missing_result,
		"ITEM_CONTAINER_MEMBERSHIP_MISSING",
		"Graph validation must detect missing container membership"
	)

	var duplicate_membership = _fixture()
	var duplicated = duplicate_membership.items.create_item(
		"rock",
		1,
		{},
		Relations.container("backpack")
	)
	var duplicate_container = (
		duplicate_membership.containers.get_container("backpack")
	)
	duplicate_container.item_ids.append(duplicated.instance_id)
	duplicate_container.item_ids.append(duplicated.instance_id)
	var duplicate_result: Dictionary = (
		duplicate_membership.validator.validate_graph()
	)
	_assert_error(
		duplicate_result,
		"DUPLICATE_CONTAINER_MEMBERSHIP",
		"Graph validation must detect duplicate membership"
	)

	var missing_item = _fixture()
	missing_item.containers.get_container(
		"backpack"
	).item_ids.append("missing_item")
	var missing_item_result: Dictionary = (
		missing_item.validator.validate_graph()
	)
	_assert_error(
		missing_item_result,
		"CONTAINER_MEMBER_NOT_FOUND",
		"Graph validation must reject unknown member IDs"
	)



func _test_attachment_roundtrip() -> void:
	var fixture = _fixture()
	var chassis = fixture.items.create_item("chassis", 1, {}, Relations.world())
	var lidar = fixture.items.create_item("lidar", 1, {}, Relations.container("backpack"))
	fixture.containers.get_container("backpack").item_ids.append(lidar.instance_id)
	fixture.attachments.register_socket("rover", chassis.instance_id, "roof", ["lidar"])
	var attach: Dictionary = fixture.attachments.attach(lidar.instance_id, "rover", "roof", "attach-1")
	_assert_success(attach, "Compatible module must attach")
	_assert(Relations.kind_of(lidar.relation) == Relations.ATTACHMENT, "Attached item relation must be ATTACHMENT")
	_assert(not fixture.containers.get_container("backpack").item_ids.has(lidar.instance_id), "Attached module must leave backpack")
	var second_lidar = fixture.items.create_item("lidar", 1, {}, Relations.world())
	var occupied: Dictionary = fixture.attachments.attach(second_lidar.instance_id, "rover", "roof", "attach-occupied")
	_assert_error(occupied, "SOCKET_OCCUPIED", "Occupied socket must reject another item")
	var detach: Dictionary = fixture.attachments.detach_to_container(lidar.instance_id, "backpack", "detach-1")
	_assert_success(detach, "Attached module must detach to container")
	_assert(Relations.kind_of(lidar.relation) == Relations.CONTAINER, "Detached item relation must be CONTAINER")
	_assert(lidar.instance_id == String(detach.get("item_id", "")), "Attachment roundtrip must preserve instance identity")
	var reattach: Dictionary = fixture.attachments.attach(
		lidar.instance_id,
		"rover",
		"roof",
		"attach-2"
	)
	_assert_success(reattach, "Module must attach again after detachment")
	var direct_world_move: Dictionary = fixture.transfer.move_item(
		lidar.instance_id,
		Relations.world(),
		"direct-attached-to-world"
	)
	_assert_success(
		direct_world_move,
		"Direct relation transfer must be able to remove attached item"
	)
	_assert(
		String(
			fixture.attachments.get_socket_state(
				"rover",
				"roof"
			).get("item_id", "")
		).is_empty(),
		"Socket state must follow relation changes even outside attachment facade"
	)


func _test_mixed_relation_cycle_guard() -> void:
	var fixture = _fixture()
	var parent = fixture.items.create_item("crate", 1, {"container": {"container_id": "parent_contents"}}, Relations.world())
	fixture.containers.add_container(ContainerState.new({
		"container_id": "parent_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": parent.instance_id,
	}))
	var child = fixture.items.create_item("chassis", 1, {}, Relations.container("parent_contents"))
	fixture.containers.get_container("parent_contents").item_ids.append(child.instance_id)
	var cycle: Dictionary = fixture.transfer.move_item(parent.instance_id, Relations.attachment("assembly", child.instance_id, "socket"), "mixed-cycle")
	_assert_error(cycle, "RELATION_CYCLE", "Containment + attachment cycle must be rejected")
	_assert_success(fixture.validator.validate_graph(), "Valid graph must pass full validation after rejected cycle")


func _test_mass_and_external_volume() -> void:
	var fixture = _fixture()
	var crate = fixture.items.create_item("crate", 1, {"container": {"container_id": "crate_contents"}}, Relations.container("backpack"))
	fixture.containers.get_container("backpack").item_ids.append(crate.instance_id)
	fixture.containers.add_container(ContainerState.new({
		"container_id": "crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id,
	}))
	var rocks = fixture.items.create_item("rock", 3, {}, Relations.container("crate_contents"))
	fixture.containers.get_container("crate_contents").item_ids.append(rocks.instance_id)
	_assert(is_equal_approx(fixture.mass.item_recursive_mass_kg(crate.instance_id), 10.0), "Container recursive mass must include own 4 kg + contents 6 kg")
	_assert(is_equal_approx(fixture.mass.container_mass_kg("backpack"), 10.0), "Parent container mass must include nested contents")
	_assert(is_equal_approx(fixture.mass.container_direct_volume_l("backpack"), 30.0), "Parent volume must use container external volume only")


func _test_serialization_roundtrip() -> void:
	var fixture = _fixture()
	var crate = fixture.items.create_item("crate", 1, {"container": {"container_id": "crate_contents"}}, Relations.container("backpack"))
	fixture.containers.get_container("backpack").item_ids.append(crate.instance_id)
	fixture.containers.add_container(ContainerState.new({
		"container_id": "crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id,
	}))
	var rock = fixture.items.create_item("rock", 2, {}, Relations.container("crate_contents"))
	fixture.containers.get_container("crate_contents").item_ids.append(rock.instance_id)
	var item_data: Dictionary = fixture.items.to_dict()
	var container_data: Dictionary = fixture.containers.to_dict()
	var restored = Factory.create()
	restored.items.load_dict(item_data)
	restored.containers.load_dict(container_data)
	var restored_crate = restored.items.get_item(crate.instance_id)
	var restored_rock = restored.items.get_item(rock.instance_id)
	_assert(restored_crate != null and restored_rock != null, "Serialization must preserve item identities")
	_assert(restored_crate.get_owned_container_id() == "crate_contents", "Serialization must preserve container component")
	_assert(String(restored_rock.relation.get("container_id", "")) == "crate_contents", "Serialization must preserve nested location")
	_assert(restored.containers.get_container("crate_contents").item_ids == [rock.instance_id], "Serialization must preserve container membership")
	_assert_success(restored.validator.validate_graph(), "Restored relationship graph must be valid")


func _test_representation_lifecycle() -> void:
	var fixture = _fixture()
	var world_root = Node3D.new()
	var attachment_root = Node3D.new()
	get_root().add_child(world_root)
	get_root().add_child(attachment_root)
	var presenter = Presenter.new()
	get_root().add_child(presenter)
	presenter.setup(fixture.items, world_root, attachment_root)
	var chassis = fixture.items.create_item("chassis", 1, {}, Relations.world())
	var lidar = fixture.items.create_item("lidar", 1, {}, Relations.world())
	presenter.synchronize_item(lidar.instance_id)
	_assert(
		presenter.get_world_node(lidar.instance_id) is RigidBody3D,
		"WORLD relation must create RigidBody3D"
	)
	var loose_body: RigidBody3D = presenter.get_world_node(
		lidar.instance_id
	)
	loose_body.position = Vector3(7.0, 8.0, 9.0)
	loose_body.linear_velocity = Vector3(1.0, 2.0, 3.0)
	_assert(
		presenter.capture_world_state(lidar.instance_id),
		"World presenter must capture physics state into the domain"
	)
	_assert(
		Relations.transform_from_relation(
			lidar.relation
		).origin.is_equal_approx(Vector3(7.0, 8.0, 9.0)),
		"Captured world transform must update ItemInstance"
	)
	fixture.transfer.move_item(
		lidar.instance_id,
		Relations.container("backpack"),
		"visual-pickup"
	)
	presenter.synchronize_item(lidar.instance_id)
	await process_frame
	_assert(presenter.get_world_node(lidar.instance_id) == null, "CONTAINER relation must remove world physics")
	fixture.attachments.register_socket("rover", chassis.instance_id, "roof", ["lidar"])
	fixture.attachments.attach(lidar.instance_id, "rover", "roof", "visual-attach")
	presenter.synchronize_item(lidar.instance_id)
	_assert(presenter.get_world_node(lidar.instance_id) == null, "ATTACHMENT relation must not create loose world body")
	_assert(presenter.get_attached_node(lidar.instance_id) is Node3D, "ATTACHMENT relation must create attached presentation")
	var attached_node: Node3D = presenter.get_attached_node(lidar.instance_id)
	_assert(not attached_node is PhysicsBody3D, "Rigid attachment presentation must not own independent physics")
	fixture.attachments.detach_to_world(lidar.instance_id, Transform3D.IDENTITY, Vector3.ZERO, "visual-detach")
	presenter.synchronize_item(lidar.instance_id)
	await process_frame
	_assert(presenter.get_attached_node(lidar.instance_id) == null, "Detaching to world must remove attached presentation")
	_assert(presenter.get_world_node(lidar.instance_id) is RigidBody3D, "Detaching to world must restore physics")
	presenter.queue_free()
	world_root.queue_free()
	attachment_root.queue_free()


func _fixture() -> Dictionary:
	var fixture = Factory.create()
	fixture.items.register_definition(Definition.new({
		"id": "rock", "display_name": "Rock", "max_stack": 50,
		"unit_mass_kg": 2.0, "external_volume_l": 0.8, "tags": ["rock", "resource"],
	}))
	fixture.items.register_definition(Definition.new({
		"id": "crate", "display_name": "Crate", "max_stack": 1,
		"unit_mass_kg": 4.0, "external_volume_l": 30.0, "tags": ["container"],
	}))
	fixture.items.register_definition(Definition.new({
		"id": "lidar", "display_name": "Lidar", "max_stack": 1,
		"unit_mass_kg": 3.0, "external_volume_l": 5.0, "tags": ["lidar", "mountable"],
	}))
	fixture.items.register_definition(Definition.new({
		"id": "chassis", "display_name": "Chassis", "max_stack": 1,
		"unit_mass_kg": 100.0, "external_volume_l": 300.0,
		"tags": ["assembly_root"],
		"metadata": {"presentation_mode": "EXTERNAL"},
	}))
	fixture.items.register_definition(Definition.new({
		"id": "heavy", "display_name": "Heavy", "max_stack": 1,
		"unit_mass_kg": 100.0, "external_volume_l": 10.0, "tags": ["cargo"],
	}))
	fixture.containers.add_container(ContainerState.new({
		"container_id": "backpack", "owner_kind": "ACTOR", "owner_id": "player",
		"slot_count": 8, "maximum_mass_kg": 80.0, "maximum_volume_l": 100.0,
		"allow_nested_containers": true, "maximum_nested_depth": 2,
	}))
	return fixture


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s; result=%s" % [message, str(result)])


func _assert_error(result: Dictionary, expected_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected_code, "%s; expected=%s result=%s" % [message, expected_code, str(result)])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
