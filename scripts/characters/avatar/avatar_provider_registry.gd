class_name AvatarProviderRegistry
extends RefCounted

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")
const PresenterBase = preload("res://scripts/characters/avatar/avatar_presenter.gd")

var _providers: Dictionary = {}
var _sealed := false

func register_provider(provider) -> Dictionary:
	if _sealed:
		return Contract.failure("AVATAR_PROVIDER_REGISTRY_SEALED")
	if provider == null or not provider.has_method("get_provider_id") or not provider.has_method("supports") or not provider.has_method("create_presenter"):
		return Contract.failure("AVATAR_PROVIDER_INTERFACE_INVALID")
	var provider_id := Contract.normalized_id(provider.get_provider_id())
	if not Contract.valid_id(provider_id):
		return Contract.failure("AVATAR_PROVIDER_ID_INVALID")
	if _providers.has(provider_id):
		return Contract.failure("AVATAR_PROVIDER_DUPLICATE", {"provider_id": provider_id})
	_providers[provider_id] = provider
	return Contract.success({"provider_id": provider_id})

func seal() -> Dictionary:
	if _providers.is_empty():
		return Contract.failure("AVATAR_PROVIDER_REGISTRY_EMPTY")
	_sealed = true
	return Contract.success({"provider_count": _providers.size()})

func create_presenter(definition: Dictionary, appearance: Dictionary, local_player: bool) -> Dictionary:
	var provider_id := Contract.normalized_id(definition.get("provider_id", ""))
	var provider = _providers.get(provider_id)
	if provider == null:
		return Contract.failure("AVATAR_PROVIDER_UNKNOWN", {"provider_id": provider_id})
	if not bool(provider.supports(definition)):
		return Contract.failure("AVATAR_PROVIDER_REJECTED_DEFINITION", {"provider_id": provider_id})
	var result: Dictionary = provider.create_presenter(definition, appearance, local_player)
	if not bool(result.get("success", false)):
		return result
	var presenter = result.get("details", {}).get("presenter")
	if presenter == null or not presenter is PresenterBase:
		if presenter != null and presenter is Node:
			presenter.free()
		return Contract.failure("AVATAR_PROVIDER_RETURNED_INVALID_PRESENTER", {"provider_id": provider_id})
	return result

func get_provider_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _providers.keys():
		ids.append(String(key))
	ids.sort()
	return ids

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.avatar_provider_registry.v1",
		"sealed": _sealed,
		"provider_ids": get_provider_ids(),
		"provider_count": _providers.size(),
	}
