extends Node3D

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Bubble = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const Presenter = preload("res://scripts/world/matter/lunar_matter_bubble_presenter.gd")
const ItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const Gate = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd")
const Router = preload("res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd")
const Delivery = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd")
const Slice = preload("res://scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd")

const PLAYER := "miner"
const ACTOR := "player/miner"
const PRODUCT_AUTHORITY := "authority/p7-7-playground"
const PRODUCT_EPOCH := 1
const MATTER_OWNER := "authority/p7-7-matter-a"
const MATTER_EPOCH := 1
const REGION_A := "matter-region/p7-7-a"

@export var drill_radius_m := 0.75
@export var drill_depth_m := 3.0
@export var max_aim_distance_m := 40.0
@export var energy_budget_j := 1000000000.0

var _bubble = null
var _presenter = null
var _graph = null
var _gate = null
var _router = null
var _delivery = null
var _slice = null
var _camera: Camera3D
var _status: Label
var _tool_id := ""
var _sequence := 0
var _player_port = null
var _last_dig_result: Dictionary = {}


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
		if authority_id != PRODUCT_AUTHORITY or authority_epoch != PRODUCT_EPOCH:
			return MatterUtils.failure("P7_7_PLAYGROUND_SM1_TUPLE_MISMATCH")
		return MatterUtils.success()


class RegionalGate extends RefCounted:
	func authorize_mutation(_request: Dictionary) -> Dictionary:
		return MatterUtils.success({"region_id": REGION_A})

	func owner_id() -> String:
		return MATTER_OWNER

	func authority_epoch() -> int:
		return MATTER_EPOCH


class RegionResolver extends RefCounted:
	func resolve_brick_address(_address: Dictionary) -> Dictionary:
		return {"region_id": REGION_A}


class ReservationInterlock extends RefCounted:
	func validate_handoff(_region_id: String) -> Dictionary:
		return MatterUtils.success()

	func reserved_transaction(_region_id: String) -> Dictionary:
		return {}


class MW10Forbidden extends RefCounted:
	var calls := 0

	func execute_transaction(
		_plan: Dictionary,
		_transition_prefix: String,
		_server_tick: int
	) -> Dictionary:
		calls += 1
		return MatterUtils.failure("P7_7_PLAYGROUND_MW10_FORBIDDEN_IN_SINGLE_REGION_A")


