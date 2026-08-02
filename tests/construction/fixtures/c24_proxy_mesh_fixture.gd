extends RefCounted

const Greedy = preload("res://scripts/construction/proxies/construction_greedy_mesh_compiler.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")

const CONSTRUCT_ID := "construct/c24/mesh-fixture"
const SECTION_ID := "section/c24/mesh-fixture/p000000_p000000_p000000"

static func sample_artifact(material_suffix: String = "") -> Dictionary:
	var faces: Array = [
		_grid_face("X", 1, 1, 0, 0, "hull%s" % material_suffix),
		_grid_face("X", 1, 1, 1, 0, "hull%s" % material_suffix),
		_grid_face("Y", -1, -1, 0, 0, "structure%s" % material_suffix),
		_grid_face("Z", 1, 1, 0, 0, "hull%s" % material_suffix),
		{
			"kind": "FALLBACK",
			"axis": "Z",
			"direction": -1,
			"section_id": SECTION_ID,
			"part_id": "part/c24/fallback",
			"material_key": "detail%s" % material_suffix,
			"position_m": [2.0, 0.0, 0.0],
			"dimensions_m": [0.5, 1.5, 0.25],
		},
	]
	var result: Dictionary = Greedy.compile_artifact(
		CONSTRUCT_ID,
		1,
		"a".repeat(64),
		1,
		Artifact.SECTION,
		"SIMPLIFIED",
		[SECTION_ID],
		[-0.5, -0.75, -0.5],
		[2.25, 1.5, 0.5],
		5,
		faces
	)
	return result["artifact"]

static func empty_artifact() -> Dictionary:
	var result: Dictionary = Greedy.compile_artifact(
		CONSTRUCT_ID,
		1,
		"a".repeat(64),
		1,
		Artifact.INTERIOR,
		"FULL",
		[SECTION_ID],
		[-1.0, -1.0, -1.0],
		[1.0, 1.0, 1.0],
		0,
		[]
	)
	return result["artifact"]

static func invalid_grid_artifact() -> Dictionary:
	var artifact: Dictionary = sample_artifact()
	artifact = artifact.duplicate(true)
	artifact["material_batches"] = Array(artifact["material_batches"]).duplicate(true)
	var mutated := false
	for batch_index in range(artifact["material_batches"].size()):
		var batch: Dictionary = Dictionary(artifact["material_batches"][batch_index]).duplicate(true)
		batch["quads"] = Array(batch["quads"]).duplicate(true)
		for quad_index in range(batch["quads"].size()):
			var quad: Dictionary = Dictionary(batch["quads"][quad_index]).duplicate(true)
			if String(quad.get("kind", "")) == "GRID_QUAD":
				quad["width"] = 0
				batch["quads"][quad_index] = quad
				mutated = true
				break
		artifact["material_batches"][batch_index] = batch
		if mutated:
			break
	artifact["content_hash"] = Artifact.compute_content_hash(artifact)
	artifact["artifact_id"] = "proxy-artifact/%s" % artifact["content_hash"]
	artifact["checksum"] = Artifact.compute_checksum(artifact)
	return artifact

static func _grid_face(axis: String, direction: int, plane_q2: int, u: int, v: int, material_key: String) -> Dictionary:
	return {
		"kind": "GRID",
		"axis": axis,
		"direction": direction,
		"plane_q2": plane_q2,
		"u": u,
		"v": v,
		"section_id": SECTION_ID,
		"part_id": "part/c24/%s-%d-%d-%d" % [axis.to_lower(), direction + 1, u, v],
		"material_key": material_key,
	}
