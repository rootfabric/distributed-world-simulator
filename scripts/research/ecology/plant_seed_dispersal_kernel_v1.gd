extends RefCounted

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_seed_dispersal_kernel.v1"
const CONTEXT_SCHEMA := "distributed_world_simulator.ecology.evo1_seed_transport_context.v1"
const VERSION := "1.0.0"
const DEFAULT_PACKET_COUNT := 16
const MAX_PACKET_COUNT := 64
const LONG_TAIL_FRACTION := 0.15
const EPSILON := 0.000000000001

static func create_context(
	transport_vector: Vector2,
	turbulence: float,
	domain_bounds: Rect2 = Rect2()
) -> Dictionary:
	if not _finite_vector(transport_vector) or not is_finite(turbulence):
		return {}
	if transport_vector.length() > 1.0 + EPSILON or turbulence < 0.0 or turbulence > 1.0:
		return {}
	if domain_bounds.size.x < 0.0 or domain_bounds.size.y < 0.0:
		return {}
	var x_bounded := domain_bounds.size.x > EPSILON
	var y_bounded := domain_bounds.size.y > EPSILON
	if x_bounded != y_bounded:
		return {}
	var result := {
		"schema": CONTEXT_SCHEMA,
		"version": VERSION,
		"transport_vector": transport_vector,
		"turbulence": turbulence,
		"has_domain_bounds": x_bounded and y_bounded,
		"domain_bounds": domain_bounds,
	}
	result["checksum"] = _context_checksum(result)
	return result

static func validate_context(context: Dictionary) -> bool:
	if String(context.get("schema", "")) != CONTEXT_SCHEMA or String(context.get("version", "")) != VERSION:
		return false
	var vector := Vector2(context.get("transport_vector", Vector2(INF, INF)))
	var turbulence := float(context.get("turbulence", -1.0))
	var bounds := Rect2(context.get("domain_bounds", Rect2()))
	if not _finite_vector(vector) or vector.length() > 1.0 + EPSILON:
		return false
	if not is_finite(turbulence) or turbulence < 0.0 or turbulence > 1.0:
		return false
	if bounds.size.x < 0.0 or bounds.size.y < 0.0:
		return false
	var expected_bounds := bounds.size.x > EPSILON and bounds.size.y > EPSILON
	if bool(context.get("has_domain_bounds", false)) != expected_bounds:
		return false
	return String(context.get("checksum", "")) == _context_checksum(context)

