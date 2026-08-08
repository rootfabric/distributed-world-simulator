extends SceneTree

const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const LabSource = preload("res://scripts/characters/equipment/lab_equipment_source.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var human: Domain.Layout = _human_layout()
	var robot: Domain.Layout = _robot_layout()
	var helmet: Domain.Profile = _helmet_profile()
	var backpack: Domain.Profile = _backpack_profile()
	var eva_suit: Domain.Profile = _eva_suit_profile()

	_assert(human.is_valid(), "Humanoid layout is invalid")
	_assert(robot.is_valid(), "Robot layout is invalid")
	_assert(human.supports_anchor("body.head"), "Humanoid head anchor missing")
	_assert(human.supports_channel("body.head.outer"), "Humanoid outer head channel missing")
	_assert(human.has_capability("equipment.headwear"), "Humanoid headwear capability missing")
	_assert(not human.has_capability("equipment.hardpoint"), "Humanoid unexpectedly has robot hardpoint capability")
	_assert(helmet.is_valid(), "Helmet profile is invalid")
	_assert(backpack.is_valid(), "Backpack profile is invalid")
	_assert(eva_suit.is_valid(), "EVA suit profile is invalid")
	_assert(eva_suit.occupied_channels().size() == 3, "Full-body EVA suit must remain one profile occupying three channels")

	var empty_entries: Array = []
	var helmet_validation: Dictionary = Domain.validate_equip(human, helmet, empty_entries, "item.helmet.001")
	_assert(bool(helmet_validation.get("success", false)), "Compatible helmet was rejected")
	_assert(String(helmet_validation.get("code", "")) == Domain.RESULT_OK, "Compatible helmet returned wrong result code")

	var missing_capability: Domain.Profile = Domain.Profile.new(
		"equipment.test.scanner",
		"wearable.scanner.test",
		"body.head",
		["body.head.outer"],
		[],
		[],
		["equipment.nonexistent"]
	)
	var missing_capability_result: Dictionary = Domain.validate_equip(human, missing_capability, [], "item.scanner.001")
	_assert(String(missing_capability_result.get("code", "")) == Domain.RESULT_MISSING_CAPABILITY, "Missing capability was not rejected")

	var unsupported_anchor: Domain.Profile = Domain.Profile.new(
		"equipment.test.tail",
		"wearable.tail.test",
		"body.tail",
		["body.torso.outer"]
	)
	var unsupported_anchor_result: Dictionary = Domain.validate_equip(human, unsupported_anchor, [], "item.tail.001")
	_assert(String(unsupported_anchor_result.get("code", "")) == Domain.RESULT_UNSUPPORTED_ANCHOR, "Unsupported anchor was not rejected")

	var unsupported_channel: Domain.Profile = Domain.Profile.new(
		"equipment.test.hardpoint",
		"module.hardpoint.test",
		"body.root",
		["hardpoint.left"]
	)
	var unsupported_channel_result: Dictionary = Domain.validate_equip(human, unsupported_channel, [], "item.hardpoint.001")
	_assert(String(unsupported_channel_result.get("code", "")) == Domain.RESULT_UNSUPPORTED_CHANNEL, "Unsupported channel was not rejected")

	var biological_only: Domain.Profile = Domain.Profile.new(
		"equipment.test.biological",
		"wearable.biological.test",
		"body.head",
		["body.head.outer"],
		["biological"]
	)
	var biological_on_robot: Dictionary = Domain.validate_equip(robot, biological_only, [], "item.biological.001")
	_assert(String(biological_on_robot.get("code", "")) == Domain.RESULT_INCOMPATIBLE_CHARACTER_TAG, "Required character tag was not enforced")

	var no_mechanical: Domain.Profile = Domain.Profile.new(
		"equipment.test.no_mechanical",
		"wearable.no_mechanical.test",
		"body.head",
		["body.head.outer"],
		[],
		["mechanical"]
	)
	var no_mechanical_on_robot: Dictionary = Domain.validate_equip(robot, no_mechanical, [], "item.no_mechanical.001")
	_assert(String(no_mechanical_on_robot.get("code", "")) == Domain.RESULT_FORBIDDEN_CHARACTER_TAG, "Forbidden character tag was not enforced")

	var source = LabSource.new()
	var setup_result: Dictionary = source.setup("entity.character.lab.001", human, [helmet, backpack, eva_suit])
	_assert(bool(setup_result.get("success", false)), "Lab equipment source setup failed")
	_assert(source.registered_profile_ids().size() == 3, "Lab source did not register all profiles")
	_assert(source.get_snapshot().revision == 0, "Initial lab revision must be zero")

	var equip_helmet: Dictionary = source.equip("item.helmet.001", helmet.profile_id)
	_assert(bool(equip_helmet.get("success", false)), "Helmet equip failed")
	_assert(source.has_item("item.helmet.001"), "Helmet was not stored by lab source")
	_assert(source.get_snapshot().revision == 1, "Successful equip did not advance revision")

	var duplicate_item: Dictionary = source.equip("item.helmet.001", helmet.profile_id)
	_assert(String(duplicate_item.get("code", "")) == Domain.RESULT_ITEM_ALREADY_EQUIPPED, "Duplicate canonical item equip was not rejected")
	_assert(source.get_snapshot().revision == 1, "Rejected equip changed revision")

	var channel_conflict: Dictionary = source.equip("item.helmet.002", helmet.profile_id)
	_assert(String(channel_conflict.get("code", "")) == Domain.RESULT_EQUIPMENT_CHANNEL_OCCUPIED, "Occupied equipment channel was not rejected")
	_assert(source.get_snapshot().revision == 1, "Channel conflict changed revision")

	var equip_backpack: Dictionary = source.equip("item.backpack.001", backpack.profile_id)
	_assert(bool(equip_backpack.get("success", false)), "Backpack equip failed")
	_assert(source.get_snapshot().entries().size() == 2, "Expected helmet and backpack in snapshot")

	var equip_suit: Dictionary = source.equip("item.eva_suit.001", eva_suit.profile_id)
	_assert(bool(equip_suit.get("success", false)), "Multi-channel EVA suit equip failed")
	var suit_entry = source.get_snapshot().find_item("item.eva_suit.001")
	_assert(suit_entry != null, "EVA suit missing from snapshot")
	_assert(suit_entry.occupied_channels().size() == 3, "EVA suit lost multi-channel occupancy")

	var torso_outer: Domain.Profile = Domain.Profile.new(
		"equipment.test.jacket",
		"wearable.jacket.test",
		"body.root",
		["body.torso.outer"],
		[],
		[],
		["equipment.clothing"]
	)
	_assert(bool(source.register_profile(torso_outer).get("success", false)), "Jacket test profile registration failed")
	var suit_conflict: Dictionary = source.equip("item.jacket.001", torso_outer.profile_id)
	_assert(String(suit_conflict.get("code", "")) == Domain.RESULT_EQUIPMENT_CHANNEL_OCCUPIED, "Multi-channel suit did not reserve torso channel")

	var snapshot_a = source.get_snapshot()
	var reordered_entries: Array = snapshot_a.entries()
	reordered_entries.reverse()
	var snapshot_b: Domain.Snapshot = Domain.Snapshot.new(snapshot_a.owner_entity_id, snapshot_a.layout_id, snapshot_a.revision, reordered_entries)
	_assert(snapshot_a.state_fingerprint() == snapshot_b.state_fingerprint(), "Snapshot state fingerprint depends on entry order")
	_assert(snapshot_a.fingerprint() == snapshot_b.fingerprint(), "Snapshot fingerprint depends on entry order")

	var unequip_backpack: Dictionary = source.unequip("item.backpack.001")
	_assert(bool(unequip_backpack.get("success", false)), "Backpack unequip failed")
	_assert(not source.has_item("item.backpack.001"), "Backpack remained equipped after unequip")
	var missing_unequip: Dictionary = source.unequip("item.backpack.001")
	_assert(String(missing_unequip.get("code", "")) == Domain.RESULT_ITEM_NOT_EQUIPPED, "Missing item unequip did not return deterministic result")

	var robot_source = LabSource.new()
	var robot_setup: Dictionary = robot_source.setup("entity.robot.lab.001", robot, [helmet])
	_assert(bool(robot_setup.get("success", false)), "Robot lab source setup failed")
	var robot_helmet: Dictionary = robot_source.equip("item.helmet.robot.001", helmet.profile_id)
	_assert(bool(robot_helmet.get("success", false)), "Semantic helmet contract could not be reused by second character layout")
	_assert(robot_source.get_snapshot().layout_id == "robot.humanoid", "Robot snapshot lost its independent layout ID")

	var domain_source: String = FileAccess.get_file_as_string("res://scripts/characters/equipment/character_equipment_domain.gd")
	var lab_source: String = FileAccess.get_file_as_string("res://scripts/characters/equipment/lab_equipment_source.gd")
	for forbidden in ["Skeleton3D", "MeshInstance3D", "CharacterBody3D", "Input.", "multiplayer", "quaternius"]:
		_assert(not domain_source.to_lower().contains(String(forbidden).to_lower()), "Equipment domain gained forbidden presentation/runtime dependency: %s" % forbidden)
		_assert(not lab_source.to_lower().contains(String(forbidden).to_lower()), "Lab equipment source gained forbidden presentation/runtime dependency: %s" % forbidden)

	_finish()


func _human_layout() -> Domain.Layout:
	return Domain.Layout.new(
		"humanoid.standard",
		["character", "biological", "humanoid", "biped"],
		["equipment.headwear", "equipment.backpack", "equipment.clothing", "equipment.handheld"],
		[
			"body.head.inner", "body.head.outer",
			"body.torso.inner", "body.torso.outer", "body.torso.armor",
			"body.arms.inner", "body.arms.outer", "body.hands",
			"body.legs.inner", "body.legs.outer", "body.feet",
			"gear.back", "gear.waist", "hand.left", "hand.right",
		],
		["body.head", "body.root", "gear.back", "hand.left", "hand.right"],
		["body.region.head", "body.region.torso", "body.region.arms", "body.region.legs", "body.region.feet"]
	)


func _robot_layout() -> Domain.Layout:
	return Domain.Layout.new(
		"robot.humanoid",
		["character", "mechanical", "humanoid", "biped"],
		["equipment.headwear", "equipment.handheld", "equipment.hardpoint"],
		["body.head.outer", "hand.left", "hand.right", "module.torso", "hardpoint.left", "hardpoint.right"],
		["body.head", "body.root", "hand.left", "hand.right", "hardpoint.left", "hardpoint.right"]
	)


func _helmet_profile() -> Domain.Profile:
	return Domain.Profile.new(
		"equipment.helmet.mk1",
		"wearable.helmet.mk1",
		"body.head",
		["body.head.outer"],
		[],
		[],
		["equipment.headwear"]
	)


func _backpack_profile() -> Domain.Profile:
	return Domain.Profile.new(
		"equipment.backpack.mk1",
		"wearable.backpack.mk1",
		"gear.back",
		["gear.back"],
		[],
		[],
		["equipment.backpack"]
	)


func _eva_suit_profile() -> Domain.Profile:
	return Domain.Profile.new(
		"equipment.eva_suit.mk1",
		"wearable.eva_suit.mk1",
		"body.root",
		["body.torso.outer", "body.arms.outer", "body.legs.outer"],
		[],
		[],
		["equipment.clothing"]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7 character equipment domain: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7 character equipment domain: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
