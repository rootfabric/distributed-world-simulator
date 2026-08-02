extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const SubscriptionScript = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")


static func validate_subscription(grid_profile: Dictionary, subscription: Dictionary) -> Dictionary:
	var subscription_validation: Dictionary = SubscriptionScript.validate(subscription)
	if not bool(subscription_validation.get("success", false)):
		return subscription_validation
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_GRID")
	var center: Dictionary = subscription["center_cell_address"]
	var center_validation: Dictionary = CellGridScript.validate_address(grid_profile, center)
	if not bool(center_validation.get("success", false)):
		return MatterUtilsScript.failure("MATTER_INTEREST_CENTER_GRID_MISMATCH")
	if int(subscription["cell_level"]) > int(grid_profile["max_level"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_LEVEL_EXCEEDS_GRID")
	return MatterUtilsScript.success()


static func indices_for_cell(cell_address: Dictionary) -> Array:
	if not bool(CellAddressScript.validate(cell_address).get("success", false)):
		return []
	var x: int = 0
	var y: int = 0
	var z: int = 0
	for raw_child in cell_address["path"]:
		var child_index: int = int(raw_child)
		x = (x << 1) | (child_index & 1)
		y = (y << 1) | ((child_index >> 1) & 1)
		z = (z << 1) | ((child_index >> 2) & 1)
	return [x, y, z]


static func cell_for_indices(
	grid_profile: Dictionary,
	level: int,
	x: int,
	y: int,
	z: int
) -> Dictionary:
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
			or level < 0 or level > int(grid_profile["max_level"]):
		return {}
	var axis_count: int = 1 << level
	if x < 0 or y < 0 or z < 0 or x >= axis_count or y >= axis_count or z >= axis_count:
		return {}
	var path: Array = []
	for shift in range(level - 1, -1, -1):
		var child_index: int = ((x >> shift) & 1) \
			| (((y >> shift) & 1) << 1) \
			| (((z >> shift) & 1) << 2)
		path.append(child_index)
	return CellAddressScript.create(
		String(grid_profile["universe_id"]),
		String(grid_profile["instance_id"]),
		String(grid_profile["space_id"]),
		String(grid_profile["grid_id"]),
		int(grid_profile["grid_revision"]),
		String(grid_profile["root_id"]),
		path
	)


static func cell_addresses(grid_profile: Dictionary, subscription: Dictionary) -> Array[Dictionary]:
	if not bool(validate_subscription(grid_profile, subscription).get("success", false)):
		return []
	var level: int = int(subscription["cell_level"])
	var center_indices: Array = indices_for_cell(subscription["center_cell_address"])
	if center_indices.size() != 3:
		return []
	var radius: int = int(subscription["radius_cells"])
	var axis_count: int = 1 << level
	var result: Array[Dictionary] = []
	for z in range(maxi(0, int(center_indices[2]) - radius), mini(axis_count - 1, int(center_indices[2]) + radius) + 1):
		for y in range(maxi(0, int(center_indices[1]) - radius), mini(axis_count - 1, int(center_indices[1]) + radius) + 1):
			for x in range(maxi(0, int(center_indices[0]) - radius), mini(axis_count - 1, int(center_indices[0]) + radius) + 1):
				var address: Dictionary = cell_for_indices(grid_profile, level, x, y, z)
				if not address.is_empty():
					result.append(address)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	return result


static func contains_cell_address(
	grid_profile: Dictionary,
	subscription: Dictionary,
	cell_address: Dictionary
) -> bool:
	if not bool(validate_subscription(grid_profile, subscription).get("success", false)) \
			or not bool(CellGridScript.validate_address(grid_profile, cell_address).get("success", false)) \
			or int(cell_address["level"]) != int(subscription["cell_level"]):
		return false
	var center_indices: Array = indices_for_cell(subscription["center_cell_address"])
	var target_indices: Array = indices_for_cell(cell_address)
	if center_indices.size() != 3 or target_indices.size() != 3:
		return false
	var radius: int = int(subscription["radius_cells"])
	return absi(int(target_indices[0]) - int(center_indices[0])) <= radius \
		and absi(int(target_indices[1]) - int(center_indices[1])) <= radius \
		and absi(int(target_indices[2]) - int(center_indices[2])) <= radius


static func contains_snapshot(
	grid_profile: Dictionary,
	subscription: Dictionary,
	snapshot: Dictionary
) -> bool:
	if typeof(snapshot.get("address")) != TYPE_DICTIONARY \
			or typeof(snapshot["address"].get("cell_address")) != TYPE_DICTIONARY:
		return false
	return contains_cell_address(
		grid_profile,
		subscription,
		snapshot["address"]["cell_address"]
	)


static func projection_store_hash(
	body_definition_hash: String,
	grid_profile_hash: String,
	snapshots_by_address_id: Dictionary
) -> String:
	var address_ids: Array = snapshots_by_address_id.keys()
	address_ids.sort()
	var entries: Array = []
	for raw_address_id in address_ids:
		var address_id: String = String(raw_address_id)
		var snapshot: Dictionary = snapshots_by_address_id[address_id]
		entries.append({
			"address_id": address_id,
			"state_revision": int(snapshot["state_revision"]),
			"snapshot_checksum": String(snapshot["checksum"]),
		})
	return MatterUtilsScript.payload_hash({
		"body_definition_hash": body_definition_hash,
		"grid_profile_hash": grid_profile_hash,
		"entries": entries,
	})


static func projection_hash(
	body_id: String,
	authority_owner_id: String,
	authority_epoch: int,
	subscription: Dictionary,
	region_sequence: int,
	source_global_stream_sequence: int,
	store_hash: String
) -> String:
	return MatterUtilsScript.payload_hash({
		"body_id": body_id,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"subscription_id": subscription.get("subscription_id", ""),
		"interest_revision": subscription.get("interest_revision", 0),
		"subscription_checksum": subscription.get("checksum", ""),
		"region_sequence": region_sequence,
		"source_global_stream_sequence": source_global_stream_sequence,
		"store_hash": store_hash,
	})


static func snapshots_from_store(store, grid_profile: Dictionary, subscription: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if store == null or not store.has_method("address_ids") \
			or not store.has_method("get_snapshot_by_address_id"):
		return result
	for raw_address_id in store.address_ids():
		var address_id: String = String(raw_address_id)
		var snapshot: Dictionary = store.get_snapshot_by_address_id(address_id)
		if int(snapshot.get("state_revision", 0)) < 1:
			continue
		if contains_snapshot(grid_profile, subscription, snapshot):
			result[address_id] = snapshot.duplicate(true)
	return result
