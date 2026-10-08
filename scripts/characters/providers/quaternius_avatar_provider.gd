class_name QuaterniusAvatarProvider
extends "res://scripts/characters/avatar/avatar_provider.gd"

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")
const Adapter = preload(
	"res://scripts/characters/providers/quaternius_avatar_adapter.gd"
)

func get_provider_id() -> String:
	return "avatar/quaternius"

func create_presenter(
	definition: Dictionary,
	appearance: Dictionary,
	local_player: bool
) -> Dictionary:
	var presenter := Adapter.new()
	var configured: Dictionary = presenter.configure(
		definition,
		appearance,
		local_player
	)
	if not bool(configured.get("success", false)):
		presenter.free()
		return configured
	return Contract.success({"presenter": presenter})
