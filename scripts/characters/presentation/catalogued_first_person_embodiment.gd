class_name CataloguedFirstPersonEmbodiment
extends "res://scripts/characters/presentation/first_person_embodiment.gd"

const VisualFactoryType = preload("res://scripts/characters/presentation/held_item_visual_factory.gd")

var _catalog_visual_factory = VisualFactoryType.new()
var _catalog_profile_by_hand: Dictionary = {}
var _catalog_grip_by_hand: Dictionary = {}


func set_catalogued_hand_item(
	hand_id: String,
	item_id: String,
	display_name: String,
	item_color: Color,
	visual_descriptor: Dictionary,
	grip_transform: Dictionary
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_INVALID_HAND", {"hand_id": hand_id})
	var normalized_item_id := item_id.strip_edges()
	if normalized_item_id.is_empty():
		_catalog_profile_by_hand.erase(hand)
		_catalog_grip_by_hand.erase(hand)
		return clear_authoritative_hand_item(hand)

	var visual_profile := String(visual_descriptor.get("profile_id", "generic_box"))
	var grip_signature := JSON.stringify(grip_transform)
	if (
		String(_authoritative_item_id_by_hand.get(hand, "")) == normalized_item_id
		and String(_catalog_profile_by_hand.get(hand, "")) == visual_profile
		and String(_catalog_grip_by_hand.get(hand, "")) == grip_signature
	):
		return _success({
			"changed": false,
			"hand_id": hand,
			"item_id": normalized_item_id,
			"visual_profile": visual_profile,
			"catalogued": true,
		})

	_clear_authoritative_proxy(hand)
	_authoritative_item_id_by_hand[hand] = normalized_item_id
	var held_root := _held_root(hand)
	if held_root == null:
		return _failure("FPE_HAND_ROOT_UNAVAILABLE", {"hand_id": hand})

	var built: Dictionary = _catalog_visual_factory.create_proxy(
		visual_descriptor,
		item_color,
		"CataloguedItemProxy_%s" % hand.capitalize()
	)
	if not bool(built.get("success", false)):
		return built
	var proxy_value: Variant = Dictionary(built.get("details", {})).get("proxy")
	if not proxy_value is MeshInstance3D:
		return _failure("FPE_CATALOG_PROXY_INVALID")
	var proxy := proxy_value as MeshInstance3D
	_catalog_visual_factory.apply_local_transform(proxy, grip_transform)
	proxy.set_meta("canonical_item_id", normalized_item_id)
	proxy.set_meta("display_name", display_name)
	proxy.set_meta("held_grip_profile", String(grip_transform.get("profile_id", "")))
	held_root.add_child(proxy)
	_authoritative_proxy_by_hand[hand] = proxy
	_catalog_profile_by_hand[hand] = visual_profile
	_catalog_grip_by_hand[hand] = grip_signature
	_update_hand_proxy_visibility(hand)
	_refresh_adapter_visuals()
	return _success({
		"changed": true,
		"hand_id": hand,
		"item_id": normalized_item_id,
		"display_name": display_name,
		"visual_profile": visual_profile,
		"visual_kind": String(visual_descriptor.get("visual_kind", "BOX")),
		"catalogued": true,
		"presentation_only": true,
	})


func clear_authoritative_hand_item(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if not hand.is_empty():
		_catalog_profile_by_hand.erase(hand)
		_catalog_grip_by_hand.erase(hand)
	return super.clear_authoritative_hand_item(hand_id)


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["catalogued_viewmodel"] = {
		"enabled": true,
		"profiles_by_hand": _catalog_profile_by_hand.duplicate(true),
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
	}
	return report
