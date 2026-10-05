extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

# Native product authority used by USER1-SEM1.
#
# This is still the existing NetworkedGameplayService owner. The only change is
# selecting the product-specialized SM1 player-transfer port and exposing a
# bounded replication-revision hook for the primary service while a player is
# physically owned by the secondary movement authority.

const ProductPlayerTransferPort = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_player_transfer_port.gd"
)
const ProductUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")


func get_live_player_transfer_port():
	if not _configured or _profile != PROFILE_MULTIPLAYER_CORE:
		return null
	if _live_player_port == null:
		_live_player_port = ProductPlayerTransferPort.new()
		var configured: Dictionary = _live_player_port.configure(
			self,
			_players,
			_ownership,
			_canonical_multiplayer_items,
			_authority_owner_id,
			_authority_epoch
		)
		if not bool(configured.get("success", false)):
			_live_player_port = null
	return _live_player_port


func export_live_player_replay(logical_id: String) -> Dictionary:
	var exported: Dictionary = super.export_live_player_replay(logical_id)
	var operation_ids := _operation_ledger.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		var operation_id := String(operation_id_value)
		if exported.has(operation_id):
			continue
		var entry: Dictionary = Dictionary(_operation_ledger[operation_id])
		var result: Dictionary = Dictionary(entry.get("result", {}))
		var actor_value = result.get("details", {}).get("player", {})
		if not actor_value is Dictionary:
			continue
		var actor: Dictionary = actor_value
		if String(actor.get("logical_player_id", "")) != logical_id:
			continue
		# Ordinary JOIN / presentation outcomes predate live handoff and are not
		# tagged with live_player_id. Bind only the actor-local receipt; never
		# carry a whole-world snapshot to the other movement authority.
		exported[operation_id] = {
			"fingerprint": String(entry.get("fingerprint", "")),
			"live_player_id": logical_id,
			"source_result_checksum": String(
				entry.get("source_result_checksum", ProductUtils.payload_hash(result))
			),
			"result": {
				"success": bool(result.get("success", false)),
				"error_code": String(result.get("error_code", "")),
				"details": {"player": actor.duplicate(true)},
			},
		}
	return exported


func note_product_seam_projection_change() -> Dictionary:
	if not _configured:
		return _failure("NETWORKED_GAMEPLAY_SERVICE_NOT_READY")
	# Fixed server tick is already advanced by the M3 scheduler on every
	# authority. Only the shared snapshot revision needs to advance when a
	# secondary-owned player changes.
	_revision += 1
	return _success({"revision": _revision, "server_tick": _tick})


func product_seam_authority_report() -> Dictionary:
	return {
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"server_tick": _tick,
		"live_player_port": (
			_live_player_port.get_report()
			if _live_player_port != null
			else {}
		),
	}


func shutdown() -> Dictionary:
	if _live_player_port != null:
		_live_player_port.shutdown()
		_live_player_port = null
	return super.shutdown()
