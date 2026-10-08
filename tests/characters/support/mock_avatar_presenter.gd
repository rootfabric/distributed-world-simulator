extends "res://scripts/characters/avatar/avatar_presenter.gd"

var _right_hand: Node3D

func configure(definition_value: Dictionary, appearance_value: Dictionary, is_local_player: bool) -> Dictionary:
	var configured: Dictionary = super.configure(definition_value, appearance_value, is_local_player)
	if not bool(configured.get("success", false)):
		return configured
	var visual := MeshInstance3D.new()
	visual.name = "ExternalProviderVisual"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 1.7, 0.3)
	visual.mesh = box
	add_child(visual)
	_right_hand = Node3D.new()
	_right_hand.name = "ExternalRightHand"
	add_child(_right_hand)
	return Contract.success()

func get_socket(socket_id: StringName) -> Node3D:
	return _right_hand if String(socket_id) == "hand_right" else null

func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["external_provider"] = true
	return report
