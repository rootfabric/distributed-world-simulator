extends RefCounted
# SM0 P9 authority-envelope contract only. Canonical item contents remain owned by the existing Item Graph; this lab does not create a second Item Graph.


const ITEM_ENVELOPE_SCHEMA := "distributed_world_simulator.sm0_p9_item_authority_envelope.v1"
const INTERACTION_SCHEMA := "distributed_world_simulator.sm0_p9_foreign_interaction.v1"
const TRANSFER_SCHEMA := "distributed_world_simulator.sm0_p9_boundary_transfer.v1"
const RETIREMENT_SCHEMA := "distributed_world_simulator.sm0_p9_retirement_proof.v1"

const AUTHORITY_A := "authority/sm0/a"
const AUTHORITY_C := "authority/sm0/c"
const SHIP_AUTHORITY := "authority/island/ship/01"
const WORLD_AUTHORITIES: Array[String] = [AUTHORITY_A, AUTHORITY_C]
const ALL_AUTHORITIES: Array[String] = [AUTHORITY_A, AUTHORITY_C, SHIP_AUTHORITY]

const SCOPE_WORLD := "WORLD"
const SCOPE_SHIP := "SHIP"
const SCOPES: Array[String] = [SCOPE_WORLD, SCOPE_SHIP]

const INTERACTION_USE := "USE"
const INTERACTION_INSPECT := "INSPECT"
const INTERACTIONS: Array[String] = [INTERACTION_USE, INTERACTION_INSPECT]

static func create_item_envelope(
	item_id: String,
	owner_authority_id: String,
	authority_scope: String,
	ownership_epoch: int = 1,
	item_revision: int = 1,
	interaction_sequence: int = 0
) -> Dictionary:
	var value := {
		"schema": ITEM_ENVELOPE_SCHEMA,
		"item_id": item_id.strip_edges(),
		"owner_authority_id": owner_authority_id.strip_edges(),
		"authority_scope": authority_scope.strip_edges(),
		"ownership_epoch": ownership_epoch,
		"item_revision": item_revision,
		"interaction_sequence": interaction_sequence,
		"checksum": "",
	}
	value["checksum"] = item_checksum(value)
	return value

static func validate_item_envelope(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, ["schema", "item_id", "owner_authority_id", "authority_scope", "ownership_epoch", "item_revision", "interaction_sequence", "checksum"]):
		return _failure("SM0_P9_ITEM_FIELDS_INVALID")
	if String(value.get("schema", "")) != ITEM_ENVELOPE_SCHEMA:
		return _failure("SM0_P9_ITEM_SCHEMA_INVALID")
	if String(value.get("item_id", "")).strip_edges().is_empty():
		return _failure("SM0_P9_ITEM_ID_REQUIRED")
	var owner := String(value.get("owner_authority_id", ""))
	var scope := String(value.get("authority_scope", ""))
	if owner not in ALL_AUTHORITIES or scope not in SCOPES:
		return _failure("SM0_P9_ITEM_AUTHORITY_INVALID")
	if scope == SCOPE_SHIP and owner != SHIP_AUTHORITY:
		return _failure("SM0_P9_SHIP_SCOPE_OWNER_INVALID")
	if scope == SCOPE_WORLD and owner not in WORLD_AUTHORITIES:
		return _failure("SM0_P9_WORLD_SCOPE_OWNER_INVALID")
	if not _is_nonnegative_integer(value.get("interaction_sequence")):
		return _failure("SM0_P9_INTERACTION_SEQUENCE_INVALID")
	if not _is_positive_integer(value.get("ownership_epoch")) or not _is_positive_integer(value.get("item_revision")):
		return _failure("SM0_P9_ITEM_REVISION_INVALID")
	if String(value.get("checksum", "")) != item_checksum(value):
		return _failure("SM0_P9_ITEM_CHECKSUM_MISMATCH")
	return _success()

static func create_interaction_request(
	operation_id: String,
	actor_authority_id: String,
	item: Dictionary,
	interaction_kind: String
) -> Dictionary:
	var value := {
		"schema": INTERACTION_SCHEMA,
		"operation_id": operation_id.strip_edges(),
		"actor_authority_id": actor_authority_id.strip_edges(),
		"item_id": String(item.get("item_id", "")),
		"expected_owner_authority_id": String(item.get("owner_authority_id", "")),
		"expected_ownership_epoch": int(item.get("ownership_epoch", 0)),
		"expected_item_revision": int(item.get("item_revision", 0)),
		"interaction_kind": interaction_kind.strip_edges(),
		"checksum": "",
	}
	value["checksum"] = interaction_checksum(value)
	return value

