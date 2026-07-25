extends Node

signal partition_window_changed(snapshot: Dictionary)


const LunarCubeAddressScript = preload(
    "res://scripts/world/coordinates/lunar_cube_address.gd"
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

# Six cube-sphere faces. Each face contains 48×48 zones.
# A zone is roughly 55–60 km wide near the face centre.
const ZONES_PER_FACE: int = 48

# Each zone is split into 32×32 logical simulation chunks.
# Their nominal size is about 1.7–1.9 km.
const CHUNKS_PER_ZONE: int = 32

const WARM_ZONE_RADIUS: int = 1
const ACTIVE_CHUNK_RADIUS: int = 2
const WARM_CHUNK_RADIUS: int = 3

var moon_world
var moon_radius: float = 1_737_400.0
var zones: Dictionary = {}
var frame_counter: int = 0

var active_zone_key: String = ""
var active_chunk_key: String = ""
var active_zone_short_name: String = "-"
var active_chunk_short_name: String = "-"
var observer_is_spectator: bool = false
var last_partition_signature: String = ""


func setup(moon_reference) -> void:
    moon_world = moon_reference
    if moon_world != null and moon_world.has_method("get_moon_radius"):
        moon_radius = moon_world.get_moon_radius()


func update_observer(
    world_position: Vector3,
    spectator_mode: bool
) -> void:
    if world_position.length_squared() < 1.0:
        return

    frame_counter += 1
    observer_is_spectator = spectator_mode
    var direction := world_position.normalized()
    var address: Dictionary = LunarCubeAddressScript.direction_to_address(
        direction,
        ZONES_PER_FACE,
        CHUNKS_PER_ZONE
    )

    var current_zone_id = _make_zone_id(address)
    var current_chunk_id = _make_chunk_id(current_zone_id, address)
    var next_zone_key: String = current_zone_id.key()
    var next_chunk_key: String = current_chunk_id.key()
    var next_signature: String = "%s|%s|%s" % [
        next_zone_key,
        next_chunk_key,
        "spectator" if spectator_mode else "player",
    ]
    if next_signature == last_partition_signature:
        return

    last_partition_signature = next_signature
    active_zone_key = next_zone_key
    active_chunk_key = next_chunk_key
    active_zone_short_name = current_zone_id.short_name()
    active_chunk_short_name = current_chunk_id.short_name()

    var desired_zone_states: Dictionary = {}
    var desired_chunk_states: Dictionary = {}
    var current_zone_center := LunarCubeAddressScript.zone_center_direction(
        current_zone_id.face,
        current_zone_id.x,
        current_zone_id.y,
        ZONES_PER_FACE
    )

    # Keep an active zone and a warm 3×3 zone neighbourhood. Sampling
    # directions instead of adding grid indices also works across cube faces.
    for zone_dy in range(-WARM_ZONE_RADIUS, WARM_ZONE_RADIUS + 1):
        for zone_dx in range(-WARM_ZONE_RADIUS, WARM_ZONE_RADIUS + 1):
            var sample_direction := LunarCubeAddressScript.offset_direction(
                current_zone_center,
                float(zone_dx) * get_nominal_zone_size_m(),
                float(zone_dy) * get_nominal_zone_size_m(),
                moon_radius
            )
            var sample_address: Dictionary = LunarCubeAddressScript.direction_to_address(
                sample_direction,
                ZONES_PER_FACE,
                CHUNKS_PER_ZONE
            )
            var zone_id = _make_zone_id(sample_address)
            desired_zone_states[zone_id.key()] = (
                LunarZoneRuntimeScript.Activity.ACTIVE
                if zone_id.key() == active_zone_key
                else LunarZoneRuntimeScript.Activity.WARM
            )

    # Build a warm 7×7 chunk neighbourhood. The centre 5×5 is active.
    # Offsets are mapped back to cube-sphere addresses, so chunk windows can
    # cross zone and cube-face boundaries without special cases here.
    for chunk_dy in range(-WARM_CHUNK_RADIUS, WARM_CHUNK_RADIUS + 1):
        for chunk_dx in range(-WARM_CHUNK_RADIUS, WARM_CHUNK_RADIUS + 1):
            var sample_direction := LunarCubeAddressScript.offset_direction(
                direction,
                float(chunk_dx) * get_nominal_chunk_size_m(),
                float(chunk_dy) * get_nominal_chunk_size_m(),
                moon_radius
            )
            var sample_address: Dictionary = LunarCubeAddressScript.direction_to_address(
                sample_direction,
                ZONES_PER_FACE,
                CHUNKS_PER_ZONE
            )
            var zone_id = _make_zone_id(sample_address)
            var chunk_id = _make_chunk_id(zone_id, sample_address)
            var distance: int = maxi(absi(chunk_dx), absi(chunk_dy))
            var chunk_activity: int = (
                LunarChunkRuntimeScript.Activity.ACTIVE
                if distance <= ACTIVE_CHUNK_RADIUS
                else LunarChunkRuntimeScript.Activity.WARM
            )
            desired_chunk_states[chunk_id.key()] = {
                "zone_id": zone_id,
                "chunk_id": chunk_id,
                "center_direction": LunarCubeAddressScript.chunk_center_direction(
                    zone_id.face,
                    zone_id.x,
                    zone_id.y,
                    chunk_id.x,
                    chunk_id.y,
                    ZONES_PER_FACE,
                    CHUNKS_PER_ZONE
                ),
                "activity": chunk_activity,
            }
            var current_zone_activity: int = desired_zone_states.get(
                zone_id.key(),
                LunarZoneRuntimeScript.Activity.WARM
            )
            if chunk_activity == LunarChunkRuntimeScript.Activity.ACTIVE:
                current_zone_activity = LunarZoneRuntimeScript.Activity.ACTIVE
            desired_zone_states[zone_id.key()] = current_zone_activity

    _apply_zone_window(desired_zone_states)
    _apply_chunk_window(desired_chunk_states)
    partition_window_changed.emit(create_partition_snapshot())


func _apply_zone_window(desired_zone_states: Dictionary) -> void:
    for zone_key in zones.keys():
        if not desired_zone_states.has(zone_key):
            zones.erase(zone_key)

    for zone_key in desired_zone_states.keys():
        var activity: int = desired_zone_states[zone_key]
        if not zones.has(zone_key):
            var parts: PackedStringArray = String(zone_key).split("/")
            var zone_id = LunarZoneIdScript.new()
            zone_id.setup(
                int(parts[1].trim_prefix("f")),
                int(parts[2]),
                int(parts[3])
            )
            var runtime = LunarZoneRuntimeScript.new()
            runtime.setup(
                zone_id,
                LunarCubeAddressScript.zone_center_direction(
                    zone_id.face,
                    zone_id.x,
                    zone_id.y,
                    ZONES_PER_FACE
                )
            )
            zones[zone_key] = runtime
        zones[zone_key].set_activity(activity, frame_counter)


func _apply_chunk_window(desired_chunk_states: Dictionary) -> void:
    for zone_value in zones.values():
        for chunk_key in zone_value.chunks.keys():
            if not desired_chunk_states.has(chunk_key):
                zone_value.chunks.erase(chunk_key)

    for chunk_key in desired_chunk_states.keys():
        var desired: Dictionary = desired_chunk_states[chunk_key]
        var zone_id = desired["zone_id"]
        var zone_key: String = zone_id.key()
        if not zones.has(zone_key):
            continue
        var zone_runtime = zones[zone_key]
        if not zone_runtime.chunks.has(chunk_key):
            var chunk_runtime = LunarChunkRuntimeScript.new()
            chunk_runtime.setup(
                desired["chunk_id"],
                desired["center_direction"]
            )
            zone_runtime.chunks[chunk_key] = chunk_runtime
        zone_runtime.chunks[chunk_key].set_activity(
            desired["activity"],
            frame_counter
        )


func _make_zone_id(address: Dictionary):
    var result = LunarZoneIdScript.new()
    result.setup(
        int(address["face"]),
        int(address["zone_x"]),
        int(address["zone_y"])
    )
    return result


func _make_chunk_id(zone_id, address: Dictionary):
    var result = LunarChunkIdScript.new()
    result.setup(
        zone_id,
        int(address["chunk_x"]),
        int(address["chunk_y"])
    )
    return result


func resolve_partition(world_position: Vector3) -> Dictionary:
    if world_position.length_squared() < 1.0:
        return {}
    var address: Dictionary = LunarCubeAddressScript.direction_to_address(
        world_position.normalized(),
        ZONES_PER_FACE,
        CHUNKS_PER_ZONE
    )
    var zone_id = _make_zone_id(address)
    var chunk_id = _make_chunk_id(zone_id, address)
    return {
        "face": int(address["face"]),
        "zone_x": int(address["zone_x"]),
        "zone_y": int(address["zone_y"]),
        "chunk_x": int(address["chunk_x"]),
        "chunk_y": int(address["chunk_y"]),
        "zone_id": zone_id.key(),
        "zone_name": zone_id.short_name(),
        "chunk_id": chunk_id.key(),
        "chunk_name": chunk_id.short_name(),
    }


func offset_surface_position(
    world_position: Vector3,
    east_offset_m: float,
    north_offset_m: float,
    altitude_offset_m: float = 0.0
) -> Vector3:
    if world_position.length_squared() < 1.0:
        return Vector3.ZERO
    var direction := LunarCubeAddressScript.offset_direction(
        world_position.normalized(),
        east_offset_m,
        north_offset_m,
        moon_radius
    )
    var radius: float = world_position.length() + altitude_offset_m
    return direction * radius


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
    return moon_radius * (PI * 0.5) / float(ZONES_PER_FACE)


func get_nominal_chunk_size_m() -> float:
    return get_nominal_zone_size_m() / float(CHUNKS_PER_ZONE)


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
        "%s | %s | zones=%d(active=%d) chunks=%d active=%d warm=%d"
        % [
            active_zone_short_name,
            active_chunk_short_name,
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
    return {
        "schema": "lunar.partition.v1",
        "active_zone": active_zone_key,
        "active_chunk": active_chunk_key,
        "observer": "spectator" if observer_is_spectator else "player",
        "zones": zone_snapshots,
    }
