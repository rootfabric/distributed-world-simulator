class_name WorldFillDressing
extends RefCounted

## WF0.1 Environmental Dressing Contract (WORLD FILL train).
##
## Consumer-only, read-only derivation of presentation dressing decisions from
## canonical read-only surface descriptors.
##
## Contract guarantees:
## - DETERMINISTIC: same inputs + seed => identical outputs.
## - READ-ONLY: the input descriptor is never mutated and never aliased.
## - DEGRADES GRACEFULLY: missing producer fields yield defaults plus an
##   explicit "degraded_inputs" report, never an error.
## - PRESENTATION-ONLY: outputs feed WF0.2 scatter, WF0.3 decals, WF0.4
##   ambience and WF0.6 POI hints; they are never canonical truth, never
##   persisted server-side and never replicated.

const SCHEMA := "world_fill.dressing_decision.v1"

const DENSITY_BANDS: Array[String] = ["none", "sparse", "moderate", "dense"]

const FAMILY_PROFILES := {
	"stones": {"scale_range": [0.15, 1.4], "tilt_deg_range": [0.0, 18.0]},
	"boulders": {"scale_range": [0.8, 3.0], "tilt_deg_range": [0.0, 12.0]},
	"debris": {"scale_range": [0.1, 0.9], "tilt_deg_range": [0.0, 35.0]},
	"dry_branches": {"scale_range": [0.3, 1.6], "tilt_deg_range": [0.0, 55.0]},
	"crystals": {"scale_range": [0.2, 1.2], "tilt_deg_range": [0.0, 25.0]},
	"industrial_scrap": {"scale_range": [0.3, 2.2], "tilt_deg_range": [0.0, 45.0]},
}

const SURFACE_FAMILY_BANDS := {
	"regolith": {"stones": "dense", "debris": "moderate"},
	"dust": {"stones": "dense", "debris": "moderate"},
	"sand": {"stones": "dense", "debris": "moderate"},
	"rock": {"boulders": "moderate", "stones": "sparse"},
	"bedrock": {"boulders": "moderate", "stones": "sparse"},
	"ice": {"crystals": "moderate", "stones": "sparse"},
	"frost": {"crystals": "moderate", "stones": "sparse"},
	"metal": {"industrial_scrap": "dense", "debris": "moderate"},
	"industrial": {"industrial_scrap": "dense", "debris": "moderate"},
	"scrap": {"industrial_scrap": "dense", "debris": "moderate"},
	"soil": {"stones": "moderate", "dry_branches": "sparse"},
	"dirt": {"stones": "moderate", "dry_branches": "sparse"},
}

const SURFACE_DECALS := {
	"metal": ["scorch_mark"],
	"industrial": ["scorch_mark"],
	"scrap": ["scorch_mark"],
	"rock": ["material_exposure"],
	"bedrock": ["material_exposure"],
	"regolith": ["impact_dust"],
	"dust": ["impact_dust"],
	"sand": ["impact_dust"],
}

const BASE_DECALS: Array[String] = ["surface_wear"]

const WET_MOISTURE := 0.55
const DRY_MOISTURE := 0.2
const FLAT_SLOPE_DEG := 12.0
const STEEP_SLOPE_DEG := 40.0
const HIGH_ALTITUDE := 800.0
const UNKNOWN_SURFACE := "unknown"
const GENERIC_FAMILY := "stones"


static func derive(descriptor: Dictionary) -> Dictionary:
	var surface_type := _surface_type(descriptor)
	var position: Vector3 = descriptor.get("position", Vector3.ZERO)
	var slope_deg := _slope_deg(descriptor)
	var altitude := float(descriptor.get("altitude", position.y))
	var moisture := float(descriptor.get("moisture", -1.0))
	var ground_cover := String(descriptor.get("ground_cover", ""))
	var biome_tags := _tag_list(descriptor)
	var seed_value := int(descriptor.get("seed", 0))

	var families := _derive_families(
		surface_type, slope_deg, moisture, ground_cover
	)
	var decals := _derive_decals(surface_type, biome_tags)
	var ambience := _derive_ambience(biome_tags, altitude)
	var poi := _derive_poi(surface_type, slope_deg)
	var degraded := _degraded_inputs(descriptor)

	var payload := _payload(descriptor)
	var key := "%d:%d" % [payload.hash(), seed_value]

	return {
		"schema": SCHEMA,
		"determinism_key": key,
		"degraded_inputs": degraded,
		"prop_families": families,
		"decal_families": decals,
		"ambience_selector": ambience,
		"poi_eligibility": poi,
	}


static func _surface_type(descriptor: Dictionary) -> String:
	return String(descriptor.get("surface_type", UNKNOWN_SURFACE))


static func _slope_deg(descriptor: Dictionary) -> float:
	if descriptor.has("slope_deg"):
		return float(descriptor.get("slope_deg"))
	var normal: Vector3 = descriptor.get("normal", Vector3.UP)
	var angle := rad_to_deg(clampf(normal.angle_to(Vector3.UP), 0.0, PI))
	return snappedf(angle, 0.001)


