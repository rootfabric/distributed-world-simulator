extends RefCounted

const SourceProbes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")

const ENVIRONMENT_ORDER: Array[String] = SourceProbes.PROBE_ORDER
const PROFILE_ORDER: Array[String] = RendererProfile.PROFILE_ORDER

static func run_all() -> Dictionary:
	var source := SourceProbes.run_all()
	var result := {}
	for environment_name in ENVIRONMENT_ORDER:
		var phenotype: Dictionary = source[environment_name]
		var graph: Dictionary = phenotype["growth_graph"]
		var description := RenderDescription.build(graph)
		var views := {}
		for profile_id in PROFILE_ORDER:
			var profile := RendererProfile.create(profile_id)
			views[profile_id] = RenderDescription.materialize(description, profile)
		result[environment_name] = {
			"phenotype_hash": String(phenotype.get("phenotype_hash", "")),
			"growth_graph": graph,
			"render_description": description,
			"materializations": views,
		}
	return result

static func compute_profile_matrix_hash(results: Dictionary) -> String:
	var tokens := PackedStringArray()
	for environment_name in ENVIRONMENT_ORDER:
		var item: Dictionary = results[environment_name]
		var description: Dictionary = item["render_description"]
		tokens.append("ENV|%s|%s|%s" % [environment_name, String(item["growth_graph"]["graph_hash"]), String(description["render_description_hash"])])
		for profile_id in PROFILE_ORDER:
			var materialization: Dictionary = item["materializations"][profile_id]
			tokens.append("PROFILE|%s|%s|%s" % [environment_name, profile_id, String(materialization["materialization_hash"])])
	return "\n".join(tokens).sha256_text()
