extends RefCounted

const HASH_MODULUS: int = 2147483647
const COORDINATE_MODULUS: int = 104729
const HASH_SCALE: float = 1.0 / 2147483646.0


static func hash_ratio(x: int, y: int, z: int, seed: int, channel: int = 0) -> float:
	var wrapped_x: int = _positive_mod(x, COORDINATE_MODULUS)
	var wrapped_y: int = _positive_mod(y, COORDINATE_MODULUS)
	var wrapped_z: int = _positive_mod(z, COORDINATE_MODULUS)
	var wrapped_seed: int = _positive_mod(seed, HASH_MODULUS)
	var wrapped_channel: int = _positive_mod(channel, COORDINATE_MODULUS)
	var value: int = _positive_mod(
		wrapped_x * 73856093
		+ wrapped_y * 19349663
		+ wrapped_z * 83492791
		+ wrapped_seed * 31
		+ wrapped_channel * 265443576,
		HASH_MODULUS
	)
	value = _positive_mod(value * 48271 + 12820163, HASH_MODULUS)
	value = _positive_mod(value * 69621 + 9076337, HASH_MODULUS)
	value = _positive_mod(value * 40699 + 104729, HASH_MODULUS)
	return float(value) * HASH_SCALE


static func signed_hash(x: int, y: int, z: int, seed: int, channel: int = 0) -> float:
	return hash_ratio(x, y, z, seed, channel) * 2.0 - 1.0


static func value_noise_3d(position_m: Vector3, frequency_per_m: float, seed: int, channel: int = 0) -> float:
	if frequency_per_m <= 0.0 or not is_finite(frequency_per_m):
		return 0.0
	var scaled: Vector3 = position_m * frequency_per_m
	var x0: int = floori(scaled.x)
	var y0: int = floori(scaled.y)
	var z0: int = floori(scaled.z)
	var tx: float = _fade(scaled.x - float(x0))
	var ty: float = _fade(scaled.y - float(y0))
	var tz: float = _fade(scaled.z - float(z0))
	var x00: float = lerpf(
		signed_hash(x0, y0, z0, seed, channel),
		signed_hash(x0 + 1, y0, z0, seed, channel),
		tx
	)
	var x10: float = lerpf(
		signed_hash(x0, y0 + 1, z0, seed, channel),
		signed_hash(x0 + 1, y0 + 1, z0, seed, channel),
		tx
	)
	var x01: float = lerpf(
		signed_hash(x0, y0, z0 + 1, seed, channel),
		signed_hash(x0 + 1, y0, z0 + 1, seed, channel),
		tx
	)
	var x11: float = lerpf(
		signed_hash(x0, y0 + 1, z0 + 1, seed, channel),
		signed_hash(x0 + 1, y0 + 1, z0 + 1, seed, channel),
		tx
	)
	var y0_value: float = lerpf(x00, x10, ty)
	var y1_value: float = lerpf(x01, x11, ty)
	return lerpf(y0_value, y1_value, tz)


static func fractal_noise_3d(
	position_m: Vector3,
	frequency_per_m: float,
	seed: int,
	channel: int,
	octaves: int = 3,
	lacunarity: float = 2.0,
	gain: float = 0.5
) -> float:
	if octaves <= 0 or frequency_per_m <= 0.0:
		return 0.0
	var frequency: float = frequency_per_m
	var amplitude: float = 1.0
	var total: float = 0.0
	var amplitude_sum: float = 0.0
	for octave in range(octaves):
		total += value_noise_3d(position_m, frequency, seed, channel + octave * 101) * amplitude
		amplitude_sum += amplitude
		frequency *= lacunarity
		amplitude *= gain
	if amplitude_sum <= 0.0:
		return 0.0
	return total / amplitude_sum


static func _fade(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


static func _positive_mod(value: int, modulus: int) -> int:
	var result: int = value % modulus
	return result + modulus if result < 0 else result
