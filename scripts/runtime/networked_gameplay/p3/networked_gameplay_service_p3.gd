extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ResourceMiningService = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_service.gd"
)
const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)

const RESOURCE_DURABLE_FIELD := "resource_mining"
const RESOURCE_REPLAY_FIELD := "resource_replay"
const SERVER_OUTPUT_ITEM_PREFIX := "item/server-output/"

var _resource_mining
var _resource_spatial_resolver


func setup(
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int = 0,
	config: Dictionary = {}
) -> Dictionary:
	var base_result: Dictionary = super.setup(
		authority_owner_id,
		authority_epoch,
		server_tick,
		config
	)
	if not bool(base_result.get("success", false)):
		return base_result
	var resource_setup := _setup_resource_domain()
	if not bool(resource_setup.get("success", false)):
		super.shutdown()
		return resource_setup
	var details: Dictionary = Dictionary(base_result.get("details", {})).duplicate(true)
	details["resource_mining_snapshot"] = create_resource_mining_snapshot()
	base_result["details"] = details
	return base_result


func handle_resource_mine(
	logical_player_id: String,
	transport_session_id: String,
	ownership_epoch: int,
	operation_id: String,
	payload: Dictionary
) -> Dictionary:
	if not _configured or _resource_mining == null:
		return _failure("RESOURCE_MINING_NOT_READY")
	var player_id := logical_player_id.strip_edges().to_lower()
	var owner_check := _validate_owner(player_id, transport_session_id, ownership_epoch)
	if not bool(owner_check.get("success", false)):
		return owner_check
	var player: Dictionary = _players.get_player(player_id)
	var position_value = player.get("position", {})
	if not position_value is Dictionary:
		return _failure("RESOURCE_OUT_OF_RANGE")
	var result: Dictionary = _resource_mining.mine(
		player_id,
		operation_id,
		payload,
		Dictionary(position_value)
	)
	if bool(result.get("success", false)) and not bool(result.get("replay", false)):
		_advance()
	return result


func create_resource_mining_snapshot() -> Dictionary:
	return _resource_mining.create_snapshot() if _resource_mining != null else {}


func validate_resource_mining_snapshot(snapshot: Dictionary) -> Dictionary:
	if _resource_mining != null:
		return _resource_mining.validate_durable_state({
			"schema": ResourceMiningService.DURABLE_SCHEMA,
			"snapshot": snapshot,
			"checksum": NetworkUtils.payload_hash({
				"schema": ResourceMiningService.DURABLE_SCHEMA,
				"snapshot": snapshot,
			}),
		})
	var validator = ResourceMiningService.new()
	var durable := {
		"schema": ResourceMiningService.DURABLE_SCHEMA,
		"snapshot": snapshot,
		"checksum": "",
	}
	durable = NetworkUtils.finalize_json_checksum(durable)
	return validator.validate_durable_state(durable)


func export_durable_state() -> Dictionary:
	var state: Dictionary = super.export_durable_state()
	if state.is_empty() or _resource_mining == null:
		return state
	state[RESOURCE_DURABLE_FIELD] = _resource_mining.export_durable_state()
	state["checksum"] = ""
	return NetworkUtils.finalize_json_checksum(state)


func validate_durable_state(value: Dictionary) -> Dictionary:
	var base_validation := super.validate_durable_state(value)
	if not bool(base_validation.get("success", false)):
		return base_validation
	if not value.has(RESOURCE_DURABLE_FIELD):
		if _contains_p3_server_output(Dictionary(value.get("canonical_item_graph", {}))):
			return _failure("P3_RESOURCE_STATE_REQUIRED")
		return _success({"resource_state": "LEGACY_P2_DEFAULT"})
	if typeof(value.get(RESOURCE_DURABLE_FIELD)) != TYPE_DICTIONARY:
		return _failure("INVALID_RESOURCE_DURABLE_SECTION")
	var validator = ResourceMiningService.new()
	var resource_state: Dictionary = value.get(RESOURCE_DURABLE_FIELD, {})
	var resource_validation := validator.validate_durable_state(resource_state)
	if not bool(resource_validation.get("success", false)):
		return _failure("INVALID_GAMEPLAY_RESOURCE_STATE", {"cause": resource_validation})
	var resource_snapshot: Dictionary = resource_state.get("snapshot", {})
	if (
		String(resource_snapshot.get("authority_owner_id", "")) != String(value.get("authority_owner_id", ""))
		or int(resource_snapshot.get("authority_epoch", 0)) != int(value.get("authority_epoch", 0))
	):
		return _failure("GAMEPLAY_RESOURCE_AUTHORITY_MISMATCH")
	return _success()


func restore_durable_state(value: Dictionary) -> Dictionary:
	var has_resource_state := value.has(RESOURCE_DURABLE_FIELD)
	var restored: Dictionary = super.restore_durable_state(value)
	if not bool(restored.get("success", false)):
		return restored
	var resource_setup := _setup_resource_domain()
	if not bool(resource_setup.get("success", false)):
		return resource_setup
	var migrated_from_p2 := not has_resource_state
	if has_resource_state:
		var resource_result: Dictionary = _resource_mining.restore_durable_state(
			Dictionary(value.get(RESOURCE_DURABLE_FIELD, {}))
		)
		if not bool(resource_result.get("success", false)):
			return _failure("GAMEPLAY_RESOURCE_RECOVERY_FAILED", {"cause": resource_result})
	var details: Dictionary = Dictionary(restored.get("details", {})).duplicate(true)
	details["resource_mining_generation"] = int(create_resource_mining_snapshot().get("generation", 0))
	details["resource_mining_checksum"] = String(create_resource_mining_snapshot().get("checksum", ""))
	details["resource_mining_migrated_from_p2"] = migrated_from_p2
	restored["details"] = details
	return restored


