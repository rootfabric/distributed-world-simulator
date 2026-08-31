extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_runtime_v1.gd")

func _init() -> void:
	var points: Array = []
	for iy in range(31):
		for ix in range(31):
			points.append({
				"id": "p/%03d/%03d" % [iy, ix],
				"position": Vector3(lerpf(-1.5, 1.5, float(ix) / 30.0), lerpf(-0.8, 0.8, float(iy) / 30.0), 0.0),
			})
	var request := {
		"model_id": "artifact/b0-3-playground",
		"patch_id": "patch/playground",
		"source_frontier_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"physical_graph_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		"parent_artifact_checksum": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"authority_checksum": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
		"origin": Vector3.ZERO,
		"normal": Vector3(0, 0, 1),
		"t1": Vector3(1, 0, 0),
		"t2": Vector3(0, 1, 0),
		"points": points,
		"normal_support_limit": 20.0,
		"mu_tangent": 0.7,
		"mu_rolling": 0.05,
		"mu_torsion": 0.04,
		"effective_radius": 0.5,
	}
	var compiled := Compiler.compile(request)
	assert(bool(compiled.get("ok", false)))
	var artifact: Dictionary = compiled["model"]
	var slide := Runtime.maximum_dissipation_wrench(artifact, [1.0, 0.4, 0.0, 0.1, -0.2, 0.3])
	assert(bool(slide.get("ok", false)))
	var tip := Runtime.support(artifact, [0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	assert(bool(tip.get("ok", false)))
	print("FABRIC-BAKE B0.3 Playground: PASS artifact=%s members=%d generators=%d ratio=%.2f tip_My=%.9f dissipation=%.9f selected=%s" % [
		String(artifact["model_hash"]), int(artifact["full_member_count"]), int(artifact["generator_count"]), float(artifact["reduction_ratio"]), float(tip["support"]), float(slide["dissipation"]), String(slide["selected_generator"])
	])
	quit(0)
