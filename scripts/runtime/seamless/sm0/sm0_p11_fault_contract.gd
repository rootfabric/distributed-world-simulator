extends RefCounted

const AUTHORITIES: Array[String] = [
	"authority/sm0/a",
	"authority/sm0/b",
	"authority/sm0/c",
]
const AGGREGATE_KINDS: Array[String] = ["PLAYER", "ITEM", "VEHICLE"]
const SCHEMA := "distributed_world_simulator.sm0_p11_fault_matrix.v1"

static func transfer_signature(operation_id: String, aggregate_id: String, identity_id: String, source_authority_id: String, target_authority_id: String, source_epoch: int, topology_revision: int) -> String:
	return ("%s|%s|%s|%s|%s|%d|%d|%d" % [operation_id, aggregate_id, identity_id, source_authority_id, target_authority_id, source_epoch, source_epoch + 1, topology_revision]).sha256_text()

static func retirement_token(operation_id: String, aggregate_id: String, identity_id: String, source_authority_id: String, target_authority_id: String, source_epoch: int, target_epoch: int) -> String:
	return "retired:%s" % (("%s|%s|%s|%s|%s|%d|%d" % [operation_id, aggregate_id, identity_id, source_authority_id, target_authority_id, source_epoch, target_epoch]).sha256_text())

static func valid_authority(authority_id: String) -> bool:
	return authority_id in AUTHORITIES

static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
