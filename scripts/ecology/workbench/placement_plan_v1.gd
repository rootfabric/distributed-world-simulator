# EcologyWorkbench PlacementPlan v1 (P4, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: deterministic placement-entry generators for the ExperimentManifest
#   (manual, grid, zone_seeded_random, same_founders_different_zones,
#   different_founders_same_zone, mixed, common_garden).
# Layer: 2 (SIMULATION / ORCHESTRATION) — INPUT layer only: produces manifest
#   placement entries; it never touches runtime field/population state.
# Canonical API used (owner map rows 4,5):
#   - genome_mutation_v1.gd: draw(seed, key, count) — the ONLY RNG stream used
#     for seeded-random placements (no own RNG)  [A3]
#   - environment_field_contract_v1.gd: valid_footprint / canonical spatial
#     addressing bounds; positions live INSIDE the field footprint  [A4]
# Spatial truth: zone -> cells uses the SAME contiguous-band mapping as
#   experiment_controller_v1._build_field:
#   zone index = min(zones-1, cell_index * zones / cells) over row-major
#   cell indices (x + z * width). Positions are canonical cell centres in mm
#   (origin + cell * cell_size + cell_size / 2) — never a UI coordinate.
class_name EcoWorkbenchPlacementPlanV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")

const SCHEMA := "dws.ecology.workbench.placement-plan.v1"
const ENTRY_FIELDS := ["founder_ref", "zone_id", "position_mm"]
const PRESETS := [
	"manual",
	"grid",
	"zone_seeded_random",
	"same_founders_different_zones",
	"different_founders_same_zone",
	"mixed",
	"common_garden",
]

## Generate deterministic placement entries for `preset` from the manifest.
## options: {"zone_id": String} — target zone for different_founders_same_zone
## and common_garden (defaults to the first zone).
## Returns {"success": true, "preset": String, "entries": Array} or
## {"success": false, "error": String}. Entries always pass validate_entries.
static func generate(manifest: Dictionary, preset: String, options: Dictionary = {}) -> Dictionary:
	if not preset in PRESETS:
		return _fail("PLACEMENT_PRESET:" + preset)
	var environment: Dictionary = manifest.environment
	var founders: Array = manifest.founders
	var entries: Array = []
	match preset:
		"manual":
			entries = manifest.placement.entries.duplicate(true)
		"grid":
			entries = _grid(environment, founders)
		"zone_seeded_random":
			entries = _zone_seeded_random(environment, founders, int(manifest.seed))
		"same_founders_different_zones":
			entries = _same_founders_different_zones(environment, founders)
		"different_founders_same_zone":
			entries = _different_founders_same_zone(environment, founders, options)
		"mixed":
			entries = _mixed(environment, founders, int(manifest.seed))
		"common_garden":
			entries = _common_garden(environment, founders, options)
	var error := validate_entries(manifest, entries)
	if not error.is_empty():
		return _fail(error)
	return {"success": true, "preset": preset, "entries": entries}

## Validate generated placement entries against the manifest: every entry has
## exactly ENTRY_FIELDS, founder_ref and zone_id resolve, and the canonical
## position lies inside the field footprint in the claimed zone's cell band.
## Returns "" when valid.
static func validate_entries(manifest: Dictionary, entries: Variant) -> String:
	if not entries is Array or entries.is_empty():
		return "PLACEMENT_ENTRIES"
	var founder_ids := {}
	for founder in manifest.founders:
		founder_ids[founder.founder_id] = true
	var spatial: Dictionary = manifest.environment.spatial
	for index in entries.size():
		var entry: Variant = entries[index]
		if not entry is Dictionary or not C.keys(entry, ENTRY_FIELDS):
			return "PLACEMENT_ENTRY_FIELDS:%d" % index
		if not founder_ids.has(String(entry.founder_ref)):
			return "PLACEMENT_ENTRY_FOUNDER:%d" % index
		if zone_cells(manifest.environment, String(entry.zone_id)).is_empty():
			return "PLACEMENT_ENTRY_ZONE:%d" % index
		if not C.vector(entry.position_mm, FieldContract.MAX_PORT_COORD_MM):
			return "PLACEMENT_ENTRY_POSITION:%d" % index
		if zone_id_at(manifest.environment, entry.position_mm) != String(entry.zone_id):
			return "PLACEMENT_ENTRY_OUTSIDE_ZONE:%d" % index
	if not FieldContract.valid_footprint(spatial.origin_mm, spatial.cell_size_mm, spatial.width, spatial.depth):
		return "PLACEMENT_FOOTPRINT"
	return ""

## Zone of a canonical position (contiguous band mapping, controller-equal).
static func zone_id_at(environment: Dictionary, position_mm: Array) -> String:
	var spatial: Dictionary = environment.spatial
	var cell := cell_index(spatial, position_mm)
	if cell < 0:
		return ""
	var zones: Array = environment.zones
	var total: int = int(spatial.width) * int(spatial.depth)
	return String(zones[mini(zones.size() - 1, cell * zones.size() / total)].id)

## Row-major cell index of a canonical position; -1 when outside the footprint.
static func cell_index(spatial: Dictionary, position_mm: Array) -> int:
	var x: int = int(position_mm[0]) - int(spatial.origin_mm[0])
	var z: int = int(position_mm[2]) - int(spatial.origin_mm[2])
	if x < 0 or z < 0 or x >= int(spatial.width) * int(spatial.cell_size_mm) or z >= int(spatial.depth) * int(spatial.cell_size_mm):
		return -1
	return int(z / int(spatial.cell_size_mm)) * int(spatial.width) + int(x / int(spatial.cell_size_mm))

