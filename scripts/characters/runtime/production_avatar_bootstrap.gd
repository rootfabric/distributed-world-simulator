class_name ProductionAvatarBootstrap
extends RefCounted

const Catalog = preload(
	"res://scripts/characters/avatar/avatar_catalog.gd"
)
const ProviderRegistry = preload(
	"res://scripts/characters/avatar/avatar_provider_registry.gd"
)
const ProceduralProvider = preload(
	"res://scripts/characters/providers/procedural_humanoid_avatar_provider.gd"
)
const QuaterniusProvider = preload(
	"res://scripts/characters/providers/quaternius_avatar_provider.gd"
)

const CATALOG_PATH := (
	"res://config/characters/production-avatar-catalog.v1.json"
)

static func create_runtime(
	catalog_path: String = CATALOG_PATH
) -> Dictionary:
	var catalog := Catalog.new()
	var loaded: Dictionary = catalog.load_path(catalog_path)
	if not bool(loaded.get("success", false)):
		return loaded
	var providers := ProviderRegistry.new()
	for provider in [
		ProceduralProvider.new(),
		QuaterniusProvider.new(),
	]:
		var registered: Dictionary = providers.register_provider(provider)
		if not bool(registered.get("success", false)):
			return registered
	var sealed: Dictionary = providers.seal()
	if not bool(sealed.get("success", false)):
		return sealed
	return {
		"success": true,
		"error_code": "",
		"details": {
			"catalog": catalog,
			"providers": providers,
		},
	}
