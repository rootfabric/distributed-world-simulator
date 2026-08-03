extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const MatterSubscription = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const InterestRequest = preload("res://scripts/simulation/representation/contracts/representation_interest_request.gd")
const StreamRequest = preload("res://scripts/simulation/representation/network/contracts/representation_stream_request.gd")
const ScopeBinding = preload("res://scripts/simulation/representation/network/contracts/representation_stream_scope_binding.gd")


static func project(
	subscription: Dictionary,
	source_revision: Dictionary,
	scope_chain: Array,
	distance_m: float,
	projection_scale_px: float,
	maximum_screen_error_px: float,
	maximum_geometric_error_m: float,
	collision_required: bool,
	interior_required: bool,
	bandwidth_budget_bytes: int,
	preferred_artifact_kinds: Array,
	cached_artifact_hashes: Array,
	supported_encodings: Array,
	progressive_loading: bool,
	maximum_bootstrap_screen_error_px: float,
	maximum_stages: int,
	maximum_chunk_bytes: int,
	maximum_in_flight_bytes: int,
	priority: int,
	cancellation_generation: int
) -> Dictionary:
	var checked: Dictionary = MatterSubscription.validate(subscription)
	if not bool(checked.get("success", false)):
		return checked
	checked = SourceRevision.validate(source_revision)
	if not bool(checked.get("success", false)):
		return checked
	if String(source_revision["source_domain"]) != "MATTER":
		return Utils.failure("MATTER_REPRESENTATION_SOURCE_DOMAIN_REQUIRED")
	if int(subscription["authority_epoch"]) != int(source_revision["authority_epoch"]):
		return Utils.failure("MATTER_REPRESENTATION_AUTHORITY_EPOCH_MISMATCH")
	if scope_chain.is_empty():
		return Utils.failure("INVALID_MATTER_REPRESENTATION_SCOPE_CHAIN")
	for binding in scope_chain:
		if typeof(binding) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_MATTER_REPRESENTATION_SCOPE_CHAIN")
		checked = ScopeBinding.validate(binding)
		if not bool(checked.get("success", false)):
			return checked
	var suffix: String = Utils.payload_hash({
		"subscription_checksum": subscription["checksum"],
		"source_checksum": source_revision["checksum"],
		"scope_chain": scope_chain,
	}).substr(0, 24)
	var interest: Dictionary = InterestRequest.create(
		"interest/%s" % suffix,
		String(subscription["client_id"]),
		source_revision,
		distance_m,
		projection_scale_px,
		maximum_screen_error_px,
		maximum_geometric_error_m,
		collision_required,
		interior_required,
		bandwidth_budget_bytes,
		preferred_artifact_kinds,
		int(subscription["interest_revision"])
	)
	if interest.is_empty():
		return Utils.failure("MATTER_REPRESENTATION_INTEREST_PROJECTION_FAILED")
	var request: Dictionary = StreamRequest.create(
		"stream-request/%s" % suffix,
		interest,
		scope_chain,
		cached_artifact_hashes,
		supported_encodings,
		progressive_loading,
		maximum_bootstrap_screen_error_px,
		maximum_stages,
		maximum_chunk_bytes,
		maximum_in_flight_bytes,
		priority,
		cancellation_generation
	)
	if request.is_empty():
		return Utils.failure("MATTER_REPRESENTATION_STREAM_PROJECTION_FAILED")
	return Utils.success({"stream_request": request})
