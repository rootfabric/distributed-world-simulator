class_name Ch9PersistentEquipmentDedicatedServerRuntime
extends "res://scripts/runtime/networked_gameplay/ch9/ch9_3_dedicated_server_runtime.gd"

const RecoveryService = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_4_equipment_recovery_service.gd")

const RESULT_PERSISTENCE_ROOT_REQUIRED := "CH9_5_PERSISTENCE_ROOT_REQUIRED"
const RESULT_RECOVERY_SERVICE_SETUP_FAILED := "CH9_5_RECOVERY_SERVICE_SETUP_FAILED"
const RESULT_RECOVERY_COMPOSITION_FAILED := "CH9_5_RECOVERY_COMPOSITION_FAILED"
const RESULT_FIXED_TICK_RESTORE_FAILED := "CH9_5_FIXED_TICK_RESTORE_FAILED"


func setup(config: Dictionary) -> Dictionary:
	var requested_persistence_root := String(config.get("persistence_root", "")).strip_edges()
	if requested_persistence_root.is_empty():
		return _failure(RESULT_PERSISTENCE_ROOT_REQUIRED)

	# CH9.3 already owns the accepted ENet equipment transport composition but
	# intentionally rejects persistence. Bootstrap that exact transport without
	# persistence first; no SceneTree process iteration can run until this setup
	# call returns, so the gameplay service can be replaced synchronously before
	# live traffic is handled.
	var transport_config: Dictionary = config.duplicate(true)
	transport_config["persistence_root"] = ""
	var transport_setup: Dictionary = super.setup(transport_config)
	if not bool(transport_setup.get("success", false)):
		return transport_setup

	var replacement = RecoveryService.new()
	var replacement_setup: Dictionary = replacement.setup(
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		{
			"profile": RecoveryService.PROFILE_MULTIPLAYER_CORE,
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": _playable_sandbox,
			"fixed_tick_authority": true,
		}
	)
	if not bool(replacement_setup.get("success", false)):
		_cleanup_setup_failure()
		return _failure(RESULT_RECOVERY_SERVICE_SETUP_FAILED, {"cause": replacement_setup})

	if _service != null:
		_service.shutdown()
	_service = replacement
	_persistence_root = requested_persistence_root
	_persistence_enabled = true

	# Reuse the inherited M6 repository/coordinator/authority-adapter/outbox
	# pipeline. Because _service is already the CH9.4 recovery-aware service,
	# recover_latest() rehydrates the canonical equipment Item Graph rather than
	# falling back to the generic M4 graph implementation.
	var recovery_setup: Dictionary = _setup_recovery()
	if not bool(recovery_setup.get("success", false)):
		_cleanup_setup_failure()
		return _failure(RESULT_RECOVERY_COMPOSITION_FAILED, {"cause": recovery_setup})

	# A recovered checkpoint may carry a server tick newer than the temporary
	# transport bootstrap. Rebuild only the inherited scheduler clock so the next
	# fixed tick continues monotonically from recovered canonical state.
	_server_tick = int(_service.get_report().get("server_tick", 0))
	_fixed_tick_scheduler = FixedTickScheduler.new()
	var fixed_tick_setup: Dictionary = _fixed_tick_scheduler.configure(
		NX3_FIXED_TICK_RATE_HZ,
		FixedTickScheduler.DEFAULT_MAX_CATCH_UP_TICKS,
		_server_tick
	)
	if not bool(fixed_tick_setup.get("success", false)):
		_cleanup_setup_failure()
		return _failure(RESULT_FIXED_TICK_RESTORE_FAILED, {"cause": fixed_tick_setup})
	_last_movement_snapshot_tick = _server_tick
	_movement_snapshot_dirty = true
	_last_error_code = ""
	_write_report("READY", false)

	return _success({
		"host": _host,
		"port": _port,
		"character_equipment_authority": true,
		"character_equipment_persistence": true,
		"persistence_root": _persistence_root,
		"recovered": _recovered,
		"recovery_source": _recovery_source,
		"checkpoint_generation": _checkpoint_generation,
		"server_tick": _server_tick,
		"item_graph_channel": "ITEM",
	})


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["ch9_5_live_equipment_runtime"] = true
	report["character_equipment_persistence"] = _persistence_enabled
	report["equipment_recovery_service"] = _service is Ch9EquipmentRecoveryService
	return report