static func disperse(
	genome: Dictionary,
	lineage_id: String,
	reproduction_event: String,
	source_position: Vector2,
	emitted_seed_count: int,
	release_height_m: float,
	context: Dictionary,
	requested_packet_count: int = DEFAULT_PACKET_COUNT
) -> Dictionary:
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if lineage_id.is_empty() or lineage_id != lineage_id.strip_edges():
		return {}
	if reproduction_event.is_empty() or reproduction_event != reproduction_event.strip_edges():
		return {}
	if not _finite_vector(source_position):
		return {}
	if emitted_seed_count <= 0 or emitted_seed_count > 1000000:
		return {}
	if not is_finite(release_height_m) or release_height_m <= 0.0 or release_height_m > 1000.0:
		return {}
	if requested_packet_count <= 0 or requested_packet_count > MAX_PACKET_COUNT:
		return {}
	if not validate_context(context):
		return {}
	var bounds := Rect2(context["domain_bounds"])
	if bool(context["has_domain_bounds"]) and not bounds.has_point(source_position):
		return {}

	var packet_count := mini(requested_packet_count, emitted_seed_count)
	var base_count := emitted_seed_count / packet_count
	var remainder := emitted_seed_count % packet_count
	var inherited_distance := float(genome["seed_dispersal_distance_m"])
	var release_height_factor := sqrt(release_height_m)
	var effective_distance := inherited_distance * release_height_factor
	var transport_vector := Vector2(context["transport_vector"])
	var turbulence := float(context["turbulence"])
	var transport_strength := clampf(transport_vector.length(), 0.0, 1.0)
	var transport_direction := Vector2.ZERO if transport_strength <= EPSILON else transport_vector.normalized()
	var anisotropy := clampf(transport_strength * (1.0 - 0.50 * turbulence), 0.0, 0.90)
	var event_key := "%s|%s|%s|%.9f|%.9f" % [lineage_id, reproduction_event, String(genome["checksum"]), source_position.x, source_position.y]
	var phase := TAU * _unit_interval(event_key + "|phase")

	var packets: Array = []
	var inside_count := 0
	var outside_count := 0
	var local_count := 0
	var long_tail_count := 0
	var weighted_distance := 0.0
	var weighted_displacement := Vector2.ZERO
	var max_distance := 0.0

	for packet_index in range(packet_count):
		var seed_count := base_count + (1 if packet_index < remainder else 0)
		var stratum := (float(packet_index) + 0.5) / float(packet_count)
		var long_tail := stratum >= 1.0 - LONG_TAIL_FRACTION
		var radial_factor := _radial_factor(stratum, long_tail)
		var distance_jitter := (_unit_interval(event_key + "|distance|" + str(packet_index)) - 0.5) * 0.16 * turbulence
		radial_factor *= maxf(0.05, 1.0 + distance_jitter)
		var angle_jitter := (_unit_interval(event_key + "|angle|" + str(packet_index)) - 0.5) * (TAU / float(packet_count)) * turbulence
		var isotropic_angle := phase + TAU * stratum + angle_jitter
		var isotropic_direction := Vector2(cos(isotropic_angle), sin(isotropic_angle))
		var direction := isotropic_direction
		if transport_strength > EPSILON:
			direction = (isotropic_direction * (1.0 - anisotropy) + transport_direction * anisotropy).normalized()
		var nominal_distance := effective_distance * radial_factor
		var displacement := direction * nominal_distance
		var destination := source_position + displacement
		var actual_distance := displacement.length()
		var outside_domain := bool(context["has_domain_bounds"]) and not bounds.has_point(destination)
		if outside_domain:
			outside_count += seed_count
		else:
			inside_count += seed_count
		if long_tail:
			long_tail_count += seed_count
		else:
			local_count += seed_count
		weighted_distance += actual_distance * float(seed_count)
		weighted_displacement += displacement * float(seed_count)
		max_distance = maxf(max_distance, actual_distance)
		var packet := {
			"schema": SCHEMA + ".packet",
			"version": VERSION,
			"packet_index": packet_index,
			"seed_count": seed_count,
			"lineage_id": lineage_id,
			"genome_checksum": String(genome["checksum"]),
			"reproduction_event": reproduction_event,
			"source_position": source_position,
			"destination_position": destination,
			"displacement": displacement,
			"distance_m": actual_distance,
			"long_tail": long_tail,
			"outside_domain": outside_domain,
		}
		packet["packet_hash"] = _packet_hash(packet)
		packets.append(packet)

	var mean_distance := weighted_distance / float(emitted_seed_count)
	var mean_displacement := weighted_displacement / float(emitted_seed_count)
	var downwind_projection := 0.0
	if transport_strength > EPSILON:
		downwind_projection = mean_displacement.dot(transport_direction)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"genome_checksum": String(genome["checksum"]),
		"lineage_id": lineage_id,
		"reproduction_event": reproduction_event,
		"source_position": source_position,
		"release_height_m": release_height_m,
		"release_height_factor": release_height_factor,
		"inherited_seed_dispersal_distance_m": inherited_distance,
		"effective_seed_dispersal_distance_m": effective_distance,
		"context_checksum": String(context["checksum"]),
		"transport_vector": transport_vector,
		"transport_anisotropy": anisotropy,
		"emitted_seed_count": emitted_seed_count,
		"transported_seed_count": inside_count + outside_count,
		"inside_domain_seed_count": inside_count,
		"outside_domain_seed_count": outside_count,
		"local_seed_count": local_count,
		"long_tail_seed_count": long_tail_count,
		"packet_count": packet_count,
		"mean_distance_m": mean_distance,
		"max_distance_m": max_distance,
		"mean_displacement": mean_displacement,
		"downwind_projection_m": downwind_projection,
		"packets": packets,
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func compute_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("genome_checksum", "")),
		String(result.get("lineage_id", "")),
		String(result.get("reproduction_event", "")),
		_vector_token(Vector2(result.get("source_position", Vector2.ZERO))),
		"%.12f" % float(result.get("release_height_m", 0.0)),
		"%.12f" % float(result.get("effective_seed_dispersal_distance_m", 0.0)),
		String(result.get("context_checksum", "")),
		str(int(result.get("emitted_seed_count", 0))),
		str(int(result.get("inside_domain_seed_count", 0))),
		str(int(result.get("outside_domain_seed_count", 0))),
		str(int(result.get("local_seed_count", 0))),
		str(int(result.get("long_tail_seed_count", 0))),
		"%.12f" % float(result.get("mean_distance_m", 0.0)),
		"%.12f" % float(result.get("max_distance_m", 0.0)),
		_vector_token(Vector2(result.get("mean_displacement", Vector2.ZERO))),
		"%.12f" % float(result.get("downwind_projection_m", 0.0)),
	])
	for packet_value in Array(result.get("packets", [])):
		var packet: Dictionary = packet_value
		tokens.append(String(packet.get("packet_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _radial_factor(stratum: float, long_tail: bool) -> float:
	if long_tail:
		var q_tail := clampf((stratum - (1.0 - LONG_TAIL_FRACTION)) / LONG_TAIL_FRACTION, 0.0, 1.0 - EPSILON)
		return 2.0 + 2.0 * (-log(maxf(EPSILON, 1.0 - 0.90 * q_tail)))
	var q_local := clampf(stratum / (1.0 - LONG_TAIL_FRACTION), 0.0, 1.0 - EPSILON)
	return 0.15 + 0.75 * (-log(maxf(EPSILON, 1.0 - 0.85 * q_local)))

static func _packet_hash(packet: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(packet.get("schema", "")),
		VERSION,
		str(int(packet.get("packet_index", -1))),
		str(int(packet.get("seed_count", 0))),
		String(packet.get("lineage_id", "")),
		String(packet.get("genome_checksum", "")),
		String(packet.get("reproduction_event", "")),
		_vector_token(Vector2(packet.get("source_position", Vector2.ZERO))),
		_vector_token(Vector2(packet.get("destination_position", Vector2.ZERO))),
		"%.12f" % float(packet.get("distance_m", 0.0)),
		str(bool(packet.get("long_tail", false))),
		str(bool(packet.get("outside_domain", false))),
	])).sha256_text()

static func _context_checksum(context: Dictionary) -> String:
	var bounds := Rect2(context.get("domain_bounds", Rect2()))
	return "|".join(PackedStringArray([
		CONTEXT_SCHEMA,
		VERSION,
		_vector_token(Vector2(context.get("transport_vector", Vector2.ZERO))),
		"%.12f" % float(context.get("turbulence", 0.0)),
		str(bool(context.get("has_domain_bounds", false))),
		_vector_token(bounds.position),
		_vector_token(bounds.size),
	])).sha256_text()

static func _unit_interval(key: String) -> float:
	var value := key.sha256_text().substr(0, 12).hex_to_int()
	return float(value) / 281474976710655.0

static func _vector_token(value: Vector2) -> String:
	return "%.12f,%.12f" % [value.x, value.y]

static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
