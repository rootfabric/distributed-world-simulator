class_name ProceduralHumanoidAvatarProvider
extends "res://scripts/characters/avatar/avatar_provider.gd"

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")
const Presenter = preload(
	"res://scripts/characters/providers/procedural_humanoid_avatar_presenter.gd"
)

func get_provider_id() -> String:
	return "avatar/procedural_humanoid"

func create_presenter(
	definition: Dictionary,
	appearance: Dictionary,
	local_player: bool
) -> Dictionary:
	var presenter := Presenter.new()
	var configured: Dictionary = presenter.configure(
		definition,
		appearance,
		local_player
	)
	if not bool(configured.get("success", false)):
		presenter.free()
		return configured
	return Contract.success({"presenter": presenter})
