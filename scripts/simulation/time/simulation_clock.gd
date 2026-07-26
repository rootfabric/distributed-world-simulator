extends RefCounted

signal time_changed(snapshot: Dictionary)

const SCHEMA: String = "planet_simulator.simulation_clock.v1"
const DEFAULT_AUTHORITY_ID: String = "local-clock"

var authority_id: String = DEFAULT_AUTHORITY_ID
var authority_epoch: int = 1
var epoch_seconds: float = 0.0
var simulation_time_s: float = 0.0
var time_scale: float = 1.0
var paused: bool = false
var tick_index: int = 0
var time_revision: int = 0


func setup(config: Dictionary = {}) -> void:
	authority_id = String(config.get("authority_id", DEFAULT_AUTHORITY_ID)).strip_edges()
	if authority_id.is_empty():
		authority_id = DEFAULT_AUTHORITY_ID
	authority_epoch = maxi(1, int(config.get("authority_epoch", 1)))
	epoch_seconds = _finite_or_default(config.get("epoch_seconds", 0.0), 0.0)
	simulation_time_s = _finite_or_default(
		config.get("initial_time_s", epoch_seconds),
		epoch_seconds
	)
	time_scale = maxf(
		0.0,
		_finite_or_default(config.get("time_scale", 1.0), 1.0)
	)
	paused = bool(config.get("paused", false))
	tick_index = maxi(0, int(config.get("tick_index", 0)))
	time_revision = maxi(0, int(config.get("time_revision", 0)))


func advance(real_delta_s: float) -> bool:
	if (
		paused
		or time_scale <= 0.0
		or real_delta_s <= 0.0
		or not is_finite(real_delta_s)
	):
		return false
	var simulated_delta_s: float = real_delta_s * time_scale
	var next_time_s: float = simulation_time_s + simulated_delta_s
	if not is_finite(simulated_delta_s) or not is_finite(next_time_s):
		return false
	simulation_time_s = next_time_s
	tick_index += 1
	return true


func set_time(value_s: float) -> void:
	if not is_finite(value_s) or is_equal_approx(simulation_time_s, value_s):
		return
	simulation_time_s = value_s
	time_revision += 1
	_emit_changed()


func set_time_scale(value: float) -> void:
	if not is_finite(value):
		return
	var next_scale: float = maxf(0.0, value)
	if is_equal_approx(time_scale, next_scale):
		return
	time_scale = next_scale
	time_revision += 1
	_emit_changed()


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	time_revision += 1
	_emit_changed()


func step(delta_s: float) -> void:
	if not is_finite(delta_s) or is_zero_approx(delta_s):
		return
	var next_time_s: float = simulation_time_s + delta_s
	if not is_finite(next_time_s):
		return
	simulation_time_s = next_time_s
	tick_index += 1
	time_revision += 1
	_emit_changed()


func get_time_seconds() -> float:
	return simulation_time_s


func apply_authoritative_snapshot(snapshot: Dictionary) -> bool:
	if String(snapshot.get("schema", "")) != SCHEMA:
		return false
	var incoming_authority_id: String = String(
		snapshot.get("authority_id", "")
	).strip_edges()
	var incoming_authority_epoch: int = int(snapshot.get("authority_epoch", 0))
	var incoming_tick_index: int = int(snapshot.get("tick_index", -1))
	var incoming_time_revision: int = int(snapshot.get("time_revision", -1))
	var incoming_epoch_seconds = snapshot.get("epoch_seconds", null)
	var incoming_simulation_time = snapshot.get("simulation_time_s", null)
	var incoming_time_scale = snapshot.get("time_scale", null)
	if (
		incoming_authority_id.is_empty()
		or incoming_authority_epoch < 1
		or incoming_tick_index < 0
		or incoming_time_revision < 0
		or not _is_finite_number(incoming_epoch_seconds)
		or not _is_finite_number(incoming_simulation_time)
		or not _is_finite_number(incoming_time_scale)
		or float(incoming_time_scale) < 0.0
	):
		return false
	if incoming_authority_epoch < authority_epoch:
		return false
	if incoming_authority_epoch == authority_epoch:
		if incoming_authority_id != authority_id:
			return false
		if incoming_time_revision < time_revision:
			return false
		if (
			incoming_time_revision == time_revision
			and incoming_tick_index < tick_index
		):
			return false

	authority_id = incoming_authority_id
	authority_epoch = incoming_authority_epoch
	epoch_seconds = float(incoming_epoch_seconds)
	simulation_time_s = float(incoming_simulation_time)
	time_scale = float(incoming_time_scale)
	paused = bool(snapshot.get("paused", false))
	tick_index = incoming_tick_index
	time_revision = incoming_time_revision
	_emit_changed()
	return true


func create_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"authority_id": authority_id,
		"authority_epoch": authority_epoch,
		"epoch_seconds": epoch_seconds,
		"simulation_time_s": simulation_time_s,
		"time_scale": time_scale,
		"paused": paused,
		"tick_index": tick_index,
		"time_revision": time_revision,
	}


func _emit_changed() -> void:
	time_changed.emit(create_snapshot())


func _finite_or_default(value, default_value: float) -> float:
	return float(value) if _is_finite_number(value) else default_value


func _is_finite_number(value) -> bool:
	var value_type: int = typeof(value)
	return value_type in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
