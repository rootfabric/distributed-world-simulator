extends Node

signal partition_window_changed(snapshot: Dictionary)

const CubeSphereGridScript = preload(
	"res://scripts/simulation/partition/cube_sphere_grid.gd"
)
const LunarZoneIdScript = preload(
	"res://scripts/world/zones/lunar_zone_id.gd"
)
const LunarZoneRuntimeScript = preload(
	"res://scripts/world/zones/lunar_zone_runtime.gd"
)
const LunarChunkIdScript = preload(
	"res://scripts/world/chunks/lunar_chunk_id.gd"
)
const LunarChunkRuntimeScript = preload(
	"res://scripts/world/chunks/lunar_chunk_runtime.gd"
)
const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

const WARM_ZONE_RADIUS: int = 1
const ACTIVE_CHUNK_RADIUS: int = 2
const WARM_CHUNK_RADIUS: int = 3
const PRIMARY_INTEREST_SOURCE_ID: String = "primary_observer"

var moon_world
var partition_grid
var zones: Dictionary = {}
var frame_counter: int = 0
var universe_id: String = "main"
var instance_id: String = "persistent"
var space_id: String = "moon"
var partition_scheme: String = CubeSphereGridScript.DEFAULT_SCHEME_ID
var partition_scheme_revision: int = CubeSphereGridScript.DEFAULT_SCHEME_REVISION
var partition_frame_id: String = CubeSphereGridScript.DEFAULT_BODY_FRAME_ID
var authority_owner_id: String = "local-process"

var active_zone_key: String = ""
var active_chunk_key: String = ""
var active_zone_short_name: String = "-"
var active_chunk_short_name: String = "-"
var observer_is_spectator: bool = false
var last_partition_signature: String = ""
var interest_sources: Dictionary = {}


func setup(moon_reference, context: Dictionary = {}) -> bool:
	zones.clear()
	interest_sources.clear()
	frame_counter = 0
	active_zone_key = ""
	active_chunk_key = ""
	active_zone_short_name = "-"
	active_chunk_short_name = "-"
	last_partition_signature = ""
	moon_world = moon_reference
	observer_is_spectator = false
	universe_id = PartitionAddressScript.DEFAULT_UNIVERSE_ID
	instance_id = PartitionAddressScript.DEFAULT_INSTANCE_ID
	space_id = PartitionAddressScript.DEFAULT_SPACE_ID
	partition_scheme = CubeSphereGridScript.DEFAULT_SCHEME_ID
	partition_scheme_revision = CubeSphereGridScript.DEFAULT_SCHEME_REVISION
	partition_frame_id = CubeSphereGridScript.DEFAULT_BODY_FRAME_ID
	authority_owner_id = "local-process"
	universe_id = String(context.get("universe_id", universe_id)).strip_edges().to_lower()
	instance_id = String(context.get("instance_id", instance_id)).strip_edges().to_lower()
	space_id = String(context.get("space_id", space_id)).strip_edges().to_lower()
	authority_owner_id = String(context.get("authority_owner_id", authority_owner_id)).strip_edges()
	if not _setup_partition_grid(context):
		return false
	var identity_probe: Dictionary = partition_grid.create_partition_address(
		Vector3.RIGHT * partition_grid.body_radius_m,
		universe_id,
		instance_id,
		space_id
	)
	if identity_probe.is_empty():
		push_error(
			"Invalid partition namespace: universe=%s instance=%s space=%s"
			% [universe_id, instance_id, space_id]
		)
		partition_grid = null
		return false
	return true