static func validate_interaction_request(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, ["schema", "operation_id", "actor_authority_id", "item_id", "expected_owner_authority_id", "expected_ownership_epoch", "expected_item_revision", "interaction_kind", "checksum"]):
		return _failure("SM0_P9_INTERACTION_FIELDS_INVALID")
	if String(value.get("schema", "")) != INTERACTION_SCHEMA:
		return _failure("SM0_P9_INTERACTION_SCHEMA_INVALID")
	if String(value.get("operation_id", "")).strip_edges().is_empty() or String(value.get("item_id", "")).strip_edges().is_empty():
		return _failure("SM0_P9_INTERACTION_ID_REQUIRED")
	if String(value.get("actor_authority_id", "")) not in ALL_AUTHORITIES or String(value.get("expected_owner_authority_id", "")) not in ALL_AUTHORITIES:
		return _failure("SM0_P9_INTERACTION_AUTHORITY_INVALID")
	if String(value.get("interaction_kind", "")) not in INTERACTIONS:
		return _failure("SM0_P9_INTERACTION_KIND_INVALID")
	if not _is_positive_integer(value.get("expected_ownership_epoch")) or not _is_positive_integer(value.get("expected_item_revision")):
		return _failure("SM0_P9_INTERACTION_REVISION_INVALID")
	if String(value.get("checksum", "")) != interaction_checksum(value):
		return _failure("SM0_P9_INTERACTION_CHECKSUM_MISMATCH")
	return _success()

static func create_transfer_request(
	operation_id: String,
	item: Dictionary,
	target_authority_id: String,
	target_scope: String
) -> Dictionary:
	var value := {
		"schema": TRANSFER_SCHEMA,
		"operation_id": operation_id.strip_edges(),
		"item": item.duplicate(true),
		"item_id": String(item.get("item_id", "")),
		"source_authority_id": String(item.get("owner_authority_id", "")),
		"target_authority_id": target_authority_id.strip_edges(),
		"source_scope": String(item.get("authority_scope", "")),
		"target_scope": target_scope.strip_edges(),
		"expected_ownership_epoch": int(item.get("ownership_epoch", 0)),
		"expected_item_revision": int(item.get("item_revision", 0)),
		"checksum": "",
	}
	value["checksum"] = transfer_checksum(value)
	return value

static func validate_transfer_request(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, ["schema", "operation_id", "item", "item_id", "source_authority_id", "target_authority_id", "source_scope", "target_scope", "expected_ownership_epoch", "expected_item_revision", "checksum"]):
		return _failure("SM0_P9_TRANSFER_FIELDS_INVALID")
	if String(value.get("schema", "")) != TRANSFER_SCHEMA:
		return _failure("SM0_P9_TRANSFER_SCHEMA_INVALID")
	if String(value.get("operation_id", "")).strip_edges().is_empty() or String(value.get("item_id", "")).strip_edges().is_empty():
		return _failure("SM0_P9_TRANSFER_ID_REQUIRED")
	var item := Dictionary(value.get("item", {}))
	var item_check := validate_item_envelope(item)
	if not bool(item_check.get("success", false)):
		return _failure("SM0_P9_TRANSFER_ITEM_INVALID", {"cause": item_check})
	if String(item.get("item_id", "")) != String(value.get("item_id", "")):
		return _failure("SM0_P9_TRANSFER_ITEM_ID_MISMATCH")
	var source := String(value.get("source_authority_id", ""))
	var target := String(value.get("target_authority_id", ""))
	var source_scope := String(value.get("source_scope", ""))
	var target_scope := String(value.get("target_scope", ""))
	if source == target or source not in ALL_AUTHORITIES or target not in ALL_AUTHORITIES:
		return _failure("SM0_P9_TRANSFER_ENDPOINT_INVALID")
	if source_scope == target_scope or source_scope not in SCOPES or target_scope not in SCOPES:
		return _failure("SM0_P9_TRANSFER_SCOPE_INVALID")
	if source_scope == SCOPE_WORLD and source not in WORLD_AUTHORITIES:
		return _failure("SM0_P9_TRANSFER_SOURCE_OWNER_INVALID")
	if source_scope == SCOPE_SHIP and source != SHIP_AUTHORITY:
		return _failure("SM0_P9_TRANSFER_SOURCE_OWNER_INVALID")
	if target_scope == SCOPE_WORLD and target not in WORLD_AUTHORITIES:
		return _failure("SM0_P9_TRANSFER_TARGET_OWNER_INVALID")
	if target_scope == SCOPE_SHIP and target != SHIP_AUTHORITY:
		return _failure("SM0_P9_TRANSFER_TARGET_OWNER_INVALID")
	if String(item.get("owner_authority_id", "")) != source or String(item.get("authority_scope", "")) != source_scope:
		return _failure("SM0_P9_TRANSFER_SOURCE_ITEM_MISMATCH")
	if int(item.get("ownership_epoch", 0)) != int(value.get("expected_ownership_epoch", 0)) or int(item.get("item_revision", 0)) != int(value.get("expected_item_revision", 0)):
		return _failure("SM0_P9_TRANSFER_EXPECTATION_MISMATCH")
	if String(value.get("checksum", "")) != transfer_checksum(value):
		return _failure("SM0_P9_TRANSFER_CHECKSUM_MISMATCH")
	return _success()

