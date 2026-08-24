extends RefCounted

## EG4 world fixture generator: a deterministic, seeded producer of KNOWN
## world-graph fixtures for the projection-aggregation stage.
##
## Output shape is a GatewayWorldGraphSnapshot contract dictionary
## (planet_simulator.gateway_world_graph_snapshot.v1) that PASSES
## GatewayWorldGraphSnapshot.validate(): read_only, reconstructible,
## canonical=false, WORLD_DIRECTORY provenance. The generated relations form a
## CONNECTED graph over every world and cover ALL SEVEN relation kinds.
##
## Determinism: generation is pure arithmetic over (seed, world_count). The
## same arguments always produce canonically identical output on any machine —
## no wall clock, no entropy, no iteration-order dependence.

const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")
const SnapshotScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const DEFAULT_WORLD_COUNT := 120
const DEFAULT_SEED := 20260901
const RELATION_KINDS: Array[String] = [
	"NEIGHBOR",
	"OVERLAP",
	"CONTAINS",
	"REFERENCE_FRAME_PARENT",
	"REFERENCE_FRAME_CHILD",
	"PORTAL_OR_TRANSITION",
	"VISUALLY_RELEVANT",
]
## Stride between ring-linked worlds for the secondary relation kinds; kept
## coprime-friendly so pairings spread across the whole fixture range.
const RING_STRIDE := 1
const KIND_PAIR_OFFSETS := {
	"OVERLAP": 3,
	"CONTAINS": 7,
	"REFERENCE_FRAME_PARENT": 11,
	"REFERENCE_FRAME_CHILD": 13,
	"PORTAL_OR_TRANSITION": 17,
	"VISUALLY_RELEVANT": 19,
}


## Deterministic whole-fixture snapshot: >= world_count worlds (exactly
## world_count), connected by NEIGHBOR rings, with one deterministic extra
## edge per remaining relation kind per world index band.
static func generate_world_graph_snapshot(
		seed: int,
		world_count: int,
		directory_revision: int = 1,
) -> Dictionary:
	var worlds: Array = []
	var relations: Array = []
	var count := maxi(world_count, 2)
	for index in range(count):
		worlds.append(_world_descriptor(seed, index))
	for index in range(count):
		# Ring edge keeps the whole fixture graph connected for ANY count.
		var next_index := (index + RING_STRIDE) % count
		relations.append(_relation(seed, "NEIGHBOR", index, next_index, 0))
		# One deterministic edge per secondary kind from this world; modulo
		# wrap-around keeps every endpoint inside the partition.
		var kind_slot := 1
		for kind_value in RELATION_KINDS:
			if kind_value == "NEIGHBOR":
				continue
			var offset := int(KIND_PAIR_OFFSETS[kind_value])
			var other := _seeded_offset_target(seed, index, offset, count)
			if other == index:
				other = (index + 1) % count
			relations.append(_relation(seed, kind_value, index, other, kind_slot))
			kind_slot += 1
	return SnapshotScript.create(
		_graph_snapshot_id(seed, count),
		directory_revision,
		directory_revision,
		worlds,
		relations,
		true,
		true,
		false,
	)


## Canonical JSON of the generated fixture (determinism oracle).
static func canonical_fixture_json(seed: int, world_count: int) -> String:
	return NetworkUtilsScript.canonical_json(generate_world_graph_snapshot(seed, world_count))


## Home-world id helper shared by planner tests and process workers so every
## EG4 consumer addresses the SAME deterministic entry world.
static func home_world_id(index: int = 0) -> String:
	return "world/eg4/fixture-%04d" % maxi(index, 0)


static func world_id_at(index: int) -> String:
	return "world/eg4/fixture-%04d" % index


static func _graph_snapshot_id(seed: int, world_count: int) -> String:
	return "world-graph/eg4-fixture-s%d-w%d" % [seed, world_count]


static func _world_descriptor(seed: int, index: int) -> Dictionary:
	var world_id := world_id_at(index)
	return WorldDescriptorScript.create(
		world_id,
		"planetary_region_fixture",
		"reference-frame/eg4/fixture-%04d" % index,
		{"kind": "grid_partition", "partition": _seeded_partition(seed, index)},
		{"kind": "sphere", "radius": 1000.0 + float(_seeded_noise(seed, index, 97))},
		"authority-subject/eg4/fixture-%04d" % index,
		["surface_geometry", "entity_states"],
		{"read_only": true, "allows_mutation": false},
		["lod_near", "lod_far"],
		{"neighbor_depth": 2},
		{"max_projection_neighbors": 4},
		1 + _seeded_noise(seed, index, 5),
	)


static func _relation(seed: int, kind_value: String, world_a_index: int, world_b_index: int, slot: int) -> Dictionary:
	var relation_id := "world-relation/eg4/%s-%06d" % [
		kind_value.to_lower().replace("_", "-"),
		_seeded_relation_ordinal(seed, kind_value, world_a_index, slot),
	]
	return WorldRelationScript.create(
		relation_id,
		world_id_at(world_a_index),
		world_id_at(world_b_index),
		kind_value,
		{"id": "eg4-transition-region-%06d" % _seeded_relation_ordinal(seed, kind_value, world_a_index, slot), "kind": "transition_region"},
		{"kind": "shared_reference_frame"},
		{"read_only": true, "allows_mutation": false},
		1 + _seeded_noise(seed, world_a_index * 31 + slot, 3),
	)


## ---- deterministic arithmetic helpers --------------------------------------


## Small integer mixing over 16-bit lanes: stable across platforms because it
## stays far inside 64-bit integer range (no overflow-dependent behavior).
static func _mix(value: int) -> int:
	var x := value & 0x7FFFFFFFFFFFFFFF
	var hi := (x >> 16) & 0xFFFF
	var lo := x & 0xFFFF
	x = ((hi * 48271) ^ (lo * 40503)) & 0xFFFFFFFF
	x = x ^ (x >> 13)
	return x


static func _seeded_noise(seed: int, index: int, modulus: int) -> int:
	return _mix(seed * 2654435761 + index * 40503 + modulus * 974711) % maxi(modulus, 1)


static func _seeded_partition(seed: int, index: int) -> int:
	return _seeded_noise(seed, index, 8)


static func _seeded_offset_target(seed: int, index: int, offset: int, count: int) -> int:
	var jitter := _seeded_noise(seed, index + offset, maxi(offset, 1))
	return (index + offset + jitter) % count


static func _seeded_relation_ordinal(seed: int, kind_value: String, index: int, slot: int) -> int:
	var kind_hash := 0
	for character in kind_value.to_lower():
		kind_hash = (kind_hash * 131 + character.unicode_at(0)) & 0xFFFFFF
	return _mix(seed + kind_hash * 7919 + index * 104729 + slot * 1299709) % 1000000
