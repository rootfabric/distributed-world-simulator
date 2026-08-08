class_name QuaterniusEquipmentLab
extends "res://scripts/characters/lab/quaternius_character_lab.gd"

const EquipmentAwareFirstPersonAdapter = preload("res://scripts/characters/presentation/equipment_aware_first_person_adapter.gd")
const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const EquipmentSource = preload("res://scripts/characters/equipment/lab_equipment_source.gd")
const EquipmentPresenter = preload("res://scripts/characters/equipment/character_equipment_presenter.gd")
const QuaterniusRigAdapter = preload("res://scripts/characters/equipment/quaternius_equipment_rig_adapter.gd")
const WearableCatalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const WearableFactory = preload("res://scripts/characters/equipment/lab_wearable_factory.gd")

const HELMET_ITEM_ID := "lab.item.helmet.001"
const BACKPACK_ITEM_ID := "lab.item.backpack.001"
const HELMET_PROFILE_ID := "equipment.helmet.mk1"
const BACKPACK_PROFILE_ID := "equipment.backpack.mk1"

var equipment_layout: CharacterEquipmentDomain.Layout
auto var equipment_source
var equipment_presenter
var equipment_rig_adapter
var wearable_catalog
var equipment_last_result: Dictionary = {}


func _ready() -> void:
	super._ready()
	_upgrade_first_person_adapter()
	_setup_equipment()
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			toggle_helmet()
		elif event.keycode == KEY_B:
			toggle_backpack()


func toggle_helmet() -> Dictionary:
	return _toggle_item(HELMET_ITEM_ID, HELMET_PROFILE_ID)


func toggle_backpack() -> Dictionary:
	return _toggle_item(BACKPACK_ITEM_ID, BACKPACK_PROFILE_ID)


func set_helmet_equipped(enabled: bool) -> Dictionary:
	return _set_item_equipped(HELMET_ITEM_ID, HELMET_PROFILE_ID, enabled)


func set_backpack_equipped(enabled: bool) -> Dictionary:
	return _set_item_equipped(BACKPACK_ITEM_ID, BACKPACK_PROFILE_ID, enabled)


func _upgrade_first_person_adapter() -> void:
	var previous_adapter = first_person_adapter
	if previous_adapter != null:
		if previous_adapter.has_method("unbind_cameras"):
			previous_adapter.call("unbind_cameras")
		if previous_adapter.has_method("unbind_avatar"):
			previous_adapter.call("unbind_avatar")
		previous_adapter.queue_free()

	first_person_adapter = EquipmentAwareFirstPersonAdapter.new()
	first_person_adapter.name = "CH7EquipmentAwareFirstPersonAdapter"
	player.add_child(first_person_adapter)
	first_person_adapter.bind_avatar(avatar, presentation_profile)
	first_person_adapter.bind_cameras(first_person_camera, third_person_camera)
	first_person_adapter.set_first_person_enabled(first_person_mode)


func _setup_equipment() -> void:
	equipment_layout = EquipmentDomain.Layout.new(
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
	var helmet_profile := EquipmentDomain.Profile.new(
		HELMET_PROFILE_ID,
		"wearable.helmet.mk1",
		"body.head",
		["body.head.outer"],
		[],
		[],
		["equipment.headwear"]
	)
	var backpack_profile := EquipmentDomain.Profile.new(
		BACKPACK_PROFILE_ID,
		"wearable.backpack.mk1",
		"gear.back",
		["gear.back"],
		[],
		[],
		["equipment.backpack"]
	)

	equipment_source = EquipmentSource.new()
	equipment_last_result = equipment_source.setup(
		"lab.entity.quaternius.001",
		equipment_layout,
		[helmet_profile, backpack_profile]
	)
	if not bool(equipment_last_result.get("success", false)):
		push_error("CH7 equipment source setup failed: %s" % JSON.stringify(equipment_last_result))
		return

	equipment_rig_adapter = QuaterniusRigAdapter.new()
	equipment_last_result = equipment_rig_adapter.bind_presenter(avatar)
	if not bool(equipment_last_result.get("success", false)):
		push_error("CH7 Quaternius equipment rig bind failed: %s" % JSON.stringify(equipment_last_result))
		return

	wearable_catalog = WearableCatalog.new()
	var helmet_scene: PackedScene = WearableFactory.create_helmet_scene()
	var backpack_scene: PackedScene = WearableFactory.create_backpack_scene()
	if helmet_scene == null or backpack_scene == null:
		equipment_last_result = {"success": false, "code": "LAB_WEARABLE_PACK_FAILED", "details": {}}
		push_error("CH7 lab wearable scene packing failed")
		return

	wearable_catalog.register_scene(
		"wearable.helmet.mk1",
		equipment_rig_adapter.rig_profile_id,
		WearableCatalog.STRATEGY_RIGID_ATTACHMENT,
		helmet_scene,
		[],
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))
	)
	wearable_catalog.register_scene(
		"wearable.backpack.mk1",
		equipment_rig_adapter.rig_profile_id,
		WearableCatalog.STRATEGY_RIGID_ATTACHMENT,
		backpack_scene,
		[],
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, 0.22))
	)

	equipment_presenter = EquipmentPresenter.new()
	equipment_presenter.name = "CharacterEquipmentPresentation"
	avatar.add_child(equipment_presenter)
	equipment_last_result = equipment_presenter.setup(avatar, equipment_rig_adapter, wearable_catalog)
	if not bool(equipment_last_result.get("success", false)):
		push_error("CH7 equipment presenter setup failed: %s" % JSON.stringify(equipment_last_result))
		return
	equipment_last_result = equipment_presenter.apply_snapshot(equipment_source.get_snapshot())
	_refresh_equipment_view_policy()


