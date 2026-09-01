extends RefCounted

const MatterSubscription = preload(
	"res://scripts/simulation/matter/interest/matter_interest_subscription.gd"
)
const RepresentationSource = preload(
	"res://scripts/simulation/representation/contracts/representation_source_revision.gd"
)
const RepresentationStreamRequest = preload(
	"res://scripts/simulation/representation/network/contracts/representation_stream_request.gd"
)
const GameplaySnapshot = preload(
	"res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd"
)
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

## P7.5 is a stateless convergence observer over already-owned replication
## surfaces. It does not send frames, mutate Matter, own Item Graph state, hold
## receipts, or allocate a second aggregate revision. The caller supplies two
## client observations produced by MW7 / gameplay replication / M7 / RL3.

func evaluate(
	matter_client_a,
	matter_client_b,
	gameplay_snapshot_a: Dictionary,
	gameplay_snapshot_b: Dictionary,
	item_replica_a: Dictionary,
	item_replica_b: Dictionary,
	canonical_item_snapshot: Dictionary,
	representation_request_a: Dictionary,
	representation_request_b: Dictionary
) -> Dictionary:
	var matter_a := _matter_observation(matter_client_a)
	if not bool(matter_a.get("success", false)):
		return matter_a
	var matter_b := _matter_observation(matter_client_b)
	if not bool(matter_b.get("success", false)):
		return matter_b

	var a: Dictionary = matter_a["details"]
	var b: Dictionary = matter_b["details"]
	if a["scope"] != b["scope"]:
		return _failure("P7_5_MATTER_INTEREST_SCOPE_DIVERGED")
	if int(a["source_global_stream_sequence"]) != int(b["source_global_stream_sequence"]):
		return _failure("P7_5_MATTER_CURSOR_DIVERGED")
	if String(a["store_hash"]) != String(b["store_hash"]) 			or a["address_rows"] != b["address_rows"]:
		return _failure("P7_5_MATTER_STATE_DIVERGED")

	var gameplay_check := _gameplay_converged(gameplay_snapshot_a, gameplay_snapshot_b)
	if not bool(gameplay_check.get("success", false)):
		return gameplay_check
	var item_check := _item_graph_converged(
		item_replica_a,
		item_replica_b,
		canonical_item_snapshot
	)
	if not bool(item_check.get("success", false)):
		return item_check
	var representation_check := _representation_converged(
		representation_request_a,
		representation_request_b,
		int(a["source_global_stream_sequence"]),
		String(a["store_hash"])
	)
	if not bool(representation_check.get("success", false)):
		return representation_check

	var gameplay: Dictionary = gameplay_check["details"]
	var item: Dictionary = item_check["details"]
	var representation: Dictionary = representation_check["details"]
	var identity := {
		"matter_source_global_stream_sequence": int(a["source_global_stream_sequence"]),
		"matter_store_hash": String(a["store_hash"]),
		"gameplay_revision": int(gameplay["revision"]),
		"gameplay_checksum": String(gameplay["checksum"]),
		"item_graph_revision": int(item["revision"]),
		"item_graph_checksum": String(item["checksum"]),
		"representation_source_checksum": String(representation["source_checksum"]),
	}
	return _success({
		"converged": true,
		"identity": identity,
		"convergence_hash": NetworkUtils.payload_hash(identity),
		"matter": a,
		"gameplay": gameplay,
		"item_graph": item,
		"representation": representation,
	})


func contract_report() -> Dictionary:
	return {
		"schema": "planet_simulator.p7_5_two_client_convergence_observer.v1",
		"canonical_state_owned": false,
		"network_frames_sent": false,
		"persistent_state_owned": false,
		"delivery_receipt_store": false,
		"replay_ledger_owned": false,
		"replication_owner": "MW6",
		"interest_owner": "MW7",
		"meshing_owner": "RL2",
		"representation_stream_owner": "RL3",
		"item_owner": "CANONICAL_ITEM_GRAPH",
		"item_replica_owner": "M7_ITEM_GRAPH_REPLICA_ADAPTER",
		"aggregate_revision_owner": "NETWORKED_GAMEPLAY_SERVICE",
		"matter_projection_hash_compared_between_clients": false,
		"matter_projection_hash_reason": "MW7 projection hash intentionally includes client/subscription identity; P7.5 compares shared canonical cursor and sparse-store content instead.",
	}