func _setup_partition_grid(context: Dictionary) -> bool:
	var radius_m: float = CubeSphereGridScript.DEFAULT_BODY_RADIUS_M
	if moon_world != null and moon_world.has_method("get_moon_radius"):
		radius_m = float(moon_world.get_moon_radius())
	var grid_config: Dictionary = {
		"scheme_id": String(context.get(
			"partition_scheme",
			CubeSphereGridScript.DEFAULT_SCHEME_ID
		)),
		"scheme_revision": int(context.get(
			"partition_scheme_revision",
			CubeSphereGridScript.DEFAULT_SCHEME_REVISION
		)),
		"body_frame_id": String(context.get(
			"partition_frame_id",
			CubeSphereGridScript.DEFAULT_BODY_FRAME_ID
		)),
		"body_radius_m": float(context.get("body_radius_m", radius_m)),
		"zones_per_face": int(context.get(
			"zones_per_face",
			CubeSphereGridScript.DEFAULT_ZONES_PER_FACE
		)),
		"chunks_per_zone": int(context.get(
			"chunks_per_zone",
			CubeSphereGridScript.DEFAULT_CHUNKS_PER_ZONE
		)),
	}
	var config_path: String = String(context.get("partition_grid_config_path", ""))
	if not config_path.is_empty():
		var file_config: Dictionary = _load_partition_grid_config(config_path)
		for key in file_config.keys():
			grid_config[key] = file_config[key]
	var nested_config: Dictionary = context.get("partition_grid", {})
	for key in nested_config.keys():
		grid_config[key] = nested_config[key]
	partition_grid = CubeSphereGridScript.new()
	if not partition_grid.setup(grid_config):
		push_error("Invalid cube-sphere partition grid configuration: %s" % [grid_config])
		partition_grid = null
		return false
	partition_scheme = partition_grid.scheme_id
	partition_scheme_revision = partition_grid.scheme_revision
	partition_frame_id = partition_grid.body_frame_id
	return true


