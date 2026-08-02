extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const LeaseScript = preload("res://scripts/simulation/matter/handoff/matter_authority_lease.gd")

var _configured: bool = false
var _owner_id: String = ""
var _authority_epoch: int = 0
var _directory = null


func configure(owner_id: String, authority_epoch: int, directory) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("MATTER_REGIONAL_AUTHORITY_GATE_ALREADY_CONFIGURED")
	if not MatterUtilsScript.is_canonical_id(owner_id, 2) or authority_epoch < 1 \
			or directory == null or not directory.has_method("resolve_brick_address"):
		return MatterUtilsScript.failure("INVALID_MATTER_REGIONAL_AUTHORITY_GATE_CONFIGURATION")
	_owner_id = owner_id.strip_edges().to_lower()
	_authority_epoch = authority_epoch
	_directory = directory
	_configured = true
	return MatterUtilsScript.success()


func authorize_mutation(request: Dictionary) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_REGIONAL_AUTHORITY_GATE_NOT_CONFIGURED")
	var validation: Dictionary = RequestScript.validate(request)
	if not bool(validation.get("success", false)):
		return MatterUtilsScript.failure("INVALID_REGIONAL_MATTER_MUTATION_REQUEST")
	var region_id: String = ""
	for address_value in request["target_bricks"]:
		var address: Dictionary = address_value
		var lease: Dictionary = _directory.resolve_brick_address(address)
		if lease.is_empty():
			return MatterUtilsScript.failure("MATTER_MUTATION_OUTSIDE_AUTHORITY_REGIONS")
		var region: Dictionary = LeaseScript.decode_region(lease)
		var candidate_region_id: String = String(region.get("region_id", ""))
		if region_id.is_empty():
			region_id = candidate_region_id
		elif candidate_region_id != region_id:
			return MatterUtilsScript.failure("MATTER_CROSS_REGION_MUTATION_REQUIRES_COORDINATION")
		if String(lease["status"]) == "PREPARING":
			if String(lease["owner_id"]) == _owner_id \
					and int(lease["authority_epoch"]) == _authority_epoch:
				return MatterUtilsScript.failure("MATTER_AUTHORITY_HANDOFF_IN_PROGRESS")
			return MatterUtilsScript.failure("MATTER_REGION_NOT_OWNED_BY_SERVER")
		if String(lease["owner_id"]) != _owner_id \
				or int(lease["authority_epoch"]) != _authority_epoch:
			return MatterUtilsScript.failure("MATTER_REGION_NOT_OWNED_BY_SERVER")
	return MatterUtilsScript.success({"region_id": region_id})


func owns_region(region_id: String) -> bool:
	if not _configured:
		return false
	var lease: Dictionary = _directory.resolve_region(region_id)
	return not lease.is_empty() and String(lease.get("status", "")) == "ACTIVE" \
		and String(lease.get("owner_id", "")) == _owner_id \
		and int(lease.get("authority_epoch", 0)) == _authority_epoch


func owner_id() -> String:
	return _owner_id


func authority_epoch() -> int:
	return _authority_epoch
