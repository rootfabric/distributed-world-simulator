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
const M = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_compiler_v1.gd")
const MF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t5_motor_generator_fixture.gd")
const MG = preload("res://scripts/research/fabric_bake0/motor_generator_graph_v1.gd")
const S = preload("res://scripts/research/fabric_bake0/r5_t11_smart_servo_compiler_v1.gd")
const SF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t11_smart_servo_fixture.gd")

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

static func make_projection_unsafe_motor_candidate(current_family_b: Dictionary, revision: int = 7) -> Dictionary:
	# Adversarial valid successor: keep topology identical but rebuild unit03's
	# motor with a much larger rotor radius, lowering the legal motor omega. This
	# lets acceptance supply a caller state that is valid for the old family but
	# invalid for the candidate and prove pre-flight rejection is side-effect free.
	var current_motor: Dictionary = current_family_b.children.bank.children.unit03.children.servo.children.motor
	var baseline_graph: Dictionary = MF.make_graph()
	if String(baseline_graph.graph_hash) != String(current_motor.capsule.source_graph_hash):
		return U.failure("T15_UNSAFE_PROBE_SOURCE_ANCHOR_MISMATCH")
	var sectors: Array = baseline_graph.rotor_sectors.duplicate(true)
	for index in range(sectors.size()):
		sectors[index].radius_m = float(sectors[index].radius_m) * 4.0
	var tight_graph := MG.create(
		"graph/r5-t15-projection-unsafe-motor",
		baseline_graph.material_catalog,
		baseline_graph.electromagnetic_profiles,
		baseline_graph.winding_segments,
		sectors
	)
	if tight_graph.is_empty():
		return U.failure("T15_UNSAFE_PROBE_GRAPH_INVALID")
	var motor := F.child(M, tight_graph, "t15-unsafe-unit03-motor", revision)
	if not motor.success:
		return motor

	var modules: Dictionary = current_family_b.children.bank.children.duplicate(true)
	var affected: Dictionary = modules.unit03.duplicate(true)
	var affected_children: Dictionary = affected.children.duplicate(true)
	var servo_parts: Dictionary = affected_children.servo.children.duplicate(true)
	servo_parts.motor = motor.details
	var servo_graph := SF.make_graph(servo_parts)
	var servo: Dictionary = S.compile(
		servo_graph,
		F.request(servo_graph.graph_hash, "", "t15-unsafe-unit03-servo", servo_parts, revision),
		"capsule/t15-unsafe-unit03-servo",
		servo_parts.motor.descriptor,
		servo_parts.gearbox.descriptor
	)
	if not servo.success:
		return servo
	var servo_bundle: Dictionary = servo.details
	servo_bundle.children = servo_parts
	affected_children.servo = servo_bundle
	var module := F.compose("T12_TURRET", "t15-unsafe-unit03", affected_children, revision)
	if not module.success:
		return module
	modules.unit03 = module.details
	var bank := F.compose("T12_BANK", "t15-unsafe-bank", modules, revision)
	if not bank.success:
		return bank
	var ship := F.compose("T12_SHIP", "t15-unsafe-ship", {
		"battery": current_family_b.children.battery,
		"bank": bank.details,
	}, revision)
	if not ship.success:
		return ship
	return U.success(ship.details)
