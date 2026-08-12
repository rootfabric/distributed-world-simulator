class_name QuaterniusFpeCh9_6Host
extends "res://scripts/characters/lab/quaternius_playable_network_equipment_lab.gd"

# The accepted CH6 lab calls the virtual _refresh_status() from every physics
# frame. In the CH9.6 stack that virtual chain builds all CH6/7/8/9 diagnostics,
# refreshes the ItemGraphEquipmentSource and asks the local network server for a
# report. That work is useful for a lab HUD, but it must not run at 60 Hz while
# evaluating first-person presentation.
const STATUS_REFRESH_INTERVAL_MS := 500

var _fpe_status_refresh_last_ms := -STATUS_REFRESH_INTERVAL_MS
var _fpe_status_refresh_calls := 0
var _fpe_status_refresh_executed := 0
var _fpe_status_refresh_skipped := 0
var _fpe_status_refresh_total_us := 0
var _fpe_status_refresh_max_us := 0


func _refresh_status() -> void:
	_fpe_status_refresh_calls += 1
	var now_ms := Time.get_ticks_msec()
	if now_ms - _fpe_status_refresh_last_ms < STATUS_REFRESH_INTERVAL_MS:
		_fpe_status_refresh_skipped += 1
		return

	var started_us := Time.get_ticks_usec()
	super._refresh_status()
	var elapsed_us := maxi(Time.get_ticks_usec() - started_us, 0)
	_fpe_status_refresh_last_ms = now_ms
	_fpe_status_refresh_executed += 1
	_fpe_status_refresh_total_us += elapsed_us
	_fpe_status_refresh_max_us = maxi(_fpe_status_refresh_max_us, elapsed_us)


func force_fpe_status_refresh() -> void:
	_fpe_status_refresh_last_ms = -STATUS_REFRESH_INTERVAL_MS
	_refresh_status()


func get_fpe_status_performance_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_ch9_6_status_performance.v1",
		"interval_ms": STATUS_REFRESH_INTERVAL_MS,
		"calls": _fpe_status_refresh_calls,
		"executed": _fpe_status_refresh_executed,
		"skipped": _fpe_status_refresh_skipped,
		"average_us": (
			float(_fpe_status_refresh_total_us) / float(_fpe_status_refresh_executed)
			if _fpe_status_refresh_executed > 0 else 0.0
		),
		"max_us": _fpe_status_refresh_max_us,
		"accepted_runtime_parent": "QuaterniusPlayableNetworkEquipmentLab",
		"changes_gameplay_semantics": false,
		"changes_network_authority": false,
	}