static func create_retirement_proof(request: Dictionary, retired_item: Dictionary) -> Dictionary:
	var value := {
		"schema": RETIREMENT_SCHEMA,
		"operation_id": String(request.get("operation_id", "")),
		"item_id": String(request.get("item_id", "")),
		"source_authority_id": String(request.get("source_authority_id", "")),
		"source_item_checksum": String(retired_item.get("checksum", "")),
		"source_ownership_epoch": int(retired_item.get("ownership_epoch", 0)),
		"source_item_revision": int(retired_item.get("item_revision", 0)),
		"source_retired": true,
		"checksum": "",
	}
	value["checksum"] = retirement_checksum(value)
	return value

static func validate_retirement_proof(value: Dictionary, request: Dictionary) -> Dictionary:
	if not _exact_fields(value, ["schema", "operation_id", "item_id", "source_authority_id", "source_item_checksum", "source_ownership_epoch", "source_item_revision", "source_retired", "checksum"]):
		return _failure("SM0_P9_RETIREMENT_FIELDS_INVALID")
	if String(value.get("schema", "")) != RETIREMENT_SCHEMA or not bool(value.get("source_retired", false)):
		return _failure("SM0_P9_RETIREMENT_PROOF_INVALID")
	if String(value.get("operation_id", "")) != String(request.get("operation_id", "")) or String(value.get("item_id", "")) != String(request.get("item_id", "")):
		return _failure("SM0_P9_RETIREMENT_ID_MISMATCH")
	if String(value.get("source_authority_id", "")) != String(request.get("source_authority_id", "")):
		return _failure("SM0_P9_RETIREMENT_SOURCE_MISMATCH")
	var item := Dictionary(request.get("item", {}))
	if String(value.get("source_item_checksum", "")) != String(item.get("checksum", "")) or int(value.get("source_ownership_epoch", 0)) != int(item.get("ownership_epoch", 0)) or int(value.get("source_item_revision", 0)) != int(item.get("item_revision", 0)):
		return _failure("SM0_P9_RETIREMENT_ITEM_MISMATCH")
	if String(value.get("checksum", "")) != retirement_checksum(value):
		return _failure("SM0_P9_RETIREMENT_CHECKSUM_MISMATCH")
	return _success()

static func transferred_item(request: Dictionary) -> Dictionary:
	var source_item := Dictionary(request.get("item", {}))
	return create_item_envelope(
		String(source_item.get("item_id", "")),
		String(request.get("target_authority_id", "")),
		String(request.get("target_scope", "")),
		int(source_item.get("ownership_epoch", 0)) + 1,
		int(source_item.get("item_revision", 0)) + 1,
		int(source_item.get("interaction_sequence", 0))
	)

static func interacted_item(item: Dictionary) -> Dictionary:
	return create_item_envelope(
		String(item.get("item_id", "")),
		String(item.get("owner_authority_id", "")),
		String(item.get("authority_scope", "")),
		int(item.get("ownership_epoch", 0)),
		int(item.get("item_revision", 0)) + 1,
		int(item.get("interaction_sequence", 0)) + 1
	)

static func item_checksum(value: Dictionary) -> String:
	return _hash_parts([
		ITEM_ENVELOPE_SCHEMA,
		String(value.get("item_id", "")),
		String(value.get("owner_authority_id", "")),
		String(value.get("authority_scope", "")),
		str(int(value.get("ownership_epoch", 0))),
		str(int(value.get("item_revision", 0))),
		str(int(value.get("interaction_sequence", 0))),
	])

static func interaction_checksum(value: Dictionary) -> String:
	return _hash_parts([
		INTERACTION_SCHEMA,
		String(value.get("operation_id", "")),
		String(value.get("actor_authority_id", "")),
		String(value.get("item_id", "")),
		String(value.get("expected_owner_authority_id", "")),
		str(int(value.get("expected_ownership_epoch", 0))),
		str(int(value.get("expected_item_revision", 0))),
		String(value.get("interaction_kind", "")),
	])

static func transfer_checksum(value: Dictionary) -> String:
	var item := Dictionary(value.get("item", {}))
	return _hash_parts([
		TRANSFER_SCHEMA,
		String(value.get("operation_id", "")),
		String(value.get("item_id", "")),
		String(value.get("source_authority_id", "")),
		String(value.get("target_authority_id", "")),
		String(value.get("source_scope", "")),
		String(value.get("target_scope", "")),
		str(int(value.get("expected_ownership_epoch", 0))),
		str(int(value.get("expected_item_revision", 0))),
		String(item.get("checksum", "")),
	])

static func retirement_checksum(value: Dictionary) -> String:
	return _hash_parts([
		RETIREMENT_SCHEMA,
		String(value.get("operation_id", "")),
		String(value.get("item_id", "")),
		String(value.get("source_authority_id", "")),
		String(value.get("source_item_checksum", "")),
		str(int(value.get("source_ownership_epoch", 0))),
		str(int(value.get("source_item_revision", 0))),
		"1" if bool(value.get("source_retired", false)) else "0",
	])

static func _hash_parts(parts: Array[String]) -> String:
	return "\u001f".join(parts).sha256_text()

static func _exact_fields(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for field in expected:
		if not value.has(field):
			return false
	return true

static func _is_positive_integer(value: Variant) -> bool:
	return _is_integer(value) and int(value) > 0

static func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= 0

static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return is_finite(number) and number == floor(number)
	return false

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}