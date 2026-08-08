extends RefCounted

const SampleScript = preload("res://scripts/network/observability/network_observability_sample.gd")
const FingerprintScript = preload("res://scripts/network/observability/network_build_fingerprint.gd")

const SCHEMA: String = "planet_simulator.network_telemetry_collector.v1"
const DEFAULT_SAMPLE_LIMIT: int = 512
const MAX_SAMPLE_LIMIT: int = 4096
const DIRECTIONS: Array[String] = ["sent", "received"]
const SAMPLE_STORAGE_POLICY: String = "BOUNDED_RING_OVERWRITE_V2"

var _configured: bool = false
var _runtime_role: String = ""
var _fingerprint: Dictionary = {}
var _sample_limit: int = DEFAULT_SAMPLE_LIMIT
var _sample_sequence: int = 0
var _counters: Dictionary = {}
var _gauges: Dictionary = {}
var _samples: Dictionary = {}
var _sample_heads: Dictionary = {}
var _sample_overwrites: int = 0
var _channels: Dictionary = {}


func configure(runtime_role: String, fingerprint: Dictionary, sample_limit: int = DEFAULT_SAMPLE_LIMIT) -> Dictionary:
	if _configured:
		return _failure("ALREADY_CONFIGURED")
	if runtime_role not in ["server", "client", "listen-host", "test"]:
		return _failure("INVALID_RUNTIME_ROLE")
	var fingerprint_check: Dictionary = FingerprintScript.validate(fingerprint)
	if not bool(fingerprint_check.get("success", false)):
		return _failure("INVALID_FINGERPRINT", {"cause": fingerprint_check})
	if sample_limit < 1 or sample_limit > MAX_SAMPLE_LIMIT:
		return _failure("INVALID_SAMPLE_LIMIT")
	_runtime_role = runtime_role
	_fingerprint = fingerprint.duplicate(true)
	_sample_limit = sample_limit
	_configured = true
	return _success()


func increment(counter_name: String, amount: int = 1) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if not _is_metric_name(counter_name) or amount < 0:
		return _failure("INVALID_COUNTER_UPDATE")
	_counters[counter_name] = int(_counters.get(counter_name, 0)) + amount
	return _success({"value": int(_counters[counter_name])})


func set_gauge(gauge_name: String, value: float) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if not _is_metric_name(gauge_name) or is_nan(value) or is_inf(value):
		return _failure("INVALID_GAUGE_UPDATE")
	_gauges[gauge_name] = value
	return _success()


func observe(distribution_name: String, value: float) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if not _is_metric_name(distribution_name) or is_nan(value) or is_inf(value):
		return _failure("INVALID_DISTRIBUTION_SAMPLE")

	# Hot-path telemetry is called hundreds of times per second by the realtime
	# server. The old implementation duplicated the entire sample window and
	# shifted the oldest entry out after the window filled, turning a bounded
	# metric into an O(window) allocation/copy path. Keep the same bounded sample
	# semantics with in-place ring overwrite instead. Avoid a default [] expression
	# on existing metrics too, so the steady-state path does not allocate a throwaway
	# Array before the ring lookup.
	var values: Array
	if _samples.has(distribution_name):
		values = _samples[distribution_name]
	else:
		values = []
		_samples[distribution_name] = values
	if values.size() < _sample_limit:
		values.append(value)
		if values.size() == _sample_limit and not _sample_heads.has(distribution_name):
			_sample_heads[distribution_name] = 0
	else:
		var head: int = int(_sample_heads.get(distribution_name, 0))
		values[head] = value
		_sample_heads[distribution_name] = (head + 1) % _sample_limit
		_sample_overwrites += 1
	return _success({"window_size": values.size()})


func record_transport(channel_name: String, direction: String, packet_bytes: int) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if not _is_metric_name(channel_name) or direction not in DIRECTIONS or packet_bytes < 0:
		return _failure("INVALID_TRANSPORT_SAMPLE")
	# Dictionary.get(key, _empty_channel_metrics()) evaluates the default argument
	# before get(), allocating a new metrics Dictionary for every packet even when
	# the channel already exists. Allocate only on first sight of a channel.
	var metrics: Dictionary
	if _channels.has(channel_name):
		metrics = _channels[channel_name]
	else:
		metrics = _empty_channel_metrics()
	metrics["packets_%s" % direction] = int(metrics["packets_%s" % direction]) + 1
	metrics["bytes_%s" % direction] = int(metrics["bytes_%s" % direction]) + packet_bytes
	_channels[channel_name] = metrics
	return _success()


func create_sample(captured_at_ms: int) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if captured_at_ms < 0:
		return _failure("INVALID_CAPTURE_TIME")
	_sample_sequence += 1
	var sample: Dictionary = SampleScript.create(
		"network-sample/%s/%d" % [_runtime_role, _sample_sequence],
		_runtime_role,
		captured_at_ms,
		_fingerprint,
		_counters,
		_gauges,
		_create_distributions(),
		_channels
	)
	var check: Dictionary = SampleScript.validate(sample)
	if not bool(check.get("success", false)):
		return _failure("INVALID_GENERATED_SAMPLE", {"cause": check})
	return _success({"sample": sample})


func reset_window() -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	_samples.clear()
	_sample_heads.clear()
	_sample_overwrites = 0
	return _success()


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _configured,
		"runtime_role": _runtime_role,
		"sample_limit": _sample_limit,
		"sample_sequence": _sample_sequence,
		"sample_storage_policy": SAMPLE_STORAGE_POLICY,
		"sample_overwrites": _sample_overwrites,
		"counter_count": _counters.size(),
		"gauge_count": _gauges.size(),
		"distribution_count": _samples.size(),
		"channel_count": _channels.size(),
	}


func _create_distributions() -> Dictionary:
	var result: Dictionary = {}
	for name_value in _samples.keys():
		var name: String = String(name_value)
		# Diagnostic materialization may copy/sort because it is cold-path and
		# explicitly requested. observe() itself stays allocation-bounded.
		var values: Array = Array(_samples[name_value]).duplicate()
		values.sort()
		if values.is_empty():
			continue
		var sum: float = 0.0
		for value in values:
			sum += float(value)
		result[name] = {
			"count": values.size(),
			"min": float(values.front()),
			"max": float(values.back()),
			"mean": sum / float(values.size()),
			"p50": _percentile(values, 0.50),
			"p95": _percentile(values, 0.95),
			"p99": _percentile(values, 0.99),
		}
	return result


func _percentile(sorted_values: Array, percentile: float) -> float:
	if sorted_values.size() == 1:
		return float(sorted_values[0])
	var position: float = clampf(percentile, 0.0, 1.0) * float(sorted_values.size() - 1)
	var lower: int = int(floor(position))
	var upper: int = int(ceil(position))
	if lower == upper:
		return float(sorted_values[lower])
	var weight: float = position - float(lower)
	return lerpf(float(sorted_values[lower]), float(sorted_values[upper]), weight)


func _empty_channel_metrics() -> Dictionary:
	return {
		"packets_sent": 0,
		"packets_received": 0,
		"bytes_sent": 0,
		"bytes_received": 0,
	}


func _is_metric_name(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value != value.to_lower() or value.length() > 96:
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["_", "-", "."]):
			return false
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
