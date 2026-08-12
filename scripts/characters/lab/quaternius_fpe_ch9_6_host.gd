class_name QuaterniusFpeCh9_6Host
extends "res://scripts/characters/lab/quaternius_playable_network_equipment_lab.gd"

signal fpe_canonical_projection_applied(classification: String, snapshot: Dictionary)

# The accepted CH6 lab calls virtual _refresh_status() every physics frame. In
# the full CH9.6 inheritance chain a single call can rebuild CH6/7/8/9 debug
# text, refresh equipment snapshots and ask the local network server for a full
# report. Operator evidence measured a 195 ms maximum call. The FPE research
# host therefore never executes that diagnostic chain automatically. The FPE
# overlay has its own lightweight telemetry and an explicit manual heavy refresh
# remains available for diagnostics only.
const PROJECTION_FULL := "FULL_GRAPH"
const PROJECTION_HOTBAR_METADATA_ONLY := "HOTBAR_METADATA_ONLY"
const LOCAL_PLAYER_ID := "a"

var _fpe_status_refresh_calls := 0
var _fpe_status_refresh_executed := 0
var _fpe_status_refresh_skipped := 0
var _fpe_status_refresh_total_us := 0
var _fpe_status_refresh_max_us := 0

var _fpe_last_projected_canonical_snapshot: Dictionary = {}
var _fpe_projection_total := 0
var _fpe_projection_hotbar_fast := 0
var _fpe_projection_full := 0
var _fpe_projection_fast_total_us := 0
var _fpe_projection_fast_max_us := 0
var _fpe_projection_full_total_us := 0
var _fpe_projection_full_max_us := 0


func _refresh_status() -> void:
	_fpe_status_refresh_calls += 1
	_fpe_status_refresh_skipped += 1
	# Seed the comparison baseline once network bootstrap has installed the
	# canonical graph. get_item_graph_snapshot() duplicates the graph, so never do
	# it continuously.
	if (
		_fpe_last_projected_canonical_snapshot.is_empty()
		and network_ready
		and network_client != null
		and network_client.has_method("get_item_graph_snapshot")
	):
		var canonical_value: Variant = network_client.call("get_item_graph_snapshot")
		if canonical_value is Dictionary and not Dictionary(canonical_value).is_empty():
			_fpe_last_projected_canonical_snapshot = Dictionary(canonical_value).duplicate(true)


func force_fpe_status_refresh() -> void:
	# Explicit diagnostic operation only. Never called by the runtime loop.
	var started_us := Time.get_ticks_usec()
	super._refresh_status()
	var elapsed_us := maxi(Time.get_ticks_usec() - started_us, 0)
	_fpe_status_refresh_executed += 1
	_fpe_status_refresh_total_us += elapsed_us
	_fpe_status_refresh_max_us = maxi(_fpe_status_refresh_max_us, elapsed_us)


func _on_projected_item_graph_updated(projected_canonical_snapshot: Dictionary) -> void:
	var started_us := Time.get_ticks_usec()
	var classification := _classify_fpe_projection(
		_fpe_last_projected_canonical_snapshot,
		projected_canonical_snapshot
	)
	_fpe_projection_total += 1

	if classification == PROJECTION_HOTBAR_METADATA_ONLY:
		var fast_result: Dictionary = _apply_fpe_hotbar_metadata_projection(projected_canonical_snapshot)
		if bool(fast_result.get("success", false)):
			var elapsed_fast_us := maxi(Time.get_ticks_usec() - started_us, 0)
			_fpe_projection_hotbar_fast += 1
			_fpe_projection_fast_total_us += elapsed_fast_us
			_fpe_projection_fast_max_us = maxi(_fpe_projection_fast_max_us, elapsed_fast_us)
			_fpe_last_projected_canonical_snapshot = projected_canonical_snapshot.duplicate(true)
			fpe_canonical_projection_applied.emit(
				PROJECTION_HOTBAR_METADATA_ONLY,
				projected_canonical_snapshot.duplicate(true)
			)
			return
		# Fail safe: if metadata-only application cannot be proven/applied, use the
		# accepted full CH9.6 projection path instead of dropping authority state.
		classification = PROJECTION_FULL

	super._on_projected_item_graph_updated(projected_canonical_snapshot)
	var elapsed_full_us := maxi(Time.get_ticks_usec() - started_us, 0)
	_fpe_projection_full += 1
	_fpe_projection_full_total_us += elapsed_full_us
	_fpe_projection_full_max_us = maxi(_fpe_projection_full_max_us, elapsed_full_us)
	_fpe_last_projected_canonical_snapshot = projected_canonical_snapshot.duplicate(true)
	fpe_canonical_projection_applied.emit(
		PROJECTION_FULL,
		projected_canonical_snapshot.duplicate(true)
	)


