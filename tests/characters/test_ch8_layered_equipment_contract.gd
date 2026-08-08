extends SceneTree

const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const Layering = preload("res://scripts/characters/equipment/character_equipment_layering.gd")
const LabSource = preload("res://scripts/characters/equipment/lab_equipment_source.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var layout := _layout()
	var undersuit := _profile("equipment.layer.undersuit", "wearable.layer.undersuit", [
		"body.torso.inner", "body.arms.inner", "body.legs.inner",
	])
	var jacket := _profile("equipment.layer.jacket", "wearable.layer.jacket", [
		"body.torso.outer", "body.arms.outer",
	])
	var trousers := _profile("equipment.layer.trousers", "wearable.layer.trousers", ["body.legs.outer"])
	var boots := _profile("equipment.layer.boots", "wearable.layer.boots", ["body.feet"])
	var armor := _profile("equipment.layer.armor", "wearable.layer.armor", ["body.torso.armor"])
	var eva := _profile("equipment.layer.eva", "wearable.layer.eva", [
		"body.torso.outer", "body.torso.armor", "body.arms.outer", "body.legs.outer", "body.feet",
	])

	var source = LabSource.new()
	var setup: Dictionary = source.setup("entity.character.layered.001", layout, [
		undersuit, jacket, trousers, boots, armor, eva,
	])
	_assert(bool(setup.get("success", false)), "Layered source setup failed")
	_assert(source.get_snapshot().revision == 0, "Layered source initial revision changed")

	_assert(bool(source.equip("item.undersuit.001", undersuit.profile_id).get("success", false)), "Undersuit equip failed")
	_assert(bool(source.equip("item.jacket.001", jacket.profile_id).get("success", false)), "Jacket equip failed")
	_assert(bool(source.equip("item.trousers.001", trousers.profile_id).get("success", false)), "Trousers equip failed")
	_assert(bool(source.equip("item.boots.001", boots.profile_id).get("success", false)), "Boots equip failed")
	_assert(bool(source.equip("item.armor.001", armor.profile_id).get("success", false)), "Armor equip failed")
	var layered_snapshot := source.get_snapshot()
	_assert(layered_snapshot.revision == 5, "Independent layers did not advance exactly five revisions")
	_assert(layered_snapshot.entries().size() == 5, "Independent layers did not coexist")
	_assert(layered_snapshot.find_item("item.undersuit.001") != null, "Inner layer disappeared")
	_assert(layered_snapshot.find_item("item.armor.001") != null, "Armor layer disappeared")

	var revision_before_plan := source.get_snapshot().revision
	var plan: Dictionary = source.plan_equip("item.eva.001", eva.profile_id)
	_assert(bool(plan.get("success", false)), "EVA conflict plan failed structurally")
	_assert(String(plan.get("code", "")) == Layering.RESULT_CONFLICT_PLAN, "EVA conflict plan returned unexpected code")
	_assert(source.get_snapshot().revision == revision_before_plan, "Planning mutated canonical revision")
	var plan_details: Dictionary = plan.get("details", {})
	_assert(bool(plan_details.get("requires_replacement", false)), "EVA plan did not require replacement")
	_assert(not bool(plan_details.get("can_equip_without_replacement", true)), "EVA plan incorrectly allowed direct equip")
	var expected_replaced := [
		"item.armor.001",
		"item.boots.001",
		"item.jacket.001",
		"item.trousers.001",
	]
	_assert((plan_details.get("conflicting_item_ids", []) as Array) == expected_replaced, "Conflict item set/order is not deterministic")
	var conflicts: Array = plan_details.get("conflicts", [])
	_assert(conflicts.size() == 5, "Expected five conflicting occupied channels")
	var conflict_channels: Array[String] = []
	for raw_conflict in conflicts:
		var conflict: Dictionary = raw_conflict
		conflict_channels.append(String(conflict.get("channel", "")))
	_assert(conflict_channels == [
		"body.arms.outer",
		"body.feet",
		"body.legs.outer",
		"body.torso.armor",
		"body.torso.outer",
	], "Conflict channels are incomplete or non-deterministic")
	_assert(not expected_replaced.has("item.undersuit.001"), "Test fixture unexpectedly marks inner layer for replacement")

	var reversed_entries: Array = layered_snapshot.entries()
	reversed_entries.reverse()
	var reversed_plan: Dictionary = Layering.plan_equip(layout, eva, reversed_entries, "item.eva.001")
	_assert(JSON.stringify(reversed_plan.get("details", {})) == JSON.stringify(plan_details), "Conflict plan depends on current-entry order")

	var legacy_reject: Dictionary = source.equip("item.eva.001", eva.profile_id)
	_assert(String(legacy_reject.get("code", "")) == Domain.RESULT_EQUIPMENT_CHANNEL_OCCUPIED, "Legacy equip stopped rejecting conflicts")
	_assert(source.get_snapshot().revision == 5, "Rejected legacy equip changed revision")
	_assert(source.get_snapshot().entries().size() == 5, "Rejected legacy equip mutated layered state")

	var replacement: Dictionary = source.equip_replacing_conflicts("item.eva.001", eva.profile_id)
	_assert(bool(replacement.get("success", false)), "Atomic EVA replacement failed")
	var replacement_details: Dictionary = replacement.get("details", {})
	_assert(bool(replacement_details.get("replacement", false)), "Atomic EVA mutation did not report replacement")
	_assert((replacement_details.get("replaced_item_ids", []) as Array) == expected_replaced, "Atomic EVA replacement removed wrong items")
	_assert(int(replacement_details.get("revision", -1)) == 6, "Atomic replacement did not advance exactly one revision")
	var eva_snapshot := source.get_snapshot()
	_assert(eva_snapshot.revision == 6, "Atomic replacement snapshot revision mismatch")
	_assert(eva_snapshot.entries().size() == 2, "Atomic replacement should leave undersuit + EVA")
	_assert(eva_snapshot.find_item("item.undersuit.001") != null, "Atomic replacement incorrectly removed compatible inner layer")
	_assert(eva_snapshot.find_item("item.eva.001") != null, "Atomic replacement did not equip EVA")
	for replaced_item in expected_replaced:
		_assert(eva_snapshot.find_item(replaced_item) == null, "Conflicting item survived atomic replacement: %s" % replaced_item)
	var eva_entry = eva_snapshot.find_item("item.eva.001")
	_assert(eva_entry != null and eva_entry.occupied_channels().size() == 5, "EVA lost multi-channel occupancy")

	var jacket_again: Dictionary = source.equip("item.jacket.002", jacket.profile_id)
	_assert(String(jacket_again.get("code", "")) == Domain.RESULT_EQUIPMENT_CHANNEL_OCCUPIED, "EVA did not reserve outer jacket channels")
	_assert(source.get_snapshot().revision == 6, "Post-EVA conflict changed revision")

	var duplicate_replace: Dictionary = source.equip_replacing_conflicts("item.eva.001", eva.profile_id)
	_assert(String(duplicate_replace.get("code", "")) == Domain.RESULT_ITEM_ALREADY_EQUIPPED, "Replace path did not preserve duplicate-item rejection")
	_assert(source.get_snapshot().revision == 6, "Duplicate replace path changed revision")

	_assert(bool(source.unequip("item.eva.001").get("success", false)), "EVA unequip failed")
	_assert(source.get_snapshot().revision == 7, "EVA unequip revision mismatch")
	_assert(source.get_snapshot().entries().size() == 1, "EVA unequip should leave only undersuit")
	_assert(source.has_item("item.undersuit.001"), "Compatible inner layer did not survive EVA lifecycle")

	var layering_source := FileAccess.get_file_as_string("res://scripts/characters/equipment/character_equipment_layering.gd")
	var lab_source := FileAccess.get_file_as_string("res://scripts/characters/equipment/lab_equipment_source.gd")
	for forbidden in ["Skeleton3D", "MeshInstance3D", "CharacterBody3D", "Input.", "multiplayer", "quaternius"]:
		_assert(not layering_source.to_lower().contains(String(forbidden).to_lower()), "Layering planner gained forbidden presentation/runtime dependency: %s" % forbidden)
		_assert(not lab_source.to_lower().contains(String(forbidden).to_lower()), "Lab source gained forbidden presentation/runtime dependency: %s" % forbidden)

	_finish()


func _layout() -> Domain.Layout:
	return Domain.Layout.new(
		"humanoid.layered",
		["character", "biological", "humanoid", "biped"],
		["equipment.clothing", "equipment.headwear", "equipment.backpack"],
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


func _profile(profile_id: String, presentation_id: String, channels: Array) -> Domain.Profile:
	return Domain.Profile.new(
		profile_id,
		presentation_id,
		"body.root",
		channels,
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
		print("CH8 layered equipment contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8 layered equipment contract: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