static func _tag_list(descriptor: Dictionary) -> Array[String]:
	var raw: Array = descriptor.get("biome_tags", [])
	var tags: Array[String] = []
	for entry in raw:
		tags.append(String(entry))
	tags.sort()
	return tags


static func _payload(descriptor: Dictionary) -> String:
	var surface_type := _surface_type(descriptor)
	var position: Vector3 = descriptor.get("position", Vector3.ZERO)
	var slope_deg := _slope_deg(descriptor)
	var altitude := float(descriptor.get("altitude", position.y))
	var moisture := float(descriptor.get("moisture", -1.0))
	var temperature := float(descriptor.get("temperature_c", -999.0))
	var ground_cover := String(descriptor.get("ground_cover", ""))
	var seed_value := int(descriptor.get("seed", 0))
	return "|".join(PackedStringArray([
		surface_type,
		"%.3f" % position.x,
		"%.3f" % position.y,
		"%.3f" % position.z,
		"%.3f" % slope_deg,
		"%.3f" % altitude,
		"%.3f" % moisture,
		"%.3f" % temperature,
		ground_cover,
		",".join(_tag_list(descriptor)),
		str(seed_value),
	]))


static func _demote(band: String) -> String:
	var index := DENSITY_BANDS.find(band)
	if index <= 0:
		return DENSITY_BANDS[0]
	return DENSITY_BANDS[index - 1]


static func _promote(band: String) -> String:
	var index := DENSITY_BANDS.find(band)
	if index < 0 or index >= DENSITY_BANDS.size() - 1:
		return DENSITY_BANDS[DENSITY_BANDS.size() - 1]
	return DENSITY_BANDS[index + 1]


static func _derive_families(
	surface_type: String,
	slope_deg: float,
	moisture: float,
	ground_cover: String
) -> Array:
	var bands := {}
	var source: Dictionary = SURFACE_FAMILY_BANDS.get(surface_type, {})
	if source.is_empty():
		bands[GENERIC_FAMILY] = DENSITY_BANDS[1]
	else:
		for family in source:
			bands[family] = String(source[family])

	var steep := slope_deg >= STEEP_SLOPE_DEG
	for family in bands.keys():
		if steep and family != "boulders":
			bands[family] = _demote(bands[family])

	if moisture > WET_MOISTURE:
		bands.erase("dry_branches")
	elif moisture >= 0.0 and moisture < DRY_MOISTURE and surface_type in ["soil", "dirt"]:
		bands["dry_branches"] = DENSITY_BANDS[2]

	if ground_cover != "" and ground_cover != "none" and not bands.is_empty():
		var family := GENERIC_FAMILY
		if bands.has(family):
			bands[family] = _promote(bands[family])
		else:
			bands[family] = DENSITY_BANDS[1]

	var families: Array = []
	var sorted_keys := bands.keys()
	sorted_keys.sort()
	for family in sorted_keys:
		var band := String(bands[family])
		if band == DENSITY_BANDS[0]:
			continue
		var profile: Dictionary = FAMILY_PROFILES.get(family, {
			"scale_range": [0.2, 1.0],
			"tilt_deg_range": [0.0, 30.0],
		})
		families.append({
			"family": family,
			"density_band": band,
			"scale_range": (profile["scale_range"] as Array).duplicate(),
			"tilt_deg_range": (profile["tilt_deg_range"] as Array).duplicate(),
		})
	return families


static func _derive_decals(
	surface_type: String,
	biome_tags: Array[String]
) -> Array:
	var decals: Array[String] = []
	decals.append_array(BASE_DECALS.duplicate())
	var surface_decals: Array = SURFACE_DECALS.get(surface_type, [])
	decals.append_array(surface_decals.duplicate())
	if biome_tags.has("wreckage") or biome_tags.has("battlefield"):
		decals.append("impact_dust")
	var unique: Array[String] = []
	for decal in decals:
		if not unique.has(decal):
			unique.append(decal)
	return unique


static func _derive_ambience(biome_tags: Array[String], altitude: float) -> String:
	if biome_tags.has("cave"):
		return "underground_echo"
	if altitude > HIGH_ALTITUDE:
		return "thin_air_loop"
	if biome_tags.has("canyon"):
		return "wind_gusts"
	if biome_tags.has("open_plain"):
		return "open_wind"
	return "quiet_rubble"


static func _derive_poi(surface_type: String, slope_deg: float) -> Dictionary:
	return {
		"outpost": slope_deg <= 10.0,
		"beacon": true,
		"wreck": surface_type in ["rock", "regolith", "dust"],
		"mining_camp": surface_type in ["rock", "regolith"] and slope_deg <= 18.0,
		"cave_entrance": slope_deg >= 35.0,
		"landing_site": slope_deg <= 6.0,
	}


static func _degraded_inputs(descriptor: Dictionary) -> Array[String]:
	var degraded: Array[String] = []
	for field in [
		"surface_type",
		"position",
		"altitude",
		"slope_deg",
		"normal",
		"moisture",
		"temperature_c",
		"ground_cover",
		"biome_tags",
	]:
		if not descriptor.has(field):
			degraded.append(field)
	return degraded
