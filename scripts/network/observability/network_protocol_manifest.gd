extends RefCounted

const P2Manifest = preload(
	"res://scripts/network/observability/network_protocol_manifest_p2.gd"
)
const FingerprintScript = preload(
	"res://scripts/network/observability/network_build_fingerprint.gd"
)
const ResourceMineCommand = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mine_command.gd"
)
const ResourceMiningSnapshot = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd"
)
const ResourceMiningDelta = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_delta.gd"
)
const ResourceMiningService = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_service.gd"
)

const SCHEMA: String = P2Manifest.SCHEMA
const MANIFEST_VERSION: int = P2Manifest.MANIFEST_VERSION
const M3_MESSAGE_SCHEMA: String = P2Manifest.M3_MESSAGE_SCHEMA
const FIELDS: Array[String] = [
	"schema", "manifest_version", "contract_versions", "channel_policy", "protocol_hash",
]


static func create() -> Dictionary:
	var contracts := contract_versions()
	var channels := channel_policy()
	return {
		"schema": SCHEMA,
		"manifest_version": MANIFEST_VERSION,
		"contract_versions": contracts,
		"channel_policy": channels,
		"protocol_hash": FingerprintScript.compute_protocol_hash(contracts, channels),
	}


static func current_protocol_hash() -> String:
	return String(create().get("protocol_hash", ""))


static func contract_versions() -> Dictionary:
	var contracts: Dictionary = P2Manifest.contract_versions().duplicate(true)
	contracts["resource_mine_command"] = {
		"schema": ResourceMineCommand.SCHEMA,
		"command_type": ResourceMineCommand.COMMAND_TYPE,
		"transport_message_type": "RESOURCE_COMMAND",
	}
	contracts["resource_mining_snapshot"] = {
		"schema": ResourceMiningSnapshot.SCHEMA,
		"transport_message_type": "RESOURCE_SNAPSHOT",
	}
	contracts["resource_mining_delta"] = {
		"schema": ResourceMiningDelta.SCHEMA,
		"transport_message_type": "RESOURCE_DELTA",
	}
	contracts["resource_mining_policy"] = {
		"mining_range_m": ResourceMiningService.MINING_RANGE_M,
		"command_channel": "CONTROL",
		"delta_channel": "ITEM",
		"snapshot_channel": "RESYNC",
	}
	return contracts


static func channel_policy() -> Dictionary:
	return P2Manifest.channel_policy().duplicate(true)


static func validate(value: Dictionary) -> Dictionary:
	var exact := _validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("UNSUPPORTED_SCHEMA")
	if int(value.get("manifest_version", 0)) != MANIFEST_VERSION:
		return _failure("UNSUPPORTED_MANIFEST_VERSION")
	if not value.get("contract_versions") is Dictionary or not value.get("channel_policy") is Dictionary:
		return _failure("INVALID_PROTOCOL_COMPONENTS")
	var expected := create()
	if Dictionary(value.get("contract_versions", {})) != Dictionary(expected["contract_versions"]):
		return _failure("CONTRACT_VERSION_DRIFT")
	if Dictionary(value.get("channel_policy", {})) != Dictionary(expected["channel_policy"]):
		return _failure("CHANNEL_POLICY_DRIFT")
	if String(value.get("protocol_hash", "")) != String(expected["protocol_hash"]):
		return _failure("PROTOCOL_HASH_MISMATCH")
	return _success()


static func _validate_exact_fields(value: Dictionary, expected: Array[String]) -> Dictionary:
	var actual: Array[String] = []
	for key_value in value.keys():
		actual.append(String(key_value))
	actual.sort()
	var sorted_expected: Array[String] = expected.duplicate()
	sorted_expected.sort()
	return _success() if actual == sorted_expected else _failure("FIELD_SET_MISMATCH", {
		"expected": sorted_expected,
		"actual": actual,
	})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
