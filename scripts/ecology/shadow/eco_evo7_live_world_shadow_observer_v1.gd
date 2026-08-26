extends Node

## Runtime observer for integration/shadow branches. It attaches to the real
## ProceduralEarthWorld and refreshes a read-only shadow observation whenever
## the local Earth surface is rebuilt. No result is written back to world state.

const Shadow = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")

var earth_world
var simulation_clock
var enabled := false
var last_observation: Dictionary = {}
var observation_counter := 0

func setup(earth_world_ref, simulation_clock_ref = null) -> bool:
	earth_world = earth_world_ref
	simulation_clock = simulation_clock_ref
	var config := Shadow.load_config()
	enabled = bool(config.get("enabled", false)) and String(config.get("mode", "")) == Shadow.MODE
	if not enabled or earth_world == null:
		return false
	if earth_world.has_signal("earth_rebuilt") and not earth_world.earth_rebuilt.is_connected(_on_earth_rebuilt):
		earth_world.earth_rebuilt.connect(_on_earth_rebuilt)
	refresh()
	return not last_observation.is_empty()

func refresh() -> Dictionary:
	if not enabled or earth_world == null:
		return {}
	observation_counter += 1
	var direction: Vector3 = earth_world.get("surface_center_direction")
	if direction.length_squared() < 0.5 and earth_world.has_method("get_canonical_spawn_direction"):
		direction = earth_world.call("get_canonical_spawn_direction")
	var world_time := 0.0
	if simulation_clock != null and simulation_clock.has_method("get_time_seconds"):
		world_time = float(simulation_clock.get_time_seconds())
	var observation_id := "earth-live-shadow-%08d" % observation_counter
	var observed := Shadow.observe_earth_world(earth_world, direction, world_time, observation_id)
	last_observation = Dictionary(observed.get("details", {})).duplicate(true) if bool(observed.get("success", false)) else {}
	return last_observation.duplicate(true)

func get_last_observation() -> Dictionary:
	return last_observation.duplicate(true)

func request_authoritative_write(surface: String, payload: Dictionary = {}) -> Dictionary:
	return Shadow.request_authoritative_write(surface, payload)

func _on_earth_rebuilt(_summary: Dictionary) -> void:
	refresh()
