class_name ProductionAvatarBootstrap
extends RefCounted

const Contract = preload(
	"res://scripts/characters/avatar/avatar_contract.gd"
)
const Catalog = preload(
	"res://scripts/characters/avatar/avatar_catalog.gd"
)
const ProviderRegistry = preload(
	"res://scripts/characters/avatar/avatar_provider_registry.gd"
)

const CATALOG_PATH := (
	"res://config/characters/production-avatar-catalog.v1.json"
)
const PROVIDER_MANIFEST_PATH := (
	"res://config/characters/avatar-provider-manifest.v1.json"
)
const PROVIDER_MANIFEST_SCHEMA := (
	"planet_simulator.avatar_provider_manifest.v1"
)

static func create_runtime(
	catalog_path: String = CATALOG_PATH,
	provider_manifest_path: String = PROVIDER_MANIFEST_PATH
) -> Dictionary:
	var catalog := Catalog.new()
	var loaded: Dictionary = catalog.load_path(catalog_path)
	if not bool(loaded.get("success", false)):
		return loaded

	var manifest_result := _load_provider_manifest(
		provider_manifest_path
	)
	if not bool(manifest_result.get("success", false)):
		return manifest_result

	var providers := ProviderRegistry.new()
	for descriptor_value in manifest_result.get(
		"details",
		{}
	).get("providers", []):
		if not descriptor_value is Dictionary:
			return Contract.failure(
				"AVATAR_PROVIDER_DESCRIPTOR_INVALID"
			)
		var instantiated := _instantiate_provider(
			Dictionary(descriptor_value)
		)
		if not bool(instantiated.get("success", false)):
			return instantiated
		var registered: Dictionary = providers.register_provider(
			instantiated.get("details", {}).get("provider")
		)
		if not bool(registered.get("success", false)):
			return registered

	var sealed: Dictionary = providers.seal()
	if not bool(sealed.get("success", false)):
		return sealed

	return Contract.success({
		"catalog": catalog,
		"providers": providers,
		"catalog_path": catalog_path,
		"provider_manifest_path": provider_manifest_path,
	})

static func _load_provider_manifest(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return Contract.failure(
			"AVATAR_PROVIDER_MANIFEST_READ_FAILED",
			{"path": path}
		)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return Contract.failure(
			"AVATAR_PROVIDER_MANIFEST_JSON_INVALID",
			{"path": path}
		)
	var manifest: Dictionary = parsed
	if String(manifest.get("schema", "")) != PROVIDER_MANIFEST_SCHEMA:
		return Contract.failure(
			"AVATAR_PROVIDER_MANIFEST_SCHEMA_INVALID"
		)
	var descriptors = manifest.get("providers", [])
	if not descriptors is Array or descriptors.is_empty():
		return Contract.failure(
			"AVATAR_PROVIDER_MANIFEST_EMPTY"
		)
	var seen: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for descriptor_value in descriptors:
		if not descriptor_value is Dictionary:
			return Contract.failure(
				"AVATAR_PROVIDER_DESCRIPTOR_INVALID"
			)
		var descriptor: Dictionary = Dictionary(
			descriptor_value
		).duplicate(true)
		var provider_id := Contract.normalized_id(
			descriptor.get("provider_id", "")
		)
		var factory_script := String(
			descriptor.get("factory_script", "")
		).strip_edges()
		if not Contract.valid_id(provider_id):
			return Contract.failure(
				"AVATAR_PROVIDER_ID_INVALID"
			)
		if (
			not factory_script.begins_with("res://")
			or not factory_script.ends_with(".gd")
		):
			return Contract.failure(
				"AVATAR_PROVIDER_FACTORY_PATH_INVALID",
				{
					"provider_id": provider_id,
					"factory_script": factory_script,
				}
			)
		if seen.has(provider_id):
			return Contract.failure(
				"AVATAR_PROVIDER_DUPLICATE",
				{"provider_id": provider_id}
			)
		seen[provider_id] = true
		normalized.append({
			"provider_id": provider_id,
			"factory_script": factory_script,
		})
	return Contract.success({
		"providers": normalized,
		"provider_count": normalized.size(),
		"path": path,
	})

static func _instantiate_provider(
	descriptor: Dictionary
) -> Dictionary:
	var provider_id := String(
		descriptor.get("provider_id", "")
	)
	var factory_script := String(
		descriptor.get("factory_script", "")
	)
	var factory = load(factory_script)
	if factory == null or not factory.can_instantiate():
		return Contract.failure(
			"AVATAR_PROVIDER_FACTORY_LOAD_FAILED",
			{
				"provider_id": provider_id,
				"factory_script": factory_script,
			}
		)
	var provider = factory.new()
	if (
		provider == null
		or not provider.has_method("get_provider_id")
		or not provider.has_method("supports")
		or not provider.has_method("create_presenter")
	):
		return Contract.failure(
			"AVATAR_PROVIDER_INTERFACE_INVALID",
			{"provider_id": provider_id}
		)
	var runtime_provider_id := Contract.normalized_id(
		provider.get_provider_id()
	)
	if runtime_provider_id != provider_id:
		return Contract.failure(
			"AVATAR_PROVIDER_MANIFEST_ID_MISMATCH",
			{
				"manifest_provider_id": provider_id,
				"runtime_provider_id": runtime_provider_id,
			}
		)
	return Contract.success({
		"provider": provider,
		"provider_id": provider_id,
		"factory_script": factory_script,
	})