## Canonical cell centre in mm (controller _cell_center-equal).
static func cell_center(spatial: Dictionary, cell: int) -> Array:
	var x: int = cell % int(spatial.width)
	var z: int = int(cell / int(spatial.width))
	return [
		int(spatial.origin_mm[0]) + x * int(spatial.cell_size_mm) + int(spatial.cell_size_mm / 2),
		int(spatial.origin_mm[1]),
		int(spatial.origin_mm[2]) + z * int(spatial.cell_size_mm) + int(spatial.cell_size_mm / 2),
	]

## Cells belonging to a zone under the contiguous-band mapping (ascending).
static func zone_cells(environment: Dictionary, zone_id: String) -> Array:
	var spatial: Dictionary = environment.spatial
	var zones: Array = environment.zones
	var total: int = int(spatial.width) * int(spatial.depth)
	var cells: Array = []
	for cell in total:
		if String(zones[mini(zones.size() - 1, cell * zones.size() / total)].id) == zone_id:
			cells.append(cell)
	return cells

# --- generators (all deterministic; same manifest -> same entries) -----------

## grid: full founders x zones lattice; within each zone the founders are
## spread evenly over the zone's cells.
static func _grid(environment: Dictionary, founders: Array) -> Array:
	var spatial: Dictionary = environment.spatial
	var entries: Array = []
	for zone in environment.zones:
		var cells := zone_cells(environment, String(zone.id))
		for fi in founders.size():
			var cell: int = cells[fi * cells.size() / maxi(1, founders.size())]
			entries.append(_entry(String(founders[fi].founder_id), String(zone.id), cell_center(spatial, cell)))
	return entries

## zone_seeded_random: founders round-robin over zones; per-zone base seed is
## derived through the canonical mutation stream:
## base = Mutation.draw(manifest.seed, "placement/" + zone_id, count);
## position i draws its cell via Mutation.draw(base, "pos/%03d" % i, cells).
static func _zone_seeded_random(environment: Dictionary, founders: Array, seed: int) -> Array:
	var spatial: Dictionary = environment.spatial
	var zones: Array = environment.zones
	var per_zone := {}
	for fi in founders.size():
		var zone_id := String(zones[fi % zones.size()].id)
		if not per_zone.has(zone_id):
			per_zone[zone_id] = []
		per_zone[zone_id].append(String(founders[fi].founder_id))
	var entries: Array = []
	for zone in zones:
		var zone_id := String(zone.id)
		var assigned: Array = per_zone.get(zone_id, [])
		if assigned.is_empty():
			continue
		var cells := zone_cells(environment, zone_id)
		var base := Mutation.draw(seed, "placement/" + zone_id, maxi(1, assigned.size()))
		for i in assigned.size():
			var cell: int = cells[Mutation.draw(base, "pos/%03d" % i, cells.size())]
			entries.append(_entry(assigned[i], zone_id, cell_center(spatial, cell)))
	return entries

## same_founders_different_zones: every founder replicated into every zone,
## each at the SAME relative cell (zone's middle cell) — zone contrast layout.
static func _same_founders_different_zones(environment: Dictionary, founders: Array) -> Array:
	var spatial: Dictionary = environment.spatial
	var entries: Array = []
	for zone in environment.zones:
		var cells := zone_cells(environment, String(zone.id))
		var cell: int = cells[cells.size() / 2]
		for founder in founders:
			entries.append(_entry(String(founder.founder_id), String(zone.id), cell_center(spatial, cell)))
	return entries

## different_founders_same_zone: all founders in ONE zone, spread evenly over
## its cells (options.zone_id, default first zone).
static func _different_founders_same_zone(environment: Dictionary, founders: Array, options: Dictionary) -> Array:
	var spatial: Dictionary = environment.spatial
	var zone_id := _target_zone(environment, options)
	var cells := zone_cells(environment, zone_id)
	var entries: Array = []
	for fi in founders.size():
		var cell: int = cells[fi * cells.size() / maxi(1, founders.size())]
		entries.append(_entry(String(founders[fi].founder_id), zone_id, cell_center(spatial, cell)))
	return entries

## mixed: even-indexed founders get one grid entry per zone; odd-indexed
## founders get zone_seeded_random entries (round-robin zones, seeded cells).
static func _mixed(environment: Dictionary, founders: Array, seed: int) -> Array:
	var even_founders: Array = []
	var odd_founders: Array = []
	for fi in founders.size():
		if fi % 2 == 0:
			even_founders.append(founders[fi])
		else:
			odd_founders.append(founders[fi])
	var entries := _grid(environment, even_founders)
	entries.append_array(_zone_seeded_random(environment, odd_founders, seed))
	return entries

## common_garden: ALL founders in ONE zone at the SAME canonical position
## (options.zone_id, default first zone) — classic common-garden experiment.
static func _common_garden(environment: Dictionary, founders: Array, options: Dictionary) -> Array:
	var spatial: Dictionary = environment.spatial
	var zone_id := _target_zone(environment, options)
	var cells := zone_cells(environment, zone_id)
	var position := cell_center(spatial, cells[cells.size() / 2])
	var entries: Array = []
	for founder in founders:
		entries.append(_entry(String(founder.founder_id), zone_id, position))
	return entries

static func _target_zone(environment: Dictionary, options: Dictionary) -> String:
	var zones: Array = environment.zones
	if options.has("zone_id") and options.zone_id is String and not String(options.zone_id).is_empty():
		for zone in zones:
			if String(zone.id) == String(options.zone_id):
				return String(zone.id)
	return String(zones[0].id)

static func _entry(founder_ref: String, zone_id: String, position_mm: Array) -> Dictionary:
	return {
		"founder_ref": founder_ref,
		"zone_id": zone_id,
		"position_mm": [int(position_mm[0]), int(position_mm[1]), int(position_mm[2])],
	}

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
