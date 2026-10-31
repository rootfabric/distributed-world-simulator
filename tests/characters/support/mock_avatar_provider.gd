extends "res://scripts/characters/avatar/avatar_provider.gd"

const Presenter = preload("res://tests/characters/support/mock_avatar_presenter.gd")

func get_provider_id() -> String:
	return "avatar/external_test"

func create_presenter(definition: Dictionary, appearance: Dictionary, local_player: bool) -> Dictionary:
	var presenter := Presenter.new()
	var configured: Dictionary = presenter.configure(definition, appearance, local_player)
	if not bool(configured.get("success", false)):
		presenter.free()
		return configured
	return Contract.success({"presenter": presenter})
