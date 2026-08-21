extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.evo1_recruitment_traits.v1"
const VERSION := "1.0.0"
const DEFAULT_TRAIT_ID := "recruitment-traits/evo1-p2-2-default"
const EPSILON := 0.000000000001

static func create_default() -> Dictionary:
	return create(DEFAULT_TRAIT_ID, 0.45, 3.0)

static func create(trait_id: String, dormancy_fraction: float, seed_bank_half_life_years: float) -> Dictionary:
	if trait_id.is_empty() or trait_id != trait_id.strip_edges():
		return {}
	if not is_finite(dormancy_fraction) or dormancy_fraction < 0.0 or dormancy_fraction > 1.0:
		return {}
	if not is_finite(seed_bank_half_life_years) or seed_bank_half_life_years < 0.05 or seed_bank_half_life_years > 100.0:
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"trait_id": trait_id,
		"dormancy_fraction": dormancy_fraction,
		"seed_bank_half_life_years": seed_bank_half_life_years,
	}
	result["checksum"] = compute_checksum(result)
	return result

static func validate(traits: Dictionary) -> bool:
	if String(traits.get("schema", "")) != SCHEMA or String(traits.get("version", "")) != VERSION:
		return false
	var trait_id := String(traits.get("trait_id", ""))
	var dormancy := float(traits.get("dormancy_fraction", -1.0))
	var half_life := float(traits.get("seed_bank_half_life_years", -1.0))
	if trait_id.is_empty() or trait_id != trait_id.strip_edges():
		return false
	if not is_finite(dormancy) or dormancy < 0.0 or dormancy > 1.0:
		return false
	if not is_finite(half_life) or half_life < 0.05 or half_life > 100.0:
		return false
	return String(traits.get("checksum", "")) == compute_checksum(traits)

static func compute_checksum(traits: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(traits.get("trait_id", "")),
		"%.12f" % float(traits.get("dormancy_fraction", 0.0)),
		"%.12f" % float(traits.get("seed_bank_half_life_years", 0.0)),
	])).sha256_text()
