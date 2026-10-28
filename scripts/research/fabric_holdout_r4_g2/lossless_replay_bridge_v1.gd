extends "res://scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd"

# Opt-in wire adapter over the existing bridge, not a new state/authority owner.
const Transport = preload("res://scripts/research/fabric_holdout_r4_g2/lossless_json_v1.gd")

func export_replay_transport() -> Dictionary:
	return Transport.encode(export_replay())

func replay_transport(wire: Dictionary, current_store: Dictionary, current_matter: Dictionary, current_authority: Dictionary, expected_replay_checksum: String) -> Dictionary:
	var decoded := Transport.decode(wire)
	if not decoded.success or not decoded.value is Dictionary:
		return U.failure("R3_REPLAY_TRANSPORT_INVALID", {"cause": decoded.error})
	return replay(decoded.value, current_store, current_matter, current_authority, expected_replay_checksum)
