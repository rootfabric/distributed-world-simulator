extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinitionScript = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetRecipeScript = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const GenerationContextScript = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQueryScript = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const VolumeQueryScript = preload("res://scripts/simulation/procedural/contracts/geo_volume_query.gd")
const FieldBundleScript = preload("res://scripts/simulation/procedural/contracts/geo_field_bundle.gd")
const GeoSampleScript = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const GeoProviderBaseScript = preload("res://scripts/simulation/procedural/providers/geo_provider.gd")

var _configured: bool = false
var _planet_definition: Dictionary = {}
var _recipe: Dictionary = {}
var _providers_by_id: Dictionary = {}
var _descriptors_by_id: Dictionary = {}
var _field_owner: Dictionary = {}
var _provider_order: Array[String] = []
var _provider_manifest_hash: String = ""


func configure(planet_definition: Dictionary, recipe: Dictionary, providers: Array) -> Dictionary:
	_clear()
	var planet_validation: Dictionary = PlanetDefinitionScript.validate(planet_definition)
	if not bool(planet_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_PLANET_DEFINITION", {"cause": planet_validation.get("error_code", "")})
	var recipe_validation: Dictionary = PlanetRecipeScript.validate(recipe)
	if not bool(recipe_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_PLANET_RECIPE", {"cause": recipe_validation.get("error_code", "")})
	if String(planet_definition["recipe_id"]) != String(recipe["recipe_id"]):
		return GeoUtilsScript.failure("PLANET_RECIPE_ID_MISMATCH")

	var expected_descriptors: Dictionary = {}
	for descriptor in recipe["provider_descriptors"]:
		var provider_id: String = String(descriptor["provider_id"])
		expected_descriptors[provider_id] = Dictionary(descriptor).duplicate(true)

	var implementations: Dictionary = {}
	for provider in providers:
		if provider == null or not provider is RefCounted:
			return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_IMPLEMENTATION")
		for required_method in ["get_descriptor", "supports_query_kind", "sample_surface", "sample_volume"]:
			if not provider.has_method(required_method):
				return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_IMPLEMENTATION", {"missing_method": required_method})
		var descriptor = provider.get_descriptor()
		if not descriptor is Dictionary:
			return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_DESCRIPTOR")
		var descriptor_validation: Dictionary = ProviderDescriptorScript.validate(descriptor)
		if not bool(descriptor_validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_DESCRIPTOR", {"cause": descriptor_validation.get("error_code", "")})
		var provider_id: String = String(descriptor["provider_id"])
		if implementations.has(provider_id):
			return GeoUtilsScript.failure("DUPLICATE_GEO_PROVIDER_IMPLEMENTATION", {"provider_id": provider_id})
		if not expected_descriptors.has(provider_id):
			return GeoUtilsScript.failure("UNDECLARED_GEO_PROVIDER", {"provider_id": provider_id})
		if GeoUtilsScript.payload_hash(descriptor) != GeoUtilsScript.payload_hash(expected_descriptors[provider_id]):
			return GeoUtilsScript.failure("GEO_PROVIDER_DESCRIPTOR_MISMATCH", {"provider_id": provider_id})
		implementations[provider_id] = provider

	for provider_id in expected_descriptors.keys():
		if not implementations.has(provider_id):
			return GeoUtilsScript.failure("UNKNOWN_GEO_PROVIDER", {"provider_id": String(provider_id)})

	var graph_result: Dictionary = _build_provider_graph(Array(recipe["provider_descriptors"]))
	if not bool(graph_result.get("success", false)):
		return graph_result

	var manifest_payload: Dictionary = {
		"recipe_id": recipe["recipe_id"],
		"recipe_version": recipe["recipe_version"],
		"provider_descriptors": recipe["provider_descriptors"],
	}
	var manifest_hash: String = GeoUtilsScript.payload_hash(manifest_payload)
	if manifest_hash.is_empty():
		return GeoUtilsScript.failure("INVALID_PROVIDER_MANIFEST_HASH")

	_planet_definition = planet_definition.duplicate(true)
	_recipe = recipe.duplicate(true)
	_providers_by_id = implementations
	_descriptors_by_id = graph_result["details"]["descriptors_by_id"].duplicate(true)
	_field_owner = graph_result["details"]["field_owner"].duplicate(true)
	_provider_order = Array(graph_result["details"]["provider_order"]).duplicate()
	_provider_manifest_hash = manifest_hash
	_configured = true
	return GeoUtilsScript.success({
		"provider_order": _provider_order.duplicate(),
		"provider_manifest_hash": _provider_manifest_hash,
	})


func is_configured() -> bool:
	return _configured


func get_provider_order() -> Array[String]:
	return _provider_order.duplicate()


func get_provider_manifest_hash() -> String:
	return _provider_manifest_hash


func sample_surface(context: Dictionary, query: Dictionary) -> Dictionary:
	return _sample(GeoProviderBaseScript.QUERY_SURFACE, context, query)


func sample_volume(context: Dictionary, query: Dictionary) -> Dictionary:
	return _sample(GeoProviderBaseScript.QUERY_VOLUME, context, query)


func _sample(query_kind: String, context: Dictionary, query: Dictionary) -> Dictionary:
	if not _configured:
		return GeoUtilsScript.failure("GEO_KERNEL_NOT_CONFIGURED")
	var context_validation: Dictionary = GenerationContextScript.validate(context)
	if not bool(context_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_GENERATION_CONTEXT", {"cause": context_validation.get("error_code", "")})
	var query_validation: Dictionary = (
		SurfaceQueryScript.validate(query)
		if query_kind == GeoProviderBaseScript.QUERY_SURFACE
		else VolumeQueryScript.validate(query)
	)
	if not bool(query_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_QUERY", {"cause": query_validation.get("error_code", "")})
	if String(context["body_id"]) != String(_planet_definition["body_id"]) or String(query["body_id"]) != String(_planet_definition["body_id"]):
		return GeoUtilsScript.failure("GEO_QUERY_BODY_MISMATCH")
	if String(context["generator_manifest_version"]) != String(_planet_definition["generator_manifest_version"]):
		return GeoUtilsScript.failure("GEO_GENERATOR_MANIFEST_VERSION_MISMATCH")

	var requested_fields: Array = query["requested_fields"]
	var needed_providers: Dictionary = {}
	for raw_field in requested_fields:
		var field_id: String = String(raw_field)
		if not _field_owner.has(field_id):
			return GeoUtilsScript.failure("UNAVAILABLE_REQUESTED_GEO_FIELD", {"field": field_id})
		_mark_provider_dependencies(String(_field_owner[field_id]), needed_providers)

	var fields: Dictionary = {}
	var provenance: Dictionary = {}
	for provider_id in _provider_order:
		if not needed_providers.has(provider_id):
			continue
		var descriptor: Dictionary = _descriptors_by_id[provider_id]
		for required_field in descriptor["requires"]:
			if not fields.has(required_field):
				return GeoUtilsScript.failure("GEO_PROVIDER_DEPENDENCY_NOT_READY", {
					"provider_id": provider_id,
					"field": String(required_field),
				})
		var input_fields: Dictionary = {}
		for required_field in descriptor["requires"]:
			input_fields[required_field] = fields[required_field]
		var provider = _providers_by_id[provider_id]
		if not bool(provider.supports_query_kind(query_kind)):
			return GeoUtilsScript.failure("GEO_PROVIDER_QUERY_KIND_UNSUPPORTED", {"provider_id": provider_id, "query_kind": query_kind})
		var response = (
			provider.sample_surface(context, query, input_fields)
			if query_kind == GeoProviderBaseScript.QUERY_SURFACE
			else provider.sample_volume(context, query, input_fields)
		)
		if not response is Dictionary or not bool(response.get("success", false)):
			return GeoUtilsScript.failure("GEO_PROVIDER_QUERY_FAILED", {
				"provider_id": provider_id,
				"cause": String(response.get("error_code", "INVALID_PROVIDER_RESPONSE")) if response is Dictionary else "INVALID_PROVIDER_RESPONSE",
			})
		var details = response.get("details", {})
		if not details is Dictionary:
			return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_OUTPUT", {"provider_id": provider_id})
		var output_candidate = details.get("values", {})
		if not output_candidate is Dictionary:
			return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_OUTPUT", {"provider_id": provider_id})
		var output_values: Dictionary = output_candidate
		var actual_fields: Array = output_values.keys()
		actual_fields.sort()
		var expected_fields: Array = Array(descriptor["provides"]).duplicate()
		if actual_fields != expected_fields:
			return GeoUtilsScript.failure("GEO_PROVIDER_OUTPUT_CONTRACT_MISMATCH", {"provider_id": provider_id})
		var output_safe: Dictionary = GeoUtilsScript.validate_json_safe(output_values, "$.geo_provider_output.%s" % provider_id)
		if not bool(output_safe.get("success", false)):
			return GeoUtilsScript.failure("NON_CANONICAL_GEO_PROVIDER_OUTPUT", {"provider_id": provider_id})
		for field_id in expected_fields:
			if fields.has(field_id):
				return GeoUtilsScript.failure("GEO_FIELD_OVERWRITE", {"field": String(field_id)})
			fields[field_id] = output_values[field_id]
			provenance[field_id] = provider_id

	var selected_values: Dictionary = {}
	var selected_provenance: Dictionary = {}
	for field_id in requested_fields:
		selected_values[field_id] = fields[field_id]
		selected_provenance[field_id] = provenance[field_id]
	var bundle: Dictionary = FieldBundleScript.create(selected_values, selected_provenance)
	var bundle_validation: Dictionary = FieldBundleScript.validate(bundle)
	if not bool(bundle_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_FIELD_BUNDLE", {"cause": bundle_validation.get("error_code", "")})
	var sample: Dictionary = GeoSampleScript.create(
		String(_planet_definition["body_id"]),
		query_kind,
		Array(query["body_fixed_position_m"]),
		bundle,
		_provider_manifest_hash
	)
	var sample_validation: Dictionary = GeoSampleScript.validate(sample)
	if not bool(sample_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_GEO_SAMPLE", {"cause": sample_validation.get("error_code", "")})
	return GeoUtilsScript.success({"sample": sample})


func _build_provider_graph(descriptors: Array) -> Dictionary:
	var descriptors_by_id: Dictionary = {}
	var field_owner: Dictionary = {}
	var adjacency: Dictionary = {}
	var indegree: Dictionary = {}
	for descriptor in descriptors:
		var provider_id: String = String(descriptor["provider_id"])
		if not bool(descriptor.get("deterministic", false)):
			return GeoUtilsScript.failure("NON_DETERMINISTIC_GEO_PROVIDER", {"provider_id": provider_id})
		descriptors_by_id[provider_id] = Dictionary(descriptor).duplicate(true)
		adjacency[provider_id] = []
		indegree[provider_id] = 0
		for raw_field in descriptor["provides"]:
			var field_id: String = String(raw_field)
			if field_owner.has(field_id):
				return GeoUtilsScript.failure("DUPLICATE_GEO_PROVIDER_OUTPUT", {
					"field": field_id,
					"first_provider_id": String(field_owner[field_id]),
					"second_provider_id": provider_id,
				})
			field_owner[field_id] = provider_id

	for descriptor in descriptors:
		var provider_id: String = String(descriptor["provider_id"])
		for raw_required_field in descriptor["requires"]:
			var required_field: String = String(raw_required_field)
			if not field_owner.has(required_field):
				return GeoUtilsScript.failure("MISSING_GEO_PROVIDER_DEPENDENCY", {"provider_id": provider_id, "field": required_field})
			var owner_id: String = String(field_owner[required_field])
			var children: Array = adjacency[owner_id]
			if not children.has(provider_id):
				children.append(provider_id)
				children.sort()
				adjacency[owner_id] = children
				indegree[provider_id] = int(indegree[provider_id]) + 1

	var ready: Array = []
	for provider_id in descriptors_by_id.keys():
		if int(indegree[provider_id]) == 0:
			ready.append(String(provider_id))
	ready.sort()
	var provider_order: Array[String] = []
	while not ready.is_empty():
		var provider_id: String = String(ready.pop_front())
		provider_order.append(provider_id)
		for child_id in adjacency[provider_id]:
			indegree[child_id] = int(indegree[child_id]) - 1
			if int(indegree[child_id]) == 0:
				ready.append(String(child_id))
				ready.sort()
	if provider_order.size() != descriptors_by_id.size():
		return GeoUtilsScript.failure("GEO_PROVIDER_DEPENDENCY_CYCLE")
	return GeoUtilsScript.success({
		"provider_order": provider_order,
		"field_owner": field_owner,
		"descriptors_by_id": descriptors_by_id,
	})


func _mark_provider_dependencies(provider_id: String, needed: Dictionary) -> void:
	if needed.has(provider_id):
		return
	needed[provider_id] = true
	var descriptor: Dictionary = _descriptors_by_id[provider_id]
	for required_field in descriptor["requires"]:
		_mark_provider_dependencies(String(_field_owner[required_field]), needed)


func _clear() -> void:
	_configured = false
	_planet_definition = {}
	_recipe = {}
	_providers_by_id = {}
	_descriptors_by_id = {}
	_field_owner = {}
	_provider_order = []
	_provider_manifest_hash = ""
