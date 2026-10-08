class_name AvatarProvider
extends RefCounted

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

func get_provider_id() -> String:
	return "avatar/provider/base"

func supports(definition: Dictionary) -> bool:
	return Contract.normalized_id(definition.get("provider_id", "")) == get_provider_id()

func create_presenter(_definition: Dictionary, _appearance: Dictionary, _local_player: bool) -> Dictionary:
	return Contract.failure("AVATAR_PROVIDER_CREATE_NOT_IMPLEMENTED", {
		"provider_id": get_provider_id(),
	})
