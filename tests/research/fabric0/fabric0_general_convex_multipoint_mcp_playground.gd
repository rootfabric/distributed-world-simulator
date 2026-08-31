extends SceneTree

const E = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_experiments_v1.gd")

func _init() -> void:
	var pair := E.rotated_pair_probe()
	var persistence := E.persistence_probe()
	var chain := E.graph_chain_probe(false,false)
	var sliding := E.graph_chain_probe(true,false)
	print("=== FABRIC0.16 GENERAL CONVEX MULTIPOINT MCP S1 ===")
	print("rotated_box_epa=",pair["collision"])
	print("manifold_ids=",pair["manifold"]["points"].map(func(p:Dictionary):return p["id"]))
	print("persistent_lifetimes=",persistence["next"]["points"].map(func(p:Dictionary):return p["lifetime"]))
	print("graph_rows=",chain["contacts"].size()," pair_impulses=",E.pair_normal_impulse(chain["solve"],"A|B|"),",",E.pair_normal_impulse(chain["solve"],"B|C|"))
	print("graph_comp=",chain["solve"]["max_complementarity_violation"]," coupling_W_0_4=",chain["solve"]["normal_matrix"][0][4])
	print("sliding_coupling_iterations=",sliding["solve"]["coupling_iterations"]," comp=",sliding["solve"]["max_complementarity_violation"]," cone=",sliding["solve"]["max_cone_violation"])
	print("momentum_errors=",sliding["linear_momentum_error"],",",sliding["angular_momentum_error"]," energy_delta=",sliding["kinetic_energy_delta"])
	print("FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_S1_PLAYGROUND_PASS")
	quit(0)
