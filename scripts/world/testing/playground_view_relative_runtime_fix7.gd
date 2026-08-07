extends "res://scripts/world/testing/playground_view_relative_runtime_fix6.gd"

# Fix7 makes the visible inventory reactive to authoritative M7 Item Graph
# replication. The replica domain was already updated by the parent runtime,
# but an open InventoryScreen kept rendering its previous current_model until
# another UI action (close/reopen, carry/drop, etc.) called refresh().
#
# Refresh presentation immediately after a newly applied authoritative item
# projection. This is intentionally a presentation reaction only: authority,
# prediction, sort ordering and canonical item state remain unchanged.

const FIX7_PRESENTATION_SCHEMA := "planet_simulator.m7_item_replica_presentation.fix7.v1"

var _m7_inventory_screen_refreshes: int = 0
var _m7_persistent_hotbar_refreshes: int = 0
var _m7_item_projection_refresh_triggers: int = 0


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	var before_revision: int = _m7_last_item_revision
	var before_projection_hash: String = _m7_last_item_projection_hash

	super._on_m4_item_graph_updated(snapshot)

	# The parent changes one or both markers only after conversion and
	# item_gameplay.apply_network_graph_snapshot() succeeded. Do not repaint for
	# duplicates, rejected projections or snapshots that were not applied.
	var projection_applied: bool = (
		_m7_last_sync_error.is_empty()
		and (
			_m7_last_item_revision != before_revision
			or _m7_last_item_projection_hash != before_projection_hash
		)
	)
	if not projection_applied:
		return

	_m7_item_projection_refresh_triggers += 1
	_refresh_m7_item_replica_presentation()


func _refresh_m7_item_replica_presentation() -> void:
	if item_gameplay == null:
		return
	var inventory_ui = item_gameplay.get("inventory_ui")
	if inventory_ui == null:
		return

	var active_screen = inventory_ui.get("active_screen")
	if active_screen != null and is_instance_valid(active_screen):
		var inventory_visible: bool = bool(active_screen.get("visible"))
		if active_screen.has_method("is_inventory_visible"):
			inventory_visible = bool(active_screen.call("is_inventory_visible"))
		if inventory_visible and active_screen.has_method("refresh"):
			# apply_network_graph_snapshot() has already completed synchronously, so
			# refresh() now builds from the new replica state in the same frame.
			active_screen.call("refresh")
			_m7_inventory_screen_refreshes += 1

	# The persistent hotbar is outside InventoryScreen and needs its own render.
	# Keep it reactive even while the main inventory window is closed.
	if inventory_ui.has_method("_refresh_persistent_hotbar"):
		inventory_ui.call("_refresh_persistent_hotbar")
		_m7_persistent_hotbar_refreshes += 1


func get_m7_item_replica_presentation_report() -> Dictionary:
	return {
		"schema": FIX7_PRESENTATION_SCHEMA,
		"projection_refresh_triggers": _m7_item_projection_refresh_triggers,
		"inventory_screen_refreshes": _m7_inventory_screen_refreshes,
		"persistent_hotbar_refreshes": _m7_persistent_hotbar_refreshes,
		"policy": "REFRESH_VISIBLE_INVENTORY_AFTER_APPLIED_ITEM_PROJECTION",
	}


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["item_replica_presentation"] = get_m7_item_replica_presentation_report()
	return report
