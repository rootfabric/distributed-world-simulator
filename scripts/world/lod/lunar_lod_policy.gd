extends RefCounted

# Central source of geometry sizes, transition altitudes and streaming policy.
# MoonWorld owns mesh generation; this object owns only LOD decisions.

const GLOBAL_SEGMENTS: int = 160
const GLOBAL_RINGS: int = 80

const ULTRA_RADIUS: float = 280.0
const ULTRA_RINGS: int = 136
const LOCAL_RADIUS: float = 14_000.0
const LOCAL_OUTER_RINGS: int = 96
const LOCAL_SEGMENTS: int = 256

const REGIONAL_RADIUS: float = 520_000.0
const REGIONAL_RINGS: int = 64
const REGIONAL_SEGMENTS: int = 144

const LOCAL_EXIT_ALTITUDE: float = 14_000.0
const LOCAL_ENTER_ALTITUDE: float = 10_000.0
const REGIONAL_EXIT_ALTITUDE: float = 650_000.0
const REGIONAL_ENTER_ALTITUDE: float = 540_000.0

const SPECTATOR_ULTRA_ALTITUDE: float = 1_200.0
const SPECTATOR_LOCAL_ALTITUDE: float = 14_000.0
const SPECTATOR_MEDIUM_ALTITUDE: float = 190_000.0
const SPECTATOR_ULTRA_RECENTER: float = 115.0
const SPECTATOR_LOCAL_RECENTER: float = 1_250.0
const SPECTATOR_MEDIUM_RECENTER: float = 19_000.0
const SPECTATOR_HIGH_RECENTER: float = 66_000.0


func update_state(current_lod: int, altitude: float) -> int:
	var next_lod: int = current_lod
	if current_lod == 0:
		if altitude > LOCAL_EXIT_ALTITUDE:
			next_lod = 1
	elif current_lod == 1:
		if altitude < LOCAL_ENTER_ALTITUDE:
			next_lod = 0
		elif altitude > REGIONAL_EXIT_ALTITUDE:
			next_lod = 2
	else:
		if altitude < REGIONAL_ENTER_ALTITUDE:
			next_lod = 1
	return next_lod


func spectator_recenter_distance(altitude: float) -> float:
	if altitude <= SPECTATOR_ULTRA_ALTITUDE:
		return SPECTATOR_ULTRA_RECENTER
	if altitude <= SPECTATOR_LOCAL_ALTITUDE:
		var local_t: float = inverse_lerp(
			SPECTATOR_ULTRA_ALTITUDE,
			SPECTATOR_LOCAL_ALTITUDE,
			altitude
		)
		return lerpf(SPECTATOR_ULTRA_RECENTER, SPECTATOR_LOCAL_RECENTER, local_t)
	if altitude <= SPECTATOR_MEDIUM_ALTITUDE:
		var medium_t: float = inverse_lerp(
			SPECTATOR_LOCAL_ALTITUDE,
			SPECTATOR_MEDIUM_ALTITUDE,
			altitude
		)
		return lerpf(SPECTATOR_LOCAL_RECENTER, SPECTATOR_MEDIUM_RECENTER, medium_t)
	return SPECTATOR_HIGH_RECENTER


func build_local_ring_radii() -> PackedFloat64Array:
	var radii := PackedFloat64Array()
	for ring_index in range(1, ULTRA_RINGS + 1):
		var t: float = float(ring_index) / float(ULTRA_RINGS)
		radii.append(ULTRA_RADIUS * pow(t, 1.08))
	for ring_index in range(1, LOCAL_OUTER_RINGS + 1):
		var t: float = float(ring_index) / float(LOCAL_OUTER_RINGS)
		radii.append(lerpf(ULTRA_RADIUS, LOCAL_RADIUS, pow(t, 1.72)))
	return radii


func layer_stack_name(lod: int) -> String:
	match lod:
		0:
			return "ULTRA 0–280 м → LOCAL 14 км → REGIONAL 520 км → GLOBAL"
		1:
			return "REGIONAL 520 км → GLOBAL"
		_:
			return "GLOBAL UV-сфера"


func detail_name(lod: int) -> String:
	if lod != 0:
		return "Планетарный LOD: кратеры + maria/highlands материал"
	return "PHOTO-NEAR: микрорельеф 280 м, normal map, 6 слоёв камней"