func _ready() -> void:
	_build_environment()
	_build_ui()
	var setup := _configure_runtime()
	if not bool(setup.get("success", false)):
		_set_status("P7.7-A setup failed: %s" % String(setup.get("error_code", "UNKNOWN")))
		return
	_set_status(
		"P7.7-A ready. Canonical Matter aim + single-region MW4 + material + visible rebuild.\n"
		+ "Left click: dig | WASD/Q/E: camera | Shift: boost"
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton 			and event.button_index == MOUSE_BUTTON_LEFT 			and event.pressed:
		_execute_dig()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _camera == null:
		return
	var speed := 8.0 * delta
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 4.0
	var basis := _camera.global_basis
	var motion := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		motion -= basis.z
	if Input.is_key_pressed(KEY_S):
		motion += basis.z
	if Input.is_key_pressed(KEY_A):
		motion -= basis.x
	if Input.is_key_pressed(KEY_D):
		motion += basis.x
	if Input.is_key_pressed(KEY_Q):
		motion -= basis.y
	if Input.is_key_pressed(KEY_E):
		motion += basis.y
	if motion.length_squared() > 0.0:
		_camera.position += motion.normalized() * speed
	_update_player_position()


func world_to_render(world_position: Vector3) -> Vector3:
	if _bubble == null:
		return world_position
	return world_position - _bubble.anchor_body_fixed_m()


func render_to_world(render_position: Vector3) -> Vector3:
	if _bubble == null:
		return render_position
	return _bubble.anchor_body_fixed_m() + render_position


func execute_single_region_dig_for_test() -> Dictionary:
	_execute_dig()
	return playground_report()


func playground_report() -> Dictionary:
	var graph_snapshot: Dictionary = _graph.create_snapshot() if _graph != null else {}
	var store_hash := ""
	if _bubble != null and _bubble.snapshot_store() != null \
			and _bubble.snapshot_store().has_method("content_hash"):
		store_hash = String(_bubble.snapshot_store().content_hash())
	return {
		"configured": _slice != null and _presenter != null and _graph != null,
		"tool_id": _tool_id,
		"tool_equipped": _graph.has_equipped_mining_tool(PLAYER) if _graph != null else false,
		"matter_store_hash": store_hash,
		"item_graph_revision": int(graph_snapshot.get("revision", -1)),
		"item_graph_checksum": String(graph_snapshot.get("checksum", "")),
		"presenter_count": _presenter.presenter_count() if _presenter != null else 0,
		"last_dig_result": _last_dig_result.duplicate(true),
	}


func contract_report() -> Dictionary:
	return {
		"schema": "planet_simulator.p7_7_digging_playground_a.v1",
		"scope": "P7_7_A_SINGLE_REGION_VISIBLE_DIG",
		"canonical_state_owned": false,
		"terrain_truth_owned": false,
		"item_graph_owned": false,
		"aim_owner": "CONTINUOUS_MATTER_QUERY",
		"mutation_owner": "P7_1_TO_MW4",
		"route_owner": "P7_6",
		"material_owner": "P7_3_TO_CANONICAL_ITEM_GRAPH",
		"presentation_owner": "LUNAR_MATTER_BUBBLE_PRESENTER",
		"mw10_allowed": false,
	}


func _configure_runtime() -> Dictionary:
	_bubble = Bubble.new()
	var bubble_setup: Dictionary = _bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": 1737425.0,
		"half_extent_m": 32.0,
		"mutation_level": 2,
		"presentation_level": 2,
		"max_level": 3,
		"brick_interior_resolution": 8,
		"ghost_border_samples": 1,
	})
	if not bool(bubble_setup.get("success", false)):
		return bubble_setup

	_presenter = Presenter.new()
	_presenter.name = "CanonicalMatterPresenter"
	add_child(_presenter)
	var presenter_setup: Dictionary = _presenter.configure(_bubble, self, true)
	if not bool(presenter_setup.get("success", false)):
		return presenter_setup

	_graph = ItemGraph.new()
	var graph_setup: Dictionary = _graph.setup("authority/p7-7-item-graph", 1)
	if not bool(graph_setup.get("success", false)):
		return graph_setup
	_graph.ensure_player(PLAYER)
	var created: Dictionary = _graph.apply_server_output(
		"operation/p7-7/playground-tool",
		PLAYER,
		"item/tool/mining",
		1,
		"source/p7-7/playground"
	)
	if not bool(created.get("success", false)):
		return created
	_tool_id = String(created.get("details", {}).get("output_item_id", ""))
	if _tool_id.is_empty():
		return MatterUtils.failure("P7_7_PLAYGROUND_TOOL_ID_MISSING")
	var equipped: Dictionary = _graph.execute(
		PLAYER,
		1,
		"operation/p7-7/playground-equip",
		"item.equip",
		{"item_id": _tool_id, "slot_id": "tool/main"}
	)
	if not bool(equipped.get("success", false)):
		return equipped

	_player_port = GameplayPort.new()
	var regional := RegionalGate.new()
	_gate = Gate.new()
	var gate_setup: Dictionary = _gate.configure(
		_player_port,
		_graph,
		SM1Port.new(),
		regional,
		PRODUCT_AUTHORITY,
		PRODUCT_EPOCH,
		50.0,
		Callable(self, "_project_player_position")
	)
	if not bool(gate_setup.get("success", false)):
		return gate_setup

	_router = Router.new()
	var router_setup: Dictionary = _router.configure(
		_gate,
		RegionResolver.new(),
		Callable(self, "_execute_single_region"),
		Callable(self, "_execute_actor_handoff_forbidden"),
		MW10Forbidden.new(),
		ReservationInterlock.new()
	)
	if not bool(router_setup.get("success", false)):
		return router_setup

	_delivery = Delivery.new()
	var delivery_setup: Dictionary = _delivery.configure(
		_bubble.excavation_service(),
		_graph
	)
	if not bool(delivery_setup.get("success", false)):
		return delivery_setup

	_slice = Slice.new()
	var slice_setup: Dictionary = _slice.configure(
		_router,
		_delivery,
		Callable(self, "_invalidate_visible_representation")
	)
	if not bool(slice_setup.get("success", false)):
		return slice_setup

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.position = Vector3(0.0, 8.0, 14.0)
	add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_update_player_position()
	return MatterUtils.success(contract_report())


