extends "res://scripts/ui/inventory/inventory_network_rev6_enhancer.gd"

# The NX6 command pump intentionally normalizes successful wire completions and
# does not preserve the original picked item_id as a top-level result field.
# Therefore pickup auto-stacking is triggered by the authoritative operation
# kind and consolidates compatible stacks already present in the local player
# inventory. This keeps the behavior deterministic without guessing an ID from
# transport-specific wire payloads.

const FIX_SCHEMA := "planet_simulator.inventory_network_rev6_enhancer.fix1.v1"


func _on_authoritative_item_command_completed(
	operation_id: String,
	result: Dictionary,
	_canonical_snapshot: Dictionary
) -> void:
	if not bool(result.get("success", false)) or not operation_id.contains("-pickup-"):
		return
	_pickup_queue.append({"attempts_left": 12, "inventory_wide": true})


func _process_pickup_queue() -> void:
	if _pickup_queue.is_empty() or _sort_in_progress:
		return
	var inventory = gameplay_controller.get_container(gameplay_controller.player_inventory_id)
	if inventory == null:
		var entry: Dictionary = Dictionary(_pickup_queue[0])
		entry["attempts_left"] = int(entry.get("attempts_left", 0)) - 1
		if int(entry["attempts_left"]) <= 0:
			_pickup_queue.pop_front()
		else:
			_pickup_queue[0] = entry
		return
	_pickup_queue.pop_front()
	_sort_in_progress = true
	var merged := _merge_container_stacks(String(gameplay_controller.player_inventory_id))
	_sort_in_progress = false
	if merged:
		_pickup_stack_operations += 1
		call_deferred("_refresh_screen")


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["schema"] = FIX_SCHEMA
	report["pickup_stack_mode"] = "CONSOLIDATE_COMPATIBLE_ON_PICKUP_COMPLETION"
	return report
