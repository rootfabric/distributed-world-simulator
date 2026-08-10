extends "res://scripts/world/testing/playground_view_relative_runtime_fix6.gd"

# Inventory rev6 fix7 composition plus FIX10 movement presentation repair.
#
# The view-relative parent intentionally advances deterministic client prediction
# only from the 60 Hz physics loop and suppresses render-side simulation. A later
# accepted presentation layer disabled Godot physics interpolation for the whole
# player/camera hierarchy because the reconciler was expected to provide its own
# render-rate sub-tick pose. In the composed runtime both mechanisms were therefore
# off: the CharacterBody transform changed only at 60 Hz even on 120-165 Hz render
# frames.
#
# Keep simulation strictly physics-only, but make visible presentation render-rate.
# The newest fixed prediction pose is extrapolated by render elapsed time using its
# already-deterministic velocity, bounded to one fixed tick. No input sequence,
# prediction tick, reconciliation or authority state advances from _process().

const InventoryRev6EnhancerFix7Script = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix7.gd"
)

const FIX10_FIX7_RENDER_PRESENTATION_POLICY: String = \
	"PHYSICS_SIMULATION_RENDER_RATE_BOUNDED_EXTRAPOLATION_V1"
const FIX10_FIX7_FIXED_DELTA_SECONDS: float = 1.0 / 60.0

var _fix10_fix7_latest_prediction_presentation: Dictionary = {}
var _fix10_fix7_render_elapsed_seconds: float = 0.0
var _fix10_fix7_render_presentation_applies: int = 0
var _fix10_fix7_fixed_presentations_consumed: int = 0
var _fix10_fix7_max_render_elapsed_seconds: float = 0.0
var _fix10_fix7_max_render_extrapolation_m: float = 0.0


func _process(delta: float) -> void:
	# Parent preserves the deliberate render-side SIMULATION suppression. This
	# layer only writes a visual transform after parent processing has completed.
	super._process(delta)
	if (
		runtime_role != "game-client"
		or not _m3_attached
		or not _network_playground_enabled
		or player == null
	):
		return
	_fix10_fix7_render_elapsed_seconds = minf(
		_fix10_fix7_render_elapsed_seconds + maxf(delta, 0.0),
		FIX10_FIX7_FIXED_DELTA_SECONDS
	)
	_fix10_fix7_max_render_elapsed_seconds = maxf(
		_fix10_fix7_max_render_elapsed_seconds,
		_fix10_fix7_render_elapsed_seconds
	)
	_fix10_fix7_apply_render_presentation()


func _flush_pending_prediction_presentation() -> void:
	# Called from the inherited physics process after fixed prediction. For normal
	# non-network paths retain the accepted parent behavior exactly.
	if (
		runtime_role != "game-client"
		or not _m3_attached
		or not _network_playground_enabled
	):
		super._flush_pending_prediction_presentation()
		return
	if not _pending_prediction_presentation_dirty:
		return
	_fix10_fix7_latest_prediction_presentation = \
		_pending_prediction_presentation.duplicate(true)
	_pending_prediction_presentation = {}
	_pending_prediction_presentation_dirty = false
	_fix10_fix7_render_elapsed_seconds = 0.0
	_fix10_fix7_fixed_presentations_consumed += 1


func _fix10_fix7_apply_render_presentation() -> void:
	if _fix10_fix7_latest_prediction_presentation.is_empty() or player == null:
		return
	var state: Dictionary = _fix10_fix7_latest_prediction_presentation
	var position_value = state.get("position", {})
	var velocity_value = state.get("velocity", {})
	if not position_value is Dictionary or not velocity_value is Dictionary:
		return
	var position: Dictionary = position_value
	var velocity: Dictionary = velocity_value
	var base_position := Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	)
	var velocity_vector := Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	var extrapolation := velocity_vector * _fix10_fix7_render_elapsed_seconds
	_fix10_fix7_max_render_extrapolation_m = maxf(
		_fix10_fix7_max_render_extrapolation_m,
		extrapolation.length()
	)
	player.set_world_position(base_position + extrapolation)
	player.velocity = velocity_vector
	var yaw: float = float(state.get("orientation_yaw", 0.0))
	if player.visual_root != null:
		player.visual_root.rotation.y = yaw
	_fix10_fix7_render_presentation_applies += 1


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result

	# The fix6 parent installs its enhancer. Remove its screen-owned buttons and
	# replace that presentation layer only; M7 adapter, prediction journal,
	# command bridge and authority paths remain untouched.
	_cleanup_inventory_enhancer_overlay(_inventory_rev6_enhancer)
	if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer):
		_inventory_rev6_enhancer.free()

	_inventory_rev6_enhancer = InventoryRev6EnhancerFix7Script.new()
	_inventory_rev6_enhancer.name = "InventoryNetworkRev6EnhancerFix7"
	add_child(_inventory_rev6_enhancer)
	var enhancer_setup: Dictionary = _inventory_rev6_enhancer.setup(
		item_gameplay,
		_m7_item_bridge
	)
	if not bool(enhancer_setup.get("success", false)):
		return enhancer_setup
	return setup_result


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	var view_report: Dictionary = Dictionary(
		report.get("view_relative_prediction", {})
	).duplicate(true)
	view_report["presentation_policy"] = FIX10_FIX7_RENDER_PRESENTATION_POLICY
	view_report["render_presentation_applies"] = _fix10_fix7_render_presentation_applies
	view_report["fixed_presentations_consumed"] = _fix10_fix7_fixed_presentations_consumed
	view_report["max_render_elapsed_seconds"] = _fix10_fix7_max_render_elapsed_seconds
	view_report["max_render_extrapolation_m"] = _fix10_fix7_max_render_extrapolation_m
	report["view_relative_prediction"] = view_report
	return report