func _execute_dig() -> void:
	if _slice == null or _camera == null:
		return
	_update_player_position()
	var origin_body_fixed := render_to_world(_camera.global_position)
	var direction := -_camera.global_basis.z.normalized()
	var query_result: Dictionary = _bubble.query_service().raycast(
		origin_body_fixed,
		direction,
		max_aim_distance_m,
		_bubble.mutation_level(),
		0.2,
		0.15,
		512
	)
	if not bool(query_result.get("success", false)):
		_set_status("Aim query rejected: %s" % String(query_result.get("error_code", "UNKNOWN")))
		return
	var query_details: Dictionary = Dictionary(query_result.get("details", {}))
	if not bool(query_details.get("hit", false)):
		_set_status("Aim query: no canonical Matter surface hit.")
		return
	var hit_body_fixed: Vector3 = query_details["position_m"]
	_sequence += 1
	var request: Dictionary = _bubble.create_excavation_request(
		"operation/p7-7/playground-%06d" % _sequence,
		ACTOR,
		_tool_id,
		hit_body_fixed - direction * 0.25,
		hit_body_fixed + direction * drill_depth_m,
		drill_radius_m,
		energy_budget_j,
		_sequence
	)
	if request.is_empty():
		_set_status("Canonical excavation request planning failed.")
		return
	var result: Dictionary = _slice.execute_aimed_dig({
		"query_result": query_result,
		"request": request,
		"mw10_plan": {},
		"server_tick": _sequence,
		"transition_prefix": "transition/p7-7/playground-%06d" % _sequence,
	})
	if not bool(result.get("success", false)):
		_set_status("Dig rejected: %s" % String(result.get("error_code", "UNKNOWN")))
		return
	_last_dig_result = result.duplicate(true)
	var details: Dictionary = result.get("details", {})
	var delivery_details: Dictionary = Dictionary(details.get("material_delivery", {}))
	var item_delivery: Dictionary = Dictionary(delivery_details.get("delivery", {}))
	_set_status(
		"P7.7-A COMMITTED\n"
		+ "route=%s | MW10=%s | changed=%d | removed=%.3f kg\n" % [
			String(details.get("route", "")),
			str(bool(details.get("mw10_invoked", true))),
			int(details.get("changed_brick_count", 0)),
			float(details.get("removed_mass_kg", 0.0)),
		]
		+ "ItemGraph output=%d | replay=%s | presenters=%d" % [
			int(item_delivery.get("output_quantity", 0)),
			str(bool(item_delivery.get("replay", false))),
			_presenter.presenter_count(),
		]
	)


func _execute_single_region(request: Dictionary) -> Dictionary:
	var authorized: Dictionary = _gate.authorize_mutation(request)
	if not bool(authorized.get("success", false)):
		return authorized
	var result: Dictionary = _bubble.execute(request)
	if String(result.get("status", "")) != "COMMITTED":
		return MatterUtils.failure(
			"P7_7_PLAYGROUND_MW4_EXECUTION_NOT_COMMITTED",
			{"matter_result": result}
		)
	return MatterUtils.success({"matter_result": result})


func _execute_actor_handoff_forbidden(
	_region_id: String,
	_context: Dictionary
) -> Dictionary:
	return MatterUtils.failure("P7_7_PLAYGROUND_ACTOR_HANDOFF_OUTSIDE_A_SCOPE")


func _invalidate_visible_representation(_addresses: Array) -> Dictionary:
	if _presenter == null:
		return MatterUtils.failure("P7_7_PLAYGROUND_PRESENTER_REQUIRED")
	return _presenter.rebuild_all()


func _project_player_position(
	player: Dictionary,
	_request: Dictionary
) -> Dictionary:
	var position: Dictionary = player.get("position", {})
	return MatterUtils.success({
		"position_m": [
			float(position.get("x", 0.0)),
			float(position.get("y", 0.0)),
			float(position.get("z", 0.0)),
		],
	})


func _update_player_position() -> void:
	if _player_port == null or _camera == null:
		return
	_player_port.position_body_fixed_m = render_to_world(_camera.global_position)


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.018, 0.025, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.2, 0.22, 0.26, 1.0)
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	layer.add_child(panel)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)


func _set_status(value: String) -> void:
	if _status != null:
		_status.text = value
