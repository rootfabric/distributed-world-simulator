extends SceneTree
const S = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd")
func _init() -> void:
	var observation := {"body_a": "floor", "body_b": "box", "members": ["m3", "m1", "m2", "m0"]}
	var solved := {"normal_support": 9.81, "generalized_impulse": [0.0,0.0,0.0,0.0,0.0], "generalized_velocity_after": [0.0,0.0,0.0,0.0,0.0], "limits": {"tangent": 4.0, "rolling": 0.5, "torsion": 0.25}}
	var state := S.begin(observation, solved, 0.0)
	state = S.advance(state, observation, solved, 0.016)
	print("FABRIC0.18-A state=", state)
	print("FABRIC0_18_A_PERSISTENT_WRENCH_CONTACT_STATE_PLAYGROUND_PASS")
	quit(0)
