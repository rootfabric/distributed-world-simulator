extends RefCounted

## ECO.EVO7 LS4.1 — frozen research species catalog.
##
## The catalog is an immutable experiment input. It contains no biome labels,
## world coordinates, placement targets or per-world tuning. Functional axes
## participate in species identity; LS4.1 derives distinct founder identities
## from that identity while all species consume the same physical patch and
## environment field. Explicit shared-resource allocation begins only at LS4.3.

const SCHEMA := "distributed_world_simulator.ecology.evo7_ls41_species_catalog.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS4.1-CATALOG-R1"

const AXIS_FIELDS: Array[String] = [
    "growth_strategy",
    "water_demand",
    "light_demand",
    "nutrient_demand",
    "stress_tolerance",
    "reproduction_strategy",
]
const SPECIES_FIELDS: Array[String] = ["species_id", "display_name", "functional_axes"]

const _CATALOG := [
    {
        "species_id": "riparian_pioneer",
        "display_name": "Riparian Pioneer",
        "functional_axes": {
            "growth_strategy": 0.90,
            "water_demand": 0.90,
            "light_demand": 0.75,
            "nutrient_demand": 0.70,
            "stress_tolerance": 0.30,
            "reproduction_strategy": 0.90,
        },
    },
    {
        "species_id": "xeric_anchor",
        "display_name": "Xeric Anchor",
        "functional_axes": {
            "growth_strategy": 0.35,
            "water_demand": 0.20,
            "light_demand": 0.85,
            "nutrient_demand": 0.35,
            "stress_tolerance": 0.90,
            "reproduction_strategy": 0.40,
        },
    },
    {
        "species_id": "shade_weaver",
        "display_name": "Shade Weaver",
        "functional_axes": {
            "growth_strategy": 0.55,
            "water_demand": 0.55,
            "light_demand": 0.25,
            "nutrient_demand": 0.55,
            "stress_tolerance": 0.60,
            "reproduction_strategy": 0.65,
        },
    },
]

static func catalog() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for value in _CATALOG:
        out.append(Dictionary(value).duplicate(true))
    return out

static func validate_catalog(value: Array) -> bool:
    if value.size() < 3:
        return false
    var seen := {}
    var signatures := {}
    for item_value in value:
        if not item_value is Dictionary:
            return false
        var item: Dictionary = item_value
        if item.keys().size() != SPECIES_FIELDS.size():
            return false
        for field in SPECIES_FIELDS:
            if not item.has(field):
                return false
        var species_id := String(item.get("species_id", ""))
        if species_id.is_empty() or species_id != species_id.to_lower() or seen.has(species_id):
            return false
        seen[species_id] = true
        if String(item.get("display_name", "")).is_empty():
            return false
        var axes_value = item.get("functional_axes")
        if not axes_value is Dictionary:
            return false
        var axes: Dictionary = axes_value
        if axes.keys().size() != AXIS_FIELDS.size():
            return false
        var signature := PackedStringArray()
        for axis in AXIS_FIELDS:
            if not axes.has(axis):
                return false
            var raw = axes[axis]
            if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
                return false
            var number := float(raw)
            if not is_finite(number) or number < 0.0 or number > 1.0:
                return false
            signature.append("%s=%.6f" % [axis, number])
        var signature_text := "|".join(signature)
        if signatures.has(signature_text):
            return false
        signatures[signature_text] = true
        if species_hash(item).length() != 64:
            return false
    return true

static func species_hash(item: Dictionary) -> String:
    var axes_value = item.get("functional_axes")
    if not axes_value is Dictionary:
        return ""
    var axes: Dictionary = axes_value
    var tokens := PackedStringArray([
        SCHEMA,
        VERSION,
        String(item.get("species_id", "")),
        String(item.get("display_name", "")),
    ])
    for axis in AXIS_FIELDS:
        if not axes.has(axis):
            return ""
        tokens.append("%s=%.6f" % [axis, float(axes[axis])])
    return "|".join(tokens).sha256_text()

static func catalog_hash(value: Array = _CATALOG) -> String:
    if not validate_catalog(value):
        return ""
    var hashes := PackedStringArray()
    for item_value in value:
        hashes.append(species_hash(Dictionary(item_value)))
    hashes.sort()
    return (SCHEMA + "|" + VERSION + "|catalog|" + "|".join(hashes)).sha256_text()
