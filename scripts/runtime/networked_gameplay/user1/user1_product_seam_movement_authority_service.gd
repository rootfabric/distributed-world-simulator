extends "res://scripts/runtime/networked_gameplay/user1/user1_product_seam_authority_service.gd"

# USER1-SEM1 secondary authority.
#
# This service deliberately does NOT call the ordinary product setup because
# that setup creates canonical M4 / ResourceMining / shared-item domains.
# Authority B owns only the live player row, ownership row, movement runtime,
# actor-local replay receipts and the accepted SM1 transfer port.

const MovementOwnership = preload(
	"res://scripts/runtime/networked_gameplay/services/player_ownership_service.gd"
)
const MovementPlayers = preload(
	"res://scripts/runtime/networked_gameplay/services/player_registry.gd"
)
const MovementRuntime = preload(
	"res://scripts/runtime/networked_gameplay/services/player_movement_service.gd"
)


func setup(
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int = 0,
	config: Dictionary = {}
) -> Dictionary:
	if _configured:
		return _movement_failure("NETWORKED_GAMEPLAY_SERVICE_ALREADY_CONFIGURED")
	if (
		authority_owner_id.strip_edges().is_empty()
		or authority_epoch < 1
		or server_tick < 0
	):
		return _movement_failure("INVALID_MULTIPLAYER_AUTHORITY_CONFIGURATION")
	var region_id := String(config.get("region_id", "")).strip_edges()
	var topology_adapter := String(
		config.get("topology_adapter", "USER1_PRODUCT_SEAM_INTERNAL")
	).strip_edges().to_upper()
	if region_id.is_empty() or topology_adapter.is_empty():
		return _movement_failure("INVALID_NETWORKED_GAMEPLAY_CONFIGURATION")

	_authority_owner_id = authority_owner_id.strip_edges()
	_authority_epoch = authority_epoch
	_tick = server_tick
	_revision = 0
	_region_id = region_id
	_topology_adapter = topology_adapter
	_profile = PROFILE_MULTIPLAYER_CORE
	_playable_sandbox = false
	_fixed_tick_authority = bool(config.get("fixed_tick_authority", true))
	_operation_ledger.clear()

	_ownership = MovementOwnership.new()
	var ownership_setup: Dictionary = _ownership.setup(
		_authority_owner_id,
		_authority_epoch,
		server_tick
	)
	if not bool(ownership_setup.get("success", false)):
		return ownership_setup
	_players = MovementPlayers.new()
	_players.clear()
	_movement = MovementRuntime.new()

	# Explicitly keep every non-movement gameplay owner absent.
	_shared_items = null
	_result_router = null
	_replication = null
	_item_graph_service = null
	_container_interactions = null
	_mount_interactions = null
	_playable_backend = null
	_canonical_multiplayer_items = null
	_resource_mining = null
	_resource_spatial_resolver = null
	_live_player_port = null
	_configured = true
	return _movement_success({
		"movement_only": true,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"region_id": _region_id,
		"canonical_domain_count": 0,
	})


func create_snapshot() -> Dictionary:
	# Secondary snapshots are never product/world snapshots. The primary product
	# service merges the active player row into its one canonical snapshot.
	return {}


func create_canonical_item_graph_snapshot() -> Dictionary:
	return {}


func create_resource_mining_snapshot() -> Dictionary:
	return {}


func product_seam_authority_report() -> Dictionary:
	var report: Dictionary = super.product_seam_authority_report()
	report["movement_only"] = true
	report["canonical_state_owned"] = false
	report["canonical_domain_count"] = 0
	report["canonical_item_graph_ready"] = false
	report["resource_mining_ready"] = false
	report["shared_item_ready"] = false
	return report


func shutdown() -> Dictionary:
	if _live_player_port != null:
		_live_player_port.shutdown()
		_live_player_port = null
	_operation_ledger.clear()
	_ownership = null
	_players = null
	_movement = null
	_shared_items = null
	_result_router = null
	_replication = null
	_item_graph_service = null
	_container_interactions = null
	_mount_interactions = null
	_playable_backend = null
	_canonical_multiplayer_items = null
	_resource_mining = null
	_resource_spatial_resolver = null
	_configured = false
	return _movement_success()


static func _movement_success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _movement_failure(
	error_code: String,
	details: Dictionary = {}
) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