func _load_partition_grid_config(config_path: String) -> Dictionary:
	if not FileAccess.file_exists(config_path):
		push_error("Partition grid config does not exist: %s" % config_path)
		return {}
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("Partition grid config cannot be opened: %s" % config_path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Partition grid config must contain a JSON object: %s" % config_path)
		return {}
	if String(parsed.get("schema", CubeSphereGridScript.SCHEMA)) != CubeSphereGridScript.SCHEMA:
		push_error("Unsupported partition grid schema in %s" % config_path)
		return {}
	return parsed


func get_partition_grid_descriptor() -> Dictionary:
	return partition_grid.create_descriptor() if partition_grid != null else {}


func get_partition_scheme_revision() -> int:
	return partition_scheme_revision


func get_zones_per_face() -> int:
	return partition_grid.zones_per_face if partition_grid != null else 0


func get_chunks_per_zone() -> int:
	return partition_grid.chunks_per_zone if partition_grid != null else 0


func get_body_radius_m() -> float:
	return partition_grid.body_radius_m if partition_grid != null else 0.0


func update_observer(world_position: Vector3, spectator_mode: bool) -> void:
	update_interest_source(
		PRIMARY_INTEREST_SOURCE_ID,
		world_position,
		spectator_mode,
		true
	)


func update_interest_source(
	source_id: String,
	world_position: Vector3,
	spectator_mode: bool = false,
	is_primary: bool = false
) -> void:
	if source_id.is_empty() or world_position.length_squared() < 1.0:
		return
	interest_sources[source_id] = {
		"source_id": source_id,
		"world_position": world_position,
		"spectator_mode": spectator_mode,
		"is_primary": is_primary or source_id == PRIMARY_INTEREST_SOURCE_ID,
	}
	_rebuild_partition_window()


func remove_interest_source(source_id: String) -> void:
	if not interest_sources.erase(source_id):
		return
	if interest_sources.is_empty():
		clear_interest_sources()
		return
	_rebuild_partition_window()


func clear_interest_sources() -> void:
	interest_sources.clear()
	zones.clear()
	active_zone_key = ""
	active_chunk_key = ""
	active_zone_short_name = "-"
	active_chunk_short_name = "-"
	last_partition_signature = ""
	partition_window_changed.emit(create_partition_snapshot())


func get_interest_source_count() -> int:
	return interest_sources.size()


func _rebuild_partition_window() -> void:
	if interest_sources.is_empty():
		return
	var desired_zone_states: Dictionary = {}
	var desired_chunk_states: Dictionary = {}
	var signature_parts := PackedStringArray()
	var source_ids: Array = interest_sources.keys()
	source_ids.sort()
	var primary_assigned: bool = false
	for source_id_value in source_ids:
		var source_id: String = String(source_id_value)
		var source: Dictionary = interest_sources[source_id]
		var world_position: Vector3 = source.get("world_position", Vector3.ZERO)
		if world_position.length_squared() < 1.0:
			continue
		var direction: Vector3 = world_position.normalized()
		var address: Dictionary = partition_grid.direction_to_cell(direction)
		var current_zone_id = _make_zone_id(address)
		var current_chunk_id = _make_chunk_id(current_zone_id, address)
		var source_is_primary: bool = bool(source.get("is_primary", false))
		if source_is_primary or not primary_assigned:
			active_zone_key = current_zone_id.key()
			active_chunk_key = current_chunk_id.key()
			active_zone_short_name = current_zone_id.short_name()
			active_chunk_short_name = current_chunk_id.short_name()
			observer_is_spectator = bool(source.get("spectator_mode", false))
			primary_assigned = true
		signature_parts.append("%s:%s:%s" % [
			source_id,
			current_chunk_id.key(),
			"spectator" if bool(source.get("spectator_mode", false)) else "actor",
		])
		_append_interest_window(
			direction,
			current_zone_id,
			desired_zone_states,
			desired_chunk_states
		)
	var next_signature: String = "|".join(signature_parts)
	if next_signature == last_partition_signature:
		return
	last_partition_signature = next_signature
	frame_counter += 1
	_apply_zone_window(desired_zone_states)
	_apply_chunk_window(desired_chunk_states)
	partition_window_changed.emit(create_partition_snapshot())


func _append_interest_window(
	direction: Vector3,
	current_zone_id,
	desired_zone_states: Dictionary,
	desired_chunk_states: Dictionary
) -> void:
	for zone_dy in range(-WARM_ZONE_RADIUS, WARM_ZONE_RADIUS + 1):
		for zone_dx in range(-WARM_ZONE_RADIUS, WARM_ZONE_RADIUS + 1):
			var sample_address: Dictionary = partition_grid.offset_zone_cell(
				current_zone_id.face,
				current_zone_id.x,
				current_zone_id.y,
				zone_dx,
				zone_dy
			)
			if sample_address.is_empty():
				continue
			var zone_id = _make_zone_id(sample_address)
			var activity: int = (
				LunarZoneRuntimeScript.Activity.ACTIVE
				if zone_id.key() == current_zone_id.key()
				else LunarZoneRuntimeScript.Activity.WARM
			)
			desired_zone_states[zone_id.key()] = maxi(
				int(desired_zone_states.get(zone_id.key(), LunarZoneRuntimeScript.Activity.WARM)),
				activity
			)
	var current_chunk_address: Dictionary = partition_grid.direction_to_cell(direction)
	for chunk_dy in range(-WARM_CHUNK_RADIUS, WARM_CHUNK_RADIUS + 1):
		for chunk_dx in range(-WARM_CHUNK_RADIUS, WARM_CHUNK_RADIUS + 1):
			var sample_address: Dictionary = partition_grid.offset_chunk_cell(
				int(current_chunk_address.get("face", -1)),
				int(current_chunk_address.get("zone_x", -1)),
				int(current_chunk_address.get("zone_y", -1)),
				int(current_chunk_address.get("chunk_x", -1)),
				int(current_chunk_address.get("chunk_y", -1)),
				chunk_dx,
				chunk_dy
			)
			if sample_address.is_empty():
				continue
			var zone_id = _make_zone_id(sample_address)
			var chunk_id = _make_chunk_id(zone_id, sample_address)
			var distance: int = maxi(absi(chunk_dx), absi(chunk_dy))
			var chunk_activity: int = (
				LunarChunkRuntimeScript.Activity.ACTIVE
				if distance <= ACTIVE_CHUNK_RADIUS
				else LunarChunkRuntimeScript.Activity.WARM
			)
			var existing: Dictionary = desired_chunk_states.get(chunk_id.key(), {})
			if existing.is_empty() or chunk_activity > int(existing.get("activity", -1)):
				desired_chunk_states[chunk_id.key()] = {
					"zone_id": zone_id,
					"chunk_id": chunk_id,
					"center_direction": partition_grid.chunk_center_direction(
						zone_id.face,
						zone_id.x,
						zone_id.y,
						chunk_id.x,
						chunk_id.y
					),
					"activity": chunk_activity,
				}
			if chunk_activity == LunarChunkRuntimeScript.Activity.ACTIVE:
				desired_zone_states[zone_id.key()] = LunarZoneRuntimeScript.Activity.ACTIVE


func _apply_zone_window(desired_zone_states: Dictionary) -> void:
	for zone_key in zones.keys():
		if not desired_zone_states.has(zone_key):
			zones.erase(zone_key)
	for zone_key_value in desired_zone_states.keys():
		var zone_key: String = String(zone_key_value)
		var activity: int = int(desired_zone_states[zone_key])
		if not zones.has(zone_key):
			var parsed: Dictionary = PartitionAddressScript.parse(zone_key, _partition_defaults())
			if parsed.is_empty():
				continue
			var zone_id = LunarZoneIdScript.new()
			zone_id.setup(
				int(parsed["face"]),
				int(parsed["zone_x"]),
				int(parsed["zone_y"]),
				String(parsed["universe_id"]),
				String(parsed["space_id"]),
				String(parsed["partition_scheme"]),
				String(parsed["instance_id"]),
				int(parsed.get("partition_scheme_revision", partition_scheme_revision))
			)
			var runtime = LunarZoneRuntimeScript.new()
			runtime.setup(
				zone_id,
				partition_grid.zone_center_direction(
					zone_id.face,
					zone_id.x,
					zone_id.y
				)
			)
			runtime.owner_token = authority_owner_id
			zones[zone_key] = runtime
		zones[zone_key].set_activity(activity, frame_counter)


func _apply_chunk_window(desired_chunk_states: Dictionary) -> void:
	for zone_value in zones.values():
		for chunk_key in zone_value.chunks.keys():
			if not desired_chunk_states.has(chunk_key):
				zone_value.chunks.erase(chunk_key)
	for chunk_key_value in desired_chunk_states.keys():
		var chunk_key: String = String(chunk_key_value)
		var desired: Dictionary = desired_chunk_states[chunk_key]
		var zone_id = desired["zone_id"]
		var zone_key: String = zone_id.key()
		if not zones.has(zone_key):
			continue
		var zone_runtime = zones[zone_key]
		if not zone_runtime.chunks.has(chunk_key):
			var chunk_runtime = LunarChunkRuntimeScript.new()
			chunk_runtime.setup(desired["chunk_id"], desired["center_direction"])
			chunk_runtime.owner_token = authority_owner_id
			zone_runtime.chunks[chunk_key] = chunk_runtime
		zone_runtime.chunks[chunk_key].set_activity(
			int(desired["activity"]),
			frame_counter
		)


func _make_zone_id(address: Dictionary):
	var result = LunarZoneIdScript.new()
	result.setup(
		int(address["face"]),
		int(address["zone_x"]),
		int(address["zone_y"]),
		universe_id,
		space_id,
		partition_scheme,
		instance_id,
		partition_scheme_revision
	)
	return result


func _make_chunk_id(zone_id, address: Dictionary):
	var result = LunarChunkIdScript.new()
	result.setup(zone_id, int(address["chunk_x"]), int(address["chunk_y"]))
	return result


func get_partition_frame_id() -> String:
	return partition_frame_id


func get_universe_id() -> String:
	return universe_id


func get_partition_instance_id() -> String:
	return instance_id


func resolve_partition(world_position: Vector3) -> Dictionary:
	if world_position.length_squared() < 1.0:
		return {}
	var address: Dictionary = partition_grid.direction_to_cell(
		world_position
	)
	var zone_id = _make_zone_id(address)
	var chunk_id = _make_chunk_id(zone_id, address)
	var partition_address: Dictionary = partition_grid.create_partition_address(
		world_position,
		universe_id,
		instance_id,
		space_id
	)
	return {
		"schema": PartitionAddressScript.SCHEMA,
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
		"partition_frame_id": partition_frame_id,
		"face": int(address["face"]),
		"zone_x": int(address["zone_x"]),
		"zone_y": int(address["zone_y"]),
		"chunk_x": int(address["chunk_x"]),
		"chunk_y": int(address["chunk_y"]),
		"zone_id": zone_id.key(),
		"zone_name": zone_id.short_name(),
		"chunk_id": chunk_id.key(),
		"chunk_name": chunk_id.short_name(),
		"partition_address": partition_address,
		"authority_owner_id": authority_owner_id,
	}


func offset_surface_position(
	world_position: Vector3,
	east_offset_m: float,
	north_offset_m: float,
	altitude_offset_m: float = 0.0
) -> Vector3:
	if world_position.length_squared() < 1.0:
		return Vector3.ZERO
	return partition_grid.offset_surface_position(
		world_position,
		east_offset_m,
		north_offset_m,
		altitude_offset_m
	)


func reset_loaded_entity_counts() -> void:
	for zone_value in zones.values():
		for chunk_value in zone_value.chunks.values():
			chunk_value.entity_count = 0


func increment_loaded_chunk_entity_count(chunk_key: String) -> void:
	for zone_value in zones.values():
		if zone_value.chunks.has(chunk_key):
			zone_value.chunks[chunk_key].entity_count += 1
			return


func get_nominal_zone_size_m() -> float:
	return partition_grid.get_nominal_zone_size_m() if partition_grid != null else 0.0


func get_nominal_chunk_size_m() -> float:
	return partition_grid.get_nominal_chunk_size_m() if partition_grid != null else 0.0


func get_loaded_zone_count() -> int:
	return zones.size()


func get_active_zone_count() -> int:
	var result: int = 0
	for zone_value in zones.values():
		if zone_value.is_active():
			result += 1
	return result


func get_loaded_chunk_count() -> int:
	var result: int = 0
	for zone_value in zones.values():
		result += zone_value.chunks.size()
	return result


func get_active_chunk_count() -> int:
	var result: int = 0
	for zone_value in zones.values():
		result += zone_value.active_chunk_count()
	return result


func get_warm_chunk_count() -> int:
	return get_loaded_chunk_count() - get_active_chunk_count()


func get_active_zone_name() -> String:
	return active_zone_short_name


func get_active_chunk_name() -> String:
	return active_chunk_short_name


func get_runtime_summary() -> String:
	return (
		"%s | %s | interests=%d zones=%d(active=%d) chunks=%d active=%d warm=%d"
		% [
			active_zone_short_name,
			active_chunk_short_name,
			interest_sources.size(),
			get_loaded_zone_count(),
			get_active_zone_count(),
			get_loaded_chunk_count(),
			get_active_chunk_count(),
			get_warm_chunk_count(),
		]
	)


func create_partition_snapshot() -> Dictionary:
	var zone_snapshots: Array[Dictionary] = []
	for zone_value in zones.values():
		var chunks: Array[Dictionary] = []
		for chunk_value in zone_value.chunks.values():
			chunks.append({
				"chunk_id": chunk_value.chunk_id.key(),
				"activity": chunk_value.activity,
				"owner_token": chunk_value.owner_token,
				"terrain_revision": chunk_value.terrain_revision,
				"entity_count": chunk_value.entity_count,
			})
		zone_snapshots.append({
			"zone_id": zone_value.zone_id.key(),
			"activity": zone_value.activity,
			"owner_token": zone_value.owner_token,
			"chunks": chunks,
		})
	var source_snapshots: Array[Dictionary] = []
	for source_id_value in interest_sources.keys():
		var source_id: String = String(source_id_value)
		var source: Dictionary = interest_sources[source_id]
		var position: Vector3 = source.get("world_position", Vector3.ZERO)
		source_snapshots.append({
			"source_id": source_id,
			"world_position": [position.x, position.y, position.z],
			"spectator_mode": bool(source.get("spectator_mode", false)),
			"is_primary": bool(source.get("is_primary", false)),
		})
	return {
		"schema": "planet_simulator.partition_window.v2",
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
		"partition_frame_id": partition_frame_id,
		"partition_grid": get_partition_grid_descriptor(),
		"authority_owner_id": authority_owner_id,
		"active_zone": active_zone_key,
		"active_chunk": active_chunk_key,
		"observer": "spectator" if observer_is_spectator else "player",
		"interest_sources": source_snapshots,
		"zones": zone_snapshots,
	}


func _partition_defaults() -> Dictionary:
	return {
		"universe_id": universe_id,
		"instance_id": instance_id,
		"space_id": space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
	}