func _apply_fpe_hotbar_metadata_projection(snapshot: Dictionary) -> Dictionary:
	if character_gameplay_controller == null:
		return {"success": false, "error_code": "FPE_HOTBAR_CONTROLLER_NOT_READY"}
	var inventories_value: Variant = snapshot.get("inventories", {})
	if not inventories_value is Dictionary:
		return {"success": false, "error_code": "FPE_HOTBAR_INVENTORIES_REQUIRED"}
	var local_inventory_value: Variant = Dictionary(inventories_value).get(LOCAL_PLAYER_ID, {})
	if not local_inventory_value is Dictionary:
		return {"success": false, "error_code": "FPE_HOTBAR_LOCAL_INVENTORY_REQUIRED"}
	var local_inventory: Dictionary = Dictionary(local_inventory_value)
	if not local_inventory.has("selected_hotbar_index"):
		return {"success": false, "error_code": "FPE_HOTBAR_SELECTION_REQUIRED"}

	var selected_index := clampi(int(local_inventory.get("selected_hotbar_index", 0)), 0, 9)
	character_gameplay_controller.selected_hotbar_index = selected_index
	character_gameplay_controller.network_replica_revision = int(snapshot.get("revision", -1))
	character_gameplay_controller.network_replica_checksum = String(snapshot.get("checksum", ""))

	# The persistent bar is the only presentation that changes for a selection.
	# Do not rebuild InventoryScreen, reload Item Graph persistence, synchronize
	# world item presentation, or re-run equipment garment reconciliation.
	var inventory_ui = character_gameplay_controller.inventory_ui
	if inventory_ui != null and inventory_ui.has_method("_refresh_persistent_hotbar"):
		inventory_ui.call("_refresh_persistent_hotbar")
	if character_gameplay_controller.has_signal("gameplay_state_changed"):
		character_gameplay_controller.emit_signal("gameplay_state_changed")

	last_network_projection_result = {
		"success": true,
		"code": "FPE_HOTBAR_METADATA_ONLY_FAST_PATH",
		"selected_hotbar_index": selected_index,
		"canonical_revision": int(snapshot.get("revision", -1)),
		"canonical_checksum": String(snapshot.get("checksum", "")),
	}
	return last_network_projection_result.duplicate(true)


func _classify_fpe_projection(previous: Dictionary, incoming: Dictionary) -> String:
	if previous.is_empty() or incoming.is_empty():
		return PROJECTION_FULL
	if String(previous.get("schema", "")) != String(incoming.get("schema", "")):
		return PROJECTION_FULL
	var previous_stable := _fpe_projection_without_hotbar_metadata(previous)
	var incoming_stable := _fpe_projection_without_hotbar_metadata(incoming)
	return (
		PROJECTION_HOTBAR_METADATA_ONLY
		if previous_stable == incoming_stable
		else PROJECTION_FULL
	)


func _fpe_projection_without_hotbar_metadata(snapshot: Dictionary) -> Dictionary:
	var stable: Dictionary = snapshot.duplicate(true)
	for key in ["revision", "tick", "server_tick", "checksum"]:
		stable.erase(key)
	var inventories_value: Variant = stable.get("inventories", {})
	if inventories_value is Dictionary:
		var inventories: Dictionary = Dictionary(inventories_value).duplicate(true)
		for player_id_value in inventories.keys():
			var inventory_value: Variant = inventories[player_id_value]
			if not inventory_value is Dictionary:
				continue
			var inventory: Dictionary = Dictionary(inventory_value).duplicate(true)
			inventory.erase("selected_hotbar_index")
			inventories[player_id_value] = inventory
		stable["inventories"] = inventories
	return stable


func get_fpe_status_performance_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_ch9_6_status_performance.v2",
		"automatic_heavy_status": false,
		"calls": _fpe_status_refresh_calls,
		"executed": _fpe_status_refresh_executed,
		"skipped": _fpe_status_refresh_skipped,
		"average_us": (
			float(_fpe_status_refresh_total_us) / float(_fpe_status_refresh_executed)
			if _fpe_status_refresh_executed > 0 else 0.0
		),
		"max_us": _fpe_status_refresh_max_us,
		"projection_total": _fpe_projection_total,
		"projection_hotbar_fast": _fpe_projection_hotbar_fast,
		"projection_full": _fpe_projection_full,
		"projection_fast_average_us": (
			float(_fpe_projection_fast_total_us) / float(_fpe_projection_hotbar_fast)
			if _fpe_projection_hotbar_fast > 0 else 0.0
		),
		"projection_fast_max_us": _fpe_projection_fast_max_us,
		"projection_full_average_us": (
			float(_fpe_projection_full_total_us) / float(_fpe_projection_full)
			if _fpe_projection_full > 0 else 0.0
		),
		"projection_full_max_us": _fpe_projection_full_max_us,
		"accepted_runtime_parent": "QuaterniusPlayableNetworkEquipmentLab",
		"changes_gameplay_semantics": false,
		"changes_network_authority": false,
	}
