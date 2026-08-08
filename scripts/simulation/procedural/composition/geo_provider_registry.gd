extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const ProviderDescriptorScript = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")

var _factories: Dictionary = {}


func register_factory(provider_id: String, factory: Callable) -> Dictionary:
	if not GeoUtilsScript.is_canonical_id(provider_id, 2):
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_FACTORY_ID")
	if not factory.is_valid():
		return GeoUtilsScript.failure("INVALID_GEO_PROVIDER_FACTORY", {"provider_id": provider_id})
	if _factories.has(provider_id):
		return GeoUtilsScript.failure("DUPLICATE_GEO_PROVIDER_FACTORY", {"provider_id": provider_id})
	_factories[provider_id] = factory
	return GeoUtilsScript.success({"provider_id": provider_id})


func has_factory(provider_id: String) -> bool:
	return _factories.has(provider_id)


func provider_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id in _factories.keys():
		ids.append(String(raw_id))
	ids.sort()
	return ids


func instantiate(descriptor: Dictionary) -> Dictionary:
	var validation: Dictionary = ProviderDescriptorScript.validate(descriptor)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_REGISTERED_PROVIDER_DESCRIPTOR", {"cause": validation.get("error_code", "")})
	var provider_id: String = String(descriptor["provider_id"])
	if not _factories.has(provider_id):
		return GeoUtilsScript.failure("UNREGISTERED_GEO_PROVIDER_FACTORY", {"provider_id": provider_id})
	var factory: Callable = _factories[provider_id]
	var provider = factory.call(descriptor.duplicate(true))
	if provider == null or not provider is RefCounted or not provider.has_method("get_descriptor"):
		return GeoUtilsScript.failure("GEO_PROVIDER_FACTORY_BUILD_FAILED", {"provider_id": provider_id})
	var actual = provider.get_descriptor()
	if not actual is Dictionary:
		return GeoUtilsScript.failure("GEO_PROVIDER_FACTORY_DESCRIPTOR_MISMATCH", {"provider_id": provider_id})
	if GeoUtilsScript.payload_hash(actual) != GeoUtilsScript.payload_hash(descriptor):
		return GeoUtilsScript.failure("GEO_PROVIDER_FACTORY_DESCRIPTOR_MISMATCH", {"provider_id": provider_id})
	return GeoUtilsScript.success({"provider": provider})
