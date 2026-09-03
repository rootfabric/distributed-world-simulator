extends RefCounted

## WORLD PACKS registry (WP0.10 comparison harness support).
##
## Maps pack ids to their presentation profile scripts. The registry is the
## single discovery point used by the gallery and the comparison harness;
## it carries no canonical authority.

const PROFILES: Dictionary = {
	"WP-MOON-INDUSTRIAL": "res://scripts/world_packs/packs/wp_moon_industrial.gd",
	"WP-MARS-DUST": "res://scripts/world_packs/packs/wp_mars_dust.gd",
}


static func ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for pack_id in PROFILES:
		result.append(String(pack_id))
	result.sort()
	return result


static func has(pack_id: String) -> bool:
	return PROFILES.has(pack_id)


static func profile_path(pack_id: String) -> String:
	return String(PROFILES[pack_id])


static func make_profile(pack_id: String) -> RefCounted:
	var script: GDScript = load(profile_path(pack_id))
	return script.new()
