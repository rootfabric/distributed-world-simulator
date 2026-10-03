extends RefCounted
## T15 source-side fixture. Rebuilds exactly one T9 emitter leaf and the four
## dependent ancestors of family-b. Unchanged siblings are reused byte-for-byte.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const E = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_compiler_v1.gd")
const EF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t9_laser_emitter_fixture.gd")
const L = preload("res://scripts/research/fabric_bake0/r5_t10_laser_cannon_compiler_v1.gd")
const LF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t10_laser_cannon_fixture.gd")

static var compile_events := 0
static var source_leaf_traversals := 0
static var source_anchor_checks := 0

static func reset() -> void:
	compile_events = 0
	source_leaf_traversals = 0
	source_anchor_checks = 0

static func _compose(kind: String, id: String, children: Dictionary, revision: int) -> Dictionary:
	compile_events += 1
	return F.compose(kind, id, children, revision)

static func rebuild_family_b_emitter(current_family_b: Dictionary, current_disabled: bool, disable_one: bool, revision: int) -> Dictionary:
	if revision < 3:
		return U.failure("T15_FIXTURE_REVISION_TOO_OLD")
	var current_emitter: Dictionary = current_family_b.children.bank.children.unit03.children.cannon.children.emitter
	var current_graph := EF.make_graph("GAAS", current_disabled)
	if String(current_graph.graph_hash) != String(current_emitter.capsule.source_graph_hash):
		return U.failure("T15_SOURCE_UNBAKE_ANCHOR_MISMATCH")
	source_anchor_checks += 1
	var modules: Dictionary = current_family_b.children.bank.children.duplicate(true)
	var affected: Dictionary = modules.unit03.duplicate(true)
	var affected_children: Dictionary = affected.children.duplicate(true)
	var cannon_parts: Dictionary = affected_children.cannon.children.duplicate(true)
	var emitter_graph := EF.make_graph("GAAS", disable_one)
	source_leaf_traversals += int(emitter_graph.gain_cells.size())
	compile_events += 1
	var emitter: Dictionary = F.child(E, emitter_graph, "t13-5-unit03-emitter", revision)
	if not emitter.success:
		return emitter
	cannon_parts.emitter = emitter.details
	var cannon_graph := LF.make_graph(cannon_parts)
	compile_events += 1
	var cannon: Dictionary = L.compile(
		cannon_graph,
		F.request(
			cannon_graph.graph_hash,
			cannon_graph.material_catalog.catalog_hash,
			"t13-5-unit03-cannon-cooling",
			cannon_parts,
			revision
		),
		"capsule/t13-5-unit03-cannon-cooling",
		cannon_parts.power.descriptor,
		cannon_parts.emitter.descriptor,
		cannon_parts.cooling.descriptor
	)
	if not cannon.success:
		return cannon
	var cannon_bundle: Dictionary = cannon.details
	cannon_bundle.children = cannon_parts
	affected_children.cannon = cannon_bundle
	var module := _compose("T12_TURRET", "t13-5-unit03-cooling", affected_children, revision)
	if not module.success:
		return module
	modules.unit03 = module.details
	var bank := _compose("T12_BANK", "t13-5-bank-cooling", modules, revision)
	if not bank.success:
		return bank
	var ship := _compose("T12_SHIP", "t13-5-ship-cooling", {
		"battery": current_family_b.children.battery,
		"bank": bank.details,
	}, revision)
	if not ship.success:
		return ship
	return U.success(ship.details)