func _toggle_item(item_id: String, profile_id: String) -> Dictionary:
	if equipment_source == null:
		return {"success": false, "code": "EQUIPMENT_SOURCE_NOT_READY", "details": {}}
	return _set_item_equipped(item_id, profile_id, not equipment_source.has_item(item_id))


func _set_item_equipped(item_id: String, profile_id: String, enabled: bool) -> Dictionary:
	if equipment_source == null or equipment_presenter == null:
		equipment_last_result = {"success": false, "code": "EQUIPMENT_NOT_READY", "details": {}}
		return equipment_last_result

	var mutation: Dictionary
	if enabled:
		if equipment_source.has_item(item_id):
			mutation = {"success": true, "code": EquipmentDomain.RESULT_OK, "details": {"changed": false}}
		else:
			mutation = equipment_source.equip(item_id, profile_id)
	else:
		if not equipment_source.has_item(item_id):
			mutation = {"success": true, "code": EquipmentDomain.RESULT_OK, "details": {"changed": false}}
		else:
			mutation = equipment_source.unequip(item_id)

	if not bool(mutation.get("success", false)):
		equipment_last_result = mutation
		_refresh_status()
		return mutation

	var presentation_result: Dictionary = equipment_presenter.apply_snapshot(equipment_source.get_snapshot())
	if not bool(presentation_result.get("success", false)):
		equipment_last_result = presentation_result
		_refresh_status()
		return presentation_result

	equipment_last_result = {
		"success": true,
		"code": EquipmentDomain.RESULT_OK,
		"details": {
			"mutation": mutation.get("details", {}),
			"presentation": presentation_result.get("details", {}),
			"revision": equipment_source.get_snapshot().revision,
		}
	}
	_refresh_equipment_view_policy()
	_refresh_status()
	return equipment_last_result


func _refresh_equipment_view_policy() -> void:
	if first_person_adapter != null and first_person_adapter.has_method("refresh_presentation_visuals"):
		var refresh_result: Dictionary = first_person_adapter.call("refresh_presentation_visuals")
		if not bool(refresh_result.get("success", false)):
			push_error("CH7 equipment view refresh failed: %s" % JSON.stringify(refresh_result))


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var helmet_state := "OFF"
	var backpack_state := "OFF"
	var revision := 0
	var rig_mode := "UNBOUND"
	if equipment_source != null:
		helmet_state = "ON" if equipment_source.has_item(HELMET_ITEM_ID) else "OFF"
		backpack_state = "ON" if equipment_source.has_item(BACKPACK_ITEM_ID) else "OFF"
		revision = equipment_source.get_snapshot().revision
	if equipment_rig_adapter != null:
		rig_mode = String(equipment_rig_adapter.create_report().get("mode", "UNBOUND"))
	status_label.text += (
		"\n\nCH7 — Universal Equipment\n"
		+ "H — helmet | B — backpack\n"
		+ "helmet: %s | backpack: %s | revision: %d | rig: %s"
		% [helmet_state, backpack_state, revision, rig_mode]
	)
