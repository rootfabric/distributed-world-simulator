class_name NetworkCharacterEquipmentCatalog
extends RefCounted

const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")

const EQUIPMENT_CONTAINER_KIND := "CHARACTER_EQUIPMENT"
const EQUIPMENT_SLOT_COUNT := 5

const SLOT_HEAD := 0
const SLOT_BACK := 1
const SLOT_UPPER := 2
const SLOT_LOWER := 3
const SLOT_FEET := 4

const PROFILE_HELMET := "equipment.helmet.mk1"
const PROFILE_BACKPACK := "equipment.backpack.mk1"
const PROFILE_UPPER := "equipment.layer.upper.peasant"
const PROFILE_LOWER := "equipment.layer.lower.peasant"
const PROFILE_FEET := "equipment.layer.feet.peasant"

const PRESENTATION_HELMET := "wearable.helmet.mk1"
const PRESENTATION_BACKPACK := "wearable.backpack.mk1"
const PRESENTATION_UPPER := "wearable.layer.upper.peasant"
const PRESENTATION_LOWER := "wearable.layer.lower.peasant"
const PRESENTATION_FEET := "wearable.layer.feet.peasant"

const DEFINITION_HELMET := "item/wearable/helmet"
const DEFINITION_BACKPACK := "item/wearable/backpack"
const DEFINITION_UPPER := "item/wearable/upper"
const DEFINITION_LOWER := "item/wearable/lower"
const DEFINITION_FEET := "item/wearable/feet"

const REPLICA_DEFINITION_HELMET := "ch9_wearable_helmet"
const REPLICA_DEFINITION_BACKPACK := "ch9_wearable_backpack"
const REPLICA_DEFINITION_UPPER := "ch9_wearable_upper"
const REPLICA_DEFINITION_LOWER := "ch9_wearable_lower"
const REPLICA_DEFINITION_FEET := "ch9_wearable_feet"


static func equipment_container_id(logical_player_id: String) -> String:
	return "equipment/%s" % logical_player_id.strip_edges().to_lower()


static func owner_entity_id(logical_player_id: String) -> String:
	return "player/%s" % logical_player_id.strip_edges().to_lower()


static func slot_profile_ids() -> Dictionary:
	return {
		SLOT_HEAD: PROFILE_HELMET,
		SLOT_BACK: PROFILE_BACKPACK,
		SLOT_UPPER: PROFILE_UPPER,
		SLOT_LOWER: PROFILE_LOWER,
		SLOT_FEET: PROFILE_FEET,
	}


static func canonical_definition_for_slot(slot_index: int) -> String:
	match slot_index:
		SLOT_HEAD: return DEFINITION_HELMET
		SLOT_BACK: return DEFINITION_BACKPACK
		SLOT_UPPER: return DEFINITION_UPPER
		SLOT_LOWER: return DEFINITION_LOWER
		SLOT_FEET: return DEFINITION_FEET
	return ""


static func replica_definition_id(canonical_definition_id: String) -> String:
	match canonical_definition_id:
		DEFINITION_HELMET: return REPLICA_DEFINITION_HELMET
		DEFINITION_BACKPACK: return REPLICA_DEFINITION_BACKPACK
		DEFINITION_UPPER: return REPLICA_DEFINITION_UPPER
		DEFINITION_LOWER: return REPLICA_DEFINITION_LOWER
		DEFINITION_FEET: return REPLICA_DEFINITION_FEET
	return ""


static func slot_for_canonical_definition(canonical_definition_id: String) -> int:
	for slot_index in range(EQUIPMENT_SLOT_COUNT):
		if canonical_definition_for_slot(slot_index) == canonical_definition_id:
			return slot_index
	return -1


static func slot_tag(slot_index: int) -> String:
	match slot_index:
		SLOT_HEAD: return "equipment.slot.head"
		SLOT_BACK: return "equipment.slot.back"
		SLOT_UPPER: return "equipment.slot.upper"
		SLOT_LOWER: return "equipment.slot.lower"
		SLOT_FEET: return "equipment.slot.feet"
	return ""


static func layout() -> CharacterEquipmentDomain.Layout:
	return EquipmentDomain.Layout.new(
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


static func profiles() -> Array:
	return [
		EquipmentDomain.Profile.new(PROFILE_HELMET, PRESENTATION_HELMET, "body.head", ["body.head.outer"], [], [], ["equipment.headwear"]),
		EquipmentDomain.Profile.new(PROFILE_BACKPACK, PRESENTATION_BACKPACK, "gear.back", ["gear.back"], [], [], ["equipment.backpack"]),
		EquipmentDomain.Profile.new(PROFILE_UPPER, PRESENTATION_UPPER, "body.root", ["body.torso.outer", "body.arms.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_LOWER, PRESENTATION_LOWER, "body.root", ["body.legs.outer"], [], [], ["equipment.clothing"]),
		EquipmentDomain.Profile.new(PROFILE_FEET, PRESENTATION_FEET, "body.root", ["body.feet"], [], [], ["equipment.clothing"]),
	]


static func profile_for_slot(slot_index: int) -> CharacterEquipmentDomain.Profile:
	var profile_id := String(slot_profile_ids().get(slot_index, ""))
	for profile_value in profiles():
		if profile_value is CharacterEquipmentDomain.Profile and profile_value.profile_id == profile_id:
			return profile_value
	return null


static func wearable_specs() -> Array[Dictionary]:
	return [
		{"slot_index": SLOT_HEAD, "suffix": "helmet", "definition_id": DEFINITION_HELMET},
		{"slot_index": SLOT_BACK, "suffix": "backpack", "definition_id": DEFINITION_BACKPACK},
		{"slot_index": SLOT_UPPER, "suffix": "upper", "definition_id": DEFINITION_UPPER},
		{"slot_index": SLOT_LOWER, "suffix": "lower", "definition_id": DEFINITION_LOWER},
		{"slot_index": SLOT_FEET, "suffix": "feet", "definition_id": DEFINITION_FEET},
	]