func _matter_observation(client) -> Dictionary:
	if client == null:
		return _failure("P7_5_MATTER_CLIENT_REQUIRED")
	for method_name in [
		"report",
		"subscription",
		"pending_subscription",
		"snapshot_store",
		"requires_resync",
		"source_global_stream_sequence",
	]:
		if not client.has_method(method_name):
			return _failure("P7_5_MW7_CLIENT_SURFACE_REQUIRED", {
				"method": method_name,
			})
	var report: Dictionary = client.report()
	if String(report.get("schema", "")) != "planet_simulator.matter_interest_replica_report.v1":
		return _failure("P7_5_MW7_CLIENT_REPORT_INVALID")
	var subscription: Dictionary = client.subscription()
	var subscription_validation: Dictionary = MatterSubscription.validate(subscription)
	if not bool(subscription_validation.get("success", false)):
		return _failure("P7_5_MW7_SUBSCRIPTION_INVALID")
	if not client.pending_subscription().is_empty():
		return _failure("P7_5_MATTER_INTEREST_UPDATE_PENDING")
	if bool(client.requires_resync()):
		return _failure("P7_5_MATTER_CLIENT_REQUIRES_RESYNC")
	var store = client.snapshot_store()
	if store == null 		or not store.has_method("content_hash") 		or not store.has_method("address_ids") 		or not store.has_method("get_snapshot_by_address_id"):
		return _failure("P7_5_MATTER_STORE_SURFACE_REQUIRED")
	var store_hash := String(store.content_hash())
	if not _is_hash(store_hash):
		return _failure("P7_5_MATTER_STORE_HASH_INVALID")
	var address_ids: Array = store.address_ids()
	address_ids.sort()
	var rows: Array = []
	for raw_address_id in address_ids:
		var address_id := String(raw_address_id)
		var snapshot: Dictionary = store.get_snapshot_by_address_id(address_id)
		var checksum := String(snapshot.get("checksum", ""))
		if address_id.is_empty() or int(snapshot.get("state_revision", 0)) < 1 			or not _is_hash(checksum):
			return _failure("P7_5_MATTER_SNAPSHOT_IDENTITY_INVALID", {
				"address_id": address_id,
			})
		rows.append({
			"address_id": address_id,
			"state_revision": int(snapshot["state_revision"]),
			"checksum": checksum,
		})
	return _success({
		"scope": _shared_scope(subscription),
		"source_global_stream_sequence": int(client.source_global_stream_sequence()),
		"store_hash": store_hash,
		"address_rows": rows,
		"persistent_snapshot_count": rows.size(),
	})


func _gameplay_converged(a: Dictionary, b: Dictionary) -> Dictionary:
	var a_validation: Dictionary = GameplaySnapshot.validate_legacy(a)
	if not bool(a_validation.get("success", false)):
		return _failure("P7_5_GAMEPLAY_SNAPSHOT_A_INVALID")
	var b_validation: Dictionary = GameplaySnapshot.validate_legacy(b)
	if not bool(b_validation.get("success", false)):
		return _failure("P7_5_GAMEPLAY_SNAPSHOT_B_INVALID")
	for field in ["authority_owner_id", "authority_epoch", "revision", "checksum"]:
		if a.get(field) != b.get(field):
			return _failure("P7_5_GAMEPLAY_AGGREGATE_DIVERGED", {"field": field})
	return _success({
		"authority_owner_id": String(a["authority_owner_id"]),
		"authority_epoch": int(a["authority_epoch"]),
		"revision": int(a["revision"]),
		"checksum": String(a["checksum"]),
	})


func _item_graph_converged(
	a: Dictionary,
	b: Dictionary,
	canonical: Dictionary
) -> Dictionary:
	var revision := int(canonical.get("revision", -1))
	var checksum := String(canonical.get("checksum", ""))
	if revision < 0 or not _is_hash(checksum):
		return _failure("P7_5_CANONICAL_ITEM_GRAPH_INVALID")
	for observation in [a, b]:
		if int(observation.get("canonical_revision", -2)) != revision 			or String(observation.get("canonical_checksum", "")) != checksum:
			return _failure("P7_5_ITEM_GRAPH_REPLICA_DIVERGED")
		var replica_snapshot = observation.get("replica_snapshot", {})
		if not replica_snapshot is Dictionary 			or int(Dictionary(replica_snapshot).get("state_revision", -2)) != revision 			or String(Dictionary(replica_snapshot).get("checksum", "")) != checksum:
			return _failure("P7_5_ITEM_GRAPH_REPLICA_BINDING_INVALID")
	return _success({"revision": revision, "checksum": checksum})


func _representation_converged(
	request_a: Dictionary,
	request_b: Dictionary,
	matter_revision: int,
	matter_store_hash: String
) -> Dictionary:
	for value in [request_a, request_b]:
		var checked: Dictionary = RepresentationStreamRequest.validate(value)
		if not bool(checked.get("success", false)):
			return _failure("P7_5_RL3_STREAM_REQUEST_INVALID")
	var source_a: Dictionary = Dictionary(
		Dictionary(request_a.get("interest_request", {})).get("source_revision", {})
	)
	var source_b: Dictionary = Dictionary(
		Dictionary(request_b.get("interest_request", {})).get("source_revision", {})
	)
	if not bool(RepresentationSource.validate(source_a).get("success", false)) 		or not bool(RepresentationSource.validate(source_b).get("success", false)):
		return _failure("P7_5_REPRESENTATION_SOURCE_INVALID")
	if source_a != source_b:
		return _failure("P7_5_REPRESENTATION_SOURCE_DIVERGED")
	if String(source_a.get("source_domain", "")) != "MATTER" 		or int(source_a.get("source_revision", -1)) != matter_revision 		or String(source_a.get("source_hash", "")) != matter_store_hash:
		return _failure("P7_5_REPRESENTATION_SOURCE_NOT_BOUND_TO_MATTER")
	return _success({
		"source_checksum": String(source_a["checksum"]),
		"source_revision": int(source_a["source_revision"]),
		"source_hash": String(source_a["source_hash"]),
	})


func _shared_scope(subscription: Dictionary) -> Dictionary:
	var center: Dictionary = subscription.get("center_cell_address", {})
	return {
		"authority_epoch": int(subscription.get("authority_epoch", 0)),
		"cell_level": int(subscription.get("cell_level", -1)),
		"center_cell_id": String(center.get("cell_id", "")),
		"radius_cells": int(subscription.get("radius_cells", -1)),
	}


func _is_hash(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not (
			(character >= "0" and character <= "9")
			or (character >= "a" and character <= "f")
		):
			return false
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