func export_replay_state() -> Dictionary:
	var state: Dictionary = super.export_replay_state()
	if state.is_empty() or _resource_mining == null:
		return state
	state[RESOURCE_REPLAY_FIELD] = _resource_mining.export_replay_state()
	state["checksum"] = ""
	return NetworkUtils.finalize_json_checksum(state)


func validate_replay_state(value: Dictionary) -> Dictionary:
	var base_validation := super.validate_replay_state(value)
	if not bool(base_validation.get("success", false)):
		return base_validation
	if not value.has(RESOURCE_REPLAY_FIELD):
		if _contains_resource_output_replay(Dictionary(value.get("item_graph_replay", {}))):
			return _failure("P3_RESOURCE_REPLAY_REQUIRED")
		return _success({"resource_replay": "LEGACY_P2_EMPTY"})
	if typeof(value.get(RESOURCE_REPLAY_FIELD)) != TYPE_DICTIONARY:
		return _failure("INVALID_RESOURCE_REPLAY_SECTION")
	var validator = ResourceMiningService.new()
	var resource_validation := validator.validate_replay_state(
		Dictionary(value.get(RESOURCE_REPLAY_FIELD, {}))
	)
	if not bool(resource_validation.get("success", false)):
		return _failure("INVALID_GAMEPLAY_RESOURCE_REPLAY", {"cause": resource_validation})
	return _success()


func restore_replay_state(value: Dictionary) -> Dictionary:
	var restored: Dictionary = super.restore_replay_state(value)
	if not bool(restored.get("success", false)):
		return restored
	if _resource_mining == null:
		var resource_setup := _setup_resource_domain()
		if not bool(resource_setup.get("success", false)):
			return resource_setup
	if value.has(RESOURCE_REPLAY_FIELD):
		var resource_result: Dictionary = _resource_mining.restore_replay_state(
			Dictionary(value.get(RESOURCE_REPLAY_FIELD, {}))
		)
		if not bool(resource_result.get("success", false)):
			return _failure("GAMEPLAY_RESOURCE_REPLAY_RECOVERY_FAILED", {"cause": resource_result})
	var details: Dictionary = Dictionary(restored.get("details", {})).duplicate(true)
	details["resource_operation_count"] = _resource_mining.get_replay_operation_count()
	restored["details"] = details
	return restored


func has_durable_replay_operation(operation_id: String) -> bool:
	return (
		super.has_durable_replay_operation(operation_id)
		or (
			_resource_mining != null
			and _resource_mining.has_replay_operation(operation_id)
		)
	)


func get_recovery_report() -> Dictionary:
	var report: Dictionary = super.get_recovery_report()
	if _resource_mining != null:
		var snapshot := create_resource_mining_snapshot()
		report["resource_mining_generation"] = int(snapshot.get("generation", 0))
		report["resource_mining_checksum"] = String(snapshot.get("checksum", ""))
		report["resource_operation_count"] = _resource_mining.get_replay_operation_count()
	return report


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["resource_mining"] = create_resource_mining_snapshot()
	return report


func shutdown() -> Dictionary:
	_resource_mining = null
	_resource_spatial_resolver = null
	return super.shutdown()


func _setup_resource_domain() -> Dictionary:
	_resource_spatial_resolver = EarthResourceSpatialResolver.new()
	var resolver_setup: Dictionary = _resource_spatial_resolver.setup()
	if not bool(resolver_setup.get("success", false)):
		return _failure("RESOURCE_SPATIAL_RESOLVER_SETUP_FAILED", {"cause": resolver_setup})
	_resource_mining = ResourceMiningService.new()
	var resource_setup: Dictionary = _resource_mining.setup(
		_authority_owner_id,
		_authority_epoch,
		_canonical_multiplayer_items,
		_resource_spatial_resolver
	)
	if not bool(resource_setup.get("success", false)):
		return _failure("RESOURCE_MINING_SETUP_FAILED", {"cause": resource_setup})
	return _success()


func _contains_p3_server_output(item_graph_state: Dictionary) -> bool:
	var snapshot_value = item_graph_state.get("snapshot", {})
	if not snapshot_value is Dictionary:
		return false
	for item_value in Dictionary(snapshot_value).get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")).begins_with(SERVER_OUTPUT_ITEM_PREFIX):
			return true
	return false


func _contains_resource_output_replay(item_graph_replay: Dictionary) -> bool:
	var records_value = item_graph_replay.get("records", {})
	if not records_value is Dictionary:
		return false
	for entry_value in Dictionary(records_value).values():
		if not entry_value is Dictionary:
			continue
		var result_value = Dictionary(entry_value).get("result", {})
		if not result_value is Dictionary:
			continue
		var details_value = Dictionary(result_value).get("details", {})
		if details_value is Dictionary and String(Dictionary(details_value).get("source_id", "")).begins_with("resource/"):
			return true
	return false
