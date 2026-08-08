extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const RegistryScript = preload("res://scripts/simulation/procedural/composition/geo_provider_registry.gd")
const BaseSurfaceProviderScript = preload("res://scripts/simulation/procedural/providers/base_surface_provider_v1.gd")
const CasualMacroLayerScript = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_layer_provider_v1.gd")
const AlternativeMacroScript = preload("res://scripts/simulation/procedural/providers/alternative_macro_terrain_provider_v1.gd")
const ValleyModifierScript = preload("res://scripts/simulation/procedural/providers/casual_valley_modifier_provider_v1.gd")


static func create_registry() -> Dictionary:
	var registry = RegistryScript.new()
	for registration in [
		[BaseSurfaceProviderScript.PROVIDER_ID, func(d): return BaseSurfaceProviderScript.new(float(d["parameters"]["base_height_m"]))],
		[CasualMacroLayerScript.PROVIDER_ID, func(d): return CasualMacroLayerScript.new(int(d["parameters"]["seed"]), float(d["parameters"]["nominal_radius_m"]), float(d["parameters"]["amplitude_m"]), float(d["parameters"]["base_wavelength_m"]), int(d["parameters"]["octaves"]), float(d["parameters"]["persistence"]))],
		[AlternativeMacroScript.PROVIDER_ID, func(d): return AlternativeMacroScript.new(int(d["parameters"]["seed"]), float(d["parameters"]["amplitude_m"]), float(d["parameters"]["frequency"]))],
		[ValleyModifierScript.PROVIDER_ID, func(d): return ValleyModifierScript.new(float(d["parameters"]["nominal_radius_m"]), float(d["parameters"]["half_width_m"]), float(d["parameters"]["depth_m"]), Array(d["parameters"]["plane_normal"]))],
	]:
		var result: Dictionary = registry.register_factory(String(registration[0]), registration[1])
		if not bool(result.get("success", false)):
			return GeoUtilsScript.failure("G4_PROVIDER_CATALOG_REGISTRATION_FAILED", {"cause": result.get("error_code", "")})
	return GeoUtilsScript.success({"registry": registry})


static func casual_descriptors(
	seed: int = 2026080801,
	nominal_radius_m: float = 6000000.0,
	base_height_m: float = 0.0,
	amplitude_m: float = 900.0,
	base_wavelength_m: float = 600000.0,
	valley_half_width_m: float = 80000.0,
	valley_depth_m: float = 350.0
) -> Array:
	return [
		BaseSurfaceProviderScript.new(base_height_m).get_descriptor(),
		CasualMacroLayerScript.new(seed, nominal_radius_m, amplitude_m, base_wavelength_m, 4, 0.5).get_descriptor(),
		ValleyModifierScript.new(nominal_radius_m, valley_half_width_m, valley_depth_m).get_descriptor(),
	]


static func alternative_descriptors(
	seed: int = 2026080801,
	nominal_radius_m: float = 6000000.0,
	base_height_m: float = 0.0,
	amplitude_m: float = 900.0,
	frequency: float = 7.0,
	valley_half_width_m: float = 80000.0,
	valley_depth_m: float = 350.0
) -> Array:
	return [
		BaseSurfaceProviderScript.new(base_height_m).get_descriptor(),
		AlternativeMacroScript.new(seed, amplitude_m, frequency).get_descriptor(),
		ValleyModifierScript.new(nominal_radius_m, valley_half_width_m, valley_depth_m).get_descriptor(),
	]
