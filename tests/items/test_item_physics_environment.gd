extends SceneTree

const Factory = preload(
	"res://scripts/items/services/item_domain_factory.gd"
)
const Definition = preload(
	"res://scripts/items/domain/item_definition.gd"
)
const ContainerState = preload(
	"res://scripts/containers/container_state.gd"
)
const Relations = preload(
	"res://scripts/items/domain/item_relations.gd"
)
const Presenter = preload(
	"res://scripts/items/presentation/item_representation_system.gd"
)
const GravityField = preload(
	"res://scripts/simulation/gravity/gravity_field.gd"
)
const GravityBodyDriver = preload(
	"res://scripts/simulation/gravity/gravity_body_driver.gd"
)

const MOON_RADIUS_M: float = 1_737_400.0
const MOON_MU_M3_S2: float = 4_890_065_191_200.0

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var domain: Dictionary = Factory.create()
	_register_definitions(domain.items)
	var crate = domain.items.create_item(
		"crate",
		1,
		{"container": {"container_id": "crate_contents"}},
		Relations.world(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)))
	)
	var crate_contents = ContainerState.new({
		"container_id": "crate_contents",
		"owner_kind": "ITEM_INSTANCE",
		"owner_id": crate.instance_id,
		"slot_count": 8,
		"maximum_mass_kg": 100.0,
		"maximum_volume_l": 100.0,
	})
	_assert(domain.containers.add_container(crate_contents), "Crate container must register")
	var inner_bag = domain.items.create_item(
		"bag",
		1,
		{"container": {"container_id": "bag_contents"}},
		Relations.container("crate_contents")
	)
	crate_contents.item_ids.append(inner_bag.instance_id)
	var bag_contents = ContainerState.new({
		"container_id": "bag_contents",
		"owner_kind": "ITEM_INSTANCE",
		"owner_id": inner_bag.instance_id,
		"slot_count": 8,
		"maximum_mass_kg": 100.0,
		"maximum_volume_l": 100.0,
	})
	_assert(domain.containers.add_container(bag_contents), "Nested bag container must register")
	var rocks = domain.items.create_item(
		"rock",
		3,
		{},
		Relations.container("bag_contents")
	)
	bag_contents.item_ids.append(rocks.instance_id)

	var gravity_field = GravityField.new()
	_assert(
		gravity_field.setup_static_sources([{
			"id": "moon",
			"radius_m": MOON_RADIUS_M,
			"gravitational_parameter_m3_s2": MOON_MU_M3_S2,
			"center_m": [0.0, -MOON_RADIUS_M, 0.0],
		}], "item-test/local"),
		"Item test gravity field must initialize"
	)
	var root = Node3D.new()
	var world_root = Node3D.new()
	var attachment_root = Node3D.new()
	root.add_child(world_root)
	root.add_child(attachment_root)
	get_root().add_child(root)
	var presenter = Presenter.new()
	root.add_child(presenter)
	presenter.setup(
		domain.items,
		world_root,
		attachment_root,
		false,
		domain.mass,
		gravity_field,
		"item-test/local"
	)
	presenter.synchronize_all()

	var crate_body: RigidBody3D = presenter.get_world_node(crate.instance_id)
	_assert(crate_body != null, "WORLD crate must create a rigid body")
	_assert_close(
		presenter.get_world_physical_mass_kg(crate.instance_id),
		11.0,
		0.000001,
		"Filled crate physical mass must include shell, nested bag and bag contents"
	)
	var surface_acceleration: Vector3 = presenter.get_world_gravity_acceleration_mps2(
		crate.instance_id
	)
	_assert(
		surface_acceleration.y < -1.619,
		"Item gravity must point down toward the local Moon centre"
	)
	_assert_close(
		crate_body.constant_force.length(),
		surface_acceleration.length() * 11.0,
		0.00001,
		"Rigid-body force must equal recursive mass times local acceleration"
	)
	_assert_close(
		crate_body.gravity_scale,
		0.0,
		0.000001,
		"Item body must not also receive Godot global gravity"
	)

	crate_body.position = Vector3(0.0, MOON_RADIUS_M, 0.0)
	var driver = crate_body.get_node_or_null("GravityBodyDriver")
	_assert(driver != null, "WORLD item must own a dynamic gravity driver")
	var high_acceleration: Vector3 = driver.apply_now()
	_assert_close(
		high_acceleration.length(),
		0.405,
		0.00001,
		"Item gravity must weaken to one quarter at two Moon radii"
	)

	world_root.rotation.z = PI * 0.5
	var rotated_scene_acceleration: Vector3 = driver.apply_now()
	_assert(
		rotated_scene_acceleration.x > 0.404
		and absf(rotated_scene_acceleration.y) < 0.00001,
		"Generic gravity driver must rotate frame acceleration into scene coordinates"
	)
	world_root.rotation = Vector3.ZERO
	high_acceleration = driver.apply_now()

	# The driver must also work while a generic body hierarchy is being built
	# and no Node3D in that hierarchy has entered SceneTree yet.
	var detached_root = Node3D.new()
	detached_root.rotation.z = PI * 0.5
	var detached_holder = Node3D.new()
	detached_holder.position = Vector3(100.0, 0.0, 0.0)
	detached_root.add_child(detached_holder)
	var detached_body = RigidBody3D.new()
	detached_body.mass = 2.0
	detached_body.position = Vector3(-100.0, MOON_RADIUS_M, 0.0)
	detached_holder.add_child(detached_body)
	var detached_driver = GravityBodyDriver.new()
	detached_body.add_child(detached_driver)
	_assert(
		not detached_body.is_inside_tree(),
		"Detached gravity regression must execute before SceneTree attachment"
	)
	detached_driver.setup(
		detached_body,
		gravity_field,
		"item-test/local",
		"",
		detached_root
	)
	var detached_acceleration: Vector3 = detached_driver.apply_now()
	_assert(
		detached_acceleration.x > 0.404
		and absf(detached_acceleration.y) < 0.00001,
		"Detached nested gravity driver must resolve position and frame rotation"
	)
	_assert_close(
		detached_body.constant_force.length(),
		detached_acceleration.length() * 2.0,
		0.00001,
		"Detached gravity force must use the configured body mass"
	)
	detached_root.free()

	var move_result: Dictionary = domain.transfer.move_item(
		rocks.instance_id,
		Relations.world(Transform3D(Basis.IDENTITY, Vector3(2.0, 2.0, 0.0))),
		"remove-crate-contents",
		int(rocks.revision)
	)
	_assert(bool(move_result.get("success", false)), "Moving contents out of crate must succeed")
	presenter.synchronize_item(rocks.instance_id)
	_assert_close(
		presenter.get_world_physical_mass_kg(crate.instance_id),
		5.0,
		0.000001,
		"Crate physical mass must retain the nested bag after its rocks leave"
	)
	_assert_close(
		crate_body.constant_force.length(),
		high_acceleration.length() * 5.0,
		0.00001,
		"Gravity force must refresh after recursive physical mass changes"
	)

	root.queue_free()
	_finish()


func _register_definitions(items) -> void:
	items.register_definition(Definition.new({
		"id": "rock",
		"display_name": "Rock",
		"max_stack": 50,
		"unit_mass_kg": 2.0,
		"external_volume_l": 0.8,
		"tags": ["rock"],
	}))
	items.register_definition(Definition.new({
		"id": "bag",
		"display_name": "Bag",
		"max_stack": 1,
		"unit_mass_kg": 1.0,
		"external_volume_l": 5.0,
		"tags": ["container"],
	}))
	items.register_definition(Definition.new({
		"id": "crate",
		"display_name": "Crate",
		"max_stack": 1,
		"unit_mass_kg": 4.0,
		"external_volume_l": 30.0,
		"tags": ["container"],
	}))


func _assert_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_assert(
		absf(actual - expected) <= tolerance,
		"%s; actual=%s expected=%s" % [message, actual, expected]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Item gravity and recursive physical mass: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"Item gravity and recursive physical mass: FAIL (%d failures, %d assertions)"
		% [failures.size(), assertions]
	)
	quit(1)
