extends SceneTree

## EG4 L0: the deterministic known-world fixture generator.
## Predicates: a seeded generation produces a VALID GatewayWorldGraphSnapshot
## with at least known_world_fixture_minimum=100 worlds; relations form a
## CONNECTED graph covering ALL SEVEN relation kinds; generation is fully
## deterministic (canonical JSON equality across runs); and the COMMITTED
## JSON fixture under tests/network/fixtures/ is exactly that deterministic
## output for the canonical seed.

const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")
const SnapshotScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const KNOWN_WORLD_FIXTURE_MINIMUM := 100
const REQUIRED_KINDS: Array[String] = [
	"NEIGHBOR", "OVERLAP", "CONTAINS", "REFERENCE_FRAME_PARENT",
	"REFERENCE_FRAME_CHILD", "PORTAL_OR_TRANSITION", "VISUALLY_RELEVANT",
]
const FIXTURE_PATH := "res://tests/network/fixtures/eg4_world_graph_fixture.json"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-fixture][FAIL] %s" % message)


func _init() -> void:
	var snapshot: Dictionary = Generator.generate_world_graph_snapshot(Generator.DEFAULT_SEED, Generator.DEFAULT_WORLD_COUNT)
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	_assert(bool(validation.get("success", false)),
			"generated snapshot failed contract validation: %s %s" % [String(validation.get("error_code", "")), str(validation.get("details", {}))])

	var worlds: Array = snapshot.get("worlds", [])
	var relations: Array = snapshot.get("relations", [])
	_assert(worlds.size() >= KNOWN_WORLD_FIXTURE_MINIMUM,
			"fixture has %d worlds, minimum is %d" % [worlds.size(), KNOWN_WORLD_FIXTURE_MINIMUM])
	_assert(relations.size() >= worlds.size(), "fixture graph too sparse to be connected")

	var kinds := {}
	for raw_relation in relations:
		kinds[String(Dictionary(raw_relation).get("relation_kind", ""))] = true
	for kind_value in REQUIRED_KINDS:
		_assert(bool(kinds.get(kind_value, false)), "fixture missing relation kind %s" % kind_value)

	_assert(_is_connected(worlds, relations), "fixture relation graph is not connected")

	# Determinism: same seed + count -> canonically identical output.
	var again: Dictionary = Generator.generate_world_graph_snapshot(Generator.DEFAULT_SEED, Generator.DEFAULT_WORLD_COUNT)
	_assert(NetworkUtilsScript.canonical_json(again) == NetworkUtilsScript.canonical_json(snapshot),
			"generation is not deterministic for the canonical seed")
	var other_seed: Dictionary = Generator.generate_world_graph_snapshot(Generator.DEFAULT_SEED + 1, Generator.DEFAULT_WORLD_COUNT)
	_assert(NetworkUtilsScript.canonical_json(other_seed) != NetworkUtilsScript.canonical_json(snapshot),
			"different seeds produced identical fixtures")

	# The committed JSON fixture must be EXACTLY the deterministic output.
	var committed: Dictionary = _read_fixture()
	_assert(not committed.is_empty(), "committed fixture missing or unparsable at %s" % FIXTURE_PATH)
	if not committed.is_empty():
		_assert(int(committed.get("world_count", -1)) >= KNOWN_WORLD_FIXTURE_MINIMUM,
				"committed fixture world_count below the known-world minimum")
		var committed_snapshot: Dictionary = Dictionary(committed.get("snapshot", {}))
		var committed_validation: Dictionary = SnapshotScript.validate(committed_snapshot)
		_assert(bool(committed_validation.get("success", false)),
				"committed fixture snapshot invalid: %s" % String(committed_validation.get("error_code", "")))
		_assert(NetworkUtilsScript.canonical_json(committed_snapshot) == NetworkUtilsScript.canonical_json(snapshot),
				"committed fixture drifted from the deterministic generator output")
		_assert(String(Dictionary(Array(committed_snapshot.get("worlds", []))[0]).get("world_id", "")) == Generator.home_world_id(0),
				"home world id convention broken")

	_finish()


func _is_connected(worlds: Array, relations: Array) -> bool:
	var adjacency: Dictionary = {}
	for raw_world in worlds:
		adjacency[String(Dictionary(raw_world).get("world_id", ""))] = []
	for raw_relation in relations:
		var relation: Dictionary = Dictionary(raw_relation)
		var a := String(relation.get("world_a", ""))
		var b := String(relation.get("world_b", ""))
		if not adjacency.has(a) or not adjacency.has(b):
			return false
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)
	if adjacency.is_empty():
		return false
	var start := Generator.home_world_id(0)
	if not adjacency.has(start):
		return false
	var visited := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor_value in adjacency[current]:
			var neighbor := String(neighbor_value)
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return visited.size() == adjacency.size()


func _read_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	return parsed if parsed is Dictionary else {}


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_world_fixture_l0",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-fixture] FIXTURE PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-fixture] FIXTURE FAIL")
		quit(1)
