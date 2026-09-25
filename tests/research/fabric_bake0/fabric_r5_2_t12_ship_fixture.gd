extends RefCounted
## T12 research-only Construction/Matter fixture. Instance source IDs are unique.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const Revision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const B = preload("res://scripts/research/fabric_bake0/r5_t3_battery_compiler_v1.gd")
const BF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t3_battery_fixture.gd")
const P = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_compiler_v1.gd")
const PF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t6_power_stage_fixture.gd")
const E = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_compiler_v1.gd")
const EF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t9_laser_emitter_fixture.gd")
const K = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_compiler_v1.gd")
const KF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t8_cooling_fixture.gd")
const L = preload("res://scripts/research/fabric_bake0/r5_t10_laser_cannon_compiler_v1.gd")
const LF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t10_laser_cannon_fixture.gd")
const M = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_compiler_v1.gd")
const MF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t5_motor_generator_fixture.gd")
const G = preload("res://scripts/research/fabric_bake0/r5_t7_gearbox_compiler_v1.gd")
const GF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t7_gearbox_fixture.gd")
const S = preload("res://scripts/research/fabric_bake0/r5_t11_smart_servo_compiler_v1.gd")
const SF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t11_smart_servo_fixture.gd")

static func request(hash_value: String, material: String, id: String, children: Dictionary = {}, revision: int = 1) -> Dictionary:
	var deps: Array = [{"dependency_id":"dependency/t12", "dependency_hash":U.canonical_hash({"compiler":"T12_R1"})}]
	for slot in children: deps.append({"dependency_id":"dependency/" + slot, "dependency_hash":children[slot].capsule.checksum})
	var dependency := Dependencies.create(deps)
	var sources: Array = [Revision.create("CONSTRUCTION", "construct/" + id, 25, revision, hash_value, dependency.dependency_hash)]
	if not material.is_empty(): sources.append(Revision.create("MATTER", "matter/" + id, 25, 1, material, dependency.dependency_hash))
	var records: Array = []; var mutable: Array = []
	for source in sources:
		records.append({"source_domain":source.source_domain, "source_id":source.source_id, "authority_epoch":25, "owner_id":"server/fabric-r5"})
		mutable.append(U.source_key(source.source_domain, source.source_id))
	return {"artifact_id":"artifact/" + id, "build_generation":1, "canonical_source_frontier":Frontier.create(sources),
		"authority_envelope":Authority.create("server/fabric-r5", records, mutable), "dependency_set":dependency}

static func child(compiler: GDScript, graph: Dictionary, id: String, revision: int = 1) -> Dictionary:
	var result: Dictionary = compiler.compile(graph, request(graph.graph_hash, graph.material_catalog.catalog_hash, id, {}, revision), "capsule/" + id)
	if not result.success: return result
	var b: Dictionary = result.details
	b.children = {}
	return U.success(b)

static func compose(kind: String, id: String, children: Dictionary, revision: int = 1) -> Dictionary:
	return C.compile(kind, children, request(C.graph_hash(kind, children), "", id, children, revision))

static func turret(id: String) -> Dictionary:
	var ch := {}
	var power := child(P, PF.make_graph(), id + "-power")
	var emitter := child(E, EF.make_graph(), id + "-emitter")
	var cooling := child(K, KF.make_graph(), id + "-cooling")
	for r in [power, emitter, cooling]:
		if not r.success: return r
	var parts := {"power":power.details, "emitter":emitter.details, "cooling":cooling.details}
	var graph := LF.make_graph(parts)
	var cannon := L.compile(graph, request(graph.graph_hash, graph.material_catalog.catalog_hash, id + "-cannon", parts),
		"capsule/" + id + "-cannon", parts.power.descriptor, parts.emitter.descriptor, parts.cooling.descriptor)
	if not cannon.success: return cannon
	ch.cannon = cannon.details; ch.cannon.children = parts
	var motor := child(M, MF.make_graph(), id + "-motor")
	var gear := child(G, GF.make_graph(), id + "-gear")
	for r in [motor, gear]:
		if not r.success: return r
	parts = {"motor":motor.details, "gearbox":gear.details}
	graph = SF.make_graph(parts)
	var servo := S.compile(graph, request(graph.graph_hash, "", id + "-servo", parts), "capsule/" + id + "-servo", parts.motor.descriptor, parts.gearbox.descriptor)
	if not servo.success: return servo
	ch.servo = servo.details; ch.servo.children = parts
	var drive := child(P, PF.make_graph(), id + "-drive")
	if not drive.success: return drive
	ch.drive = drive.details
	return compose("T12_TURRET", id, ch)

static func assemble(battery: Dictionary, modules: Dictionary, revision: int = 1) -> Dictionary:
	var bank := compose("T12_BANK", "t12-bank", modules, revision)
	if not bank.success: return bank
	return compose("T12_SHIP", "t12-ship", {"battery":battery, "bank":bank.details}, revision)

static func make_ship(count: int = 3, quality: float = 1.0) -> Dictionary:
	var battery := child(B, BF.make_graph("LFP", quality), "t12-battery")
	if not battery.success: return battery
	var modules := {}
	for i in range(count):
		var id := "t12-unit%02d" % (i + 1)
		var module := turret(id)
		if not module.success: return module
		modules["unit%02d" % (i + 1)] = module.details
	return assemble(battery.details, modules)

static func replace_third_emitter(ship: Dictionary) -> Dictionary:
	var modules: Dictionary = ship.children.bank.children.duplicate(true)
	var affected: Dictionary = modules.unit03
	var parts: Dictionary = affected.children.cannon.children.duplicate(true)
	var emitter := child(E, EF.make_graph("GAAS", true), "t12-unit03-emitter", 2)
	if not emitter.success: return emitter
	parts.emitter = emitter.details
	var graph := LF.make_graph(parts)
	var cannon := L.compile(graph, request(graph.graph_hash, graph.material_catalog.catalog_hash, "t12-unit03-cannon", parts, 2),
		"capsule/t12-unit03-cannon", parts.power.descriptor, parts.emitter.descriptor, parts.cooling.descriptor)
	if not cannon.success: return cannon
	affected.children.cannon = cannon.details; affected.children.cannon.children = parts
	var module := compose("T12_TURRET", "t12-unit03", affected.children, 2)
	if not module.success: return module
	modules.unit03 = module.details
	return assemble(ship.children.battery, modules, 2)

static func commands(count: int = 3, laser: float = 400.0, position: float = 0.2) -> Dictionary:
	var values := {}
	for i in range(count):
		values["unit%02d" % (i + 1)] = {"target_position_rad":position, "target_velocity_rad_s":0.0,
			"external_torque_nm":0.0, "laser_current_a":laser, "pwm_hz":20000.0, "mass_flow_kg_s":0.25, "range_m":1000.0}
	return values
