extends RefCounted
## T13.5 instrumented family fixture. Counts explicit compiler/compose invocations
## so acceptance can prove compile work follows unique structural deltas.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
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

static var compile_events := 0

static func reset() -> void:
	compile_events = 0

static func _child(compiler: GDScript, graph: Dictionary, id: String, revision: int = 1) -> Dictionary:
	compile_events += 1
	return F.child(compiler, graph, id, revision)

static func _compose(kind: String, id: String, children: Dictionary, revision: int = 1) -> Dictionary:
	compile_events += 1
	return F.compose(kind, id, children, revision)

static func _cannon(id: String, parts: Dictionary, revision: int = 1) -> Dictionary:
	var graph := LF.make_graph(parts)
	compile_events += 1
	var result: Dictionary = L.compile(
		graph,
		F.request(graph.graph_hash, graph.material_catalog.catalog_hash, id, parts, revision),
		"capsule/" + id,
		parts.power.descriptor,
		parts.emitter.descriptor,
		parts.cooling.descriptor
	)
	if not result.success:
		return result
	var bundle: Dictionary = result.details
	bundle.children = parts
	return U.success(bundle)

static func _servo(id: String, parts: Dictionary, revision: int = 1) -> Dictionary:
	var graph := SF.make_graph(parts)
	compile_events += 1
	var result: Dictionary = S.compile(
		graph,
		F.request(graph.graph_hash, "", id, parts, revision),
		"capsule/" + id,
		parts.motor.descriptor,
		parts.gearbox.descriptor
	)
	if not result.success:
		return result
	var bundle: Dictionary = result.details
	bundle.children = parts
	return U.success(bundle)

static func _turret(id: String) -> Dictionary:
	var power := _child(P, PF.make_graph(), id + "-power")
	var emitter := _child(E, EF.make_graph("GAAS"), id + "-emitter")
	var cooling := _child(K, KF.make_graph("WATER"), id + "-cooling")
	for result in [power, emitter, cooling]:
		if not result.success:
			return result
	var cannon := _cannon(id + "-cannon", {
		"power": power.details,
		"emitter": emitter.details,
		"cooling": cooling.details,
	})
	if not cannon.success:
		return cannon
	var motor := _child(M, MF.make_graph(), id + "-motor")
	var gear := _child(G, GF.make_graph(), id + "-gear")
	for result in [motor, gear]:
		if not result.success:
			return result
	var servo := _servo(id + "-servo", {"motor": motor.details, "gearbox": gear.details})
	if not servo.success:
		return servo
	var drive := _child(P, PF.make_graph(), id + "-drive")
	if not drive.success:
		return drive
	return _compose("T12_TURRET", id, {
		"cannon": cannon.details,
		"servo": servo.details,
		"drive": drive.details,
	})

static func make_base_ship() -> Dictionary:
	var battery := _child(B, BF.make_graph("LFP", 1.0), "t13-5-battery-lfp")
	if not battery.success:
		return battery
	var modules := {}
	for i in range(3):
		var id := "t13-5-unit%02d" % (i + 1)
		var module := _turret(id)
		if not module.success:
			return module
		modules["unit%02d" % (i + 1)] = module.details
	var bank := _compose("T12_BANK", "t13-5-bank-base", modules)
	if not bank.success:
		return bank
	return _compose("T12_SHIP", "t13-5-ship-base", {
		"battery": battery.details,
		"bank": bank.details,
	})

static func make_battery_variant(base: Dictionary) -> Dictionary:
	var battery := _child(B, BF.make_graph("NMC", 1.0), "t13-5-battery-nmc", 2)
	if not battery.success:
		return battery
	return _compose("T12_SHIP", "t13-5-ship-battery", {
		"battery": battery.details,
		"bank": base.children.bank,
	}, 2)

static func _replace_third_cannon_part(base: Dictionary, part_kind: String) -> Dictionary:
	var modules: Dictionary = base.children.bank.children.duplicate(true)
	var affected: Dictionary = modules.unit03
	var parts: Dictionary = affected.children.cannon.children.duplicate(true)
	if part_kind == "COOLING":
		var cooling := _child(K, KF.make_graph("GLYCOL"), "t13-5-unit03-cooling-glycol", 2)
		if not cooling.success:
			return cooling
		parts.cooling = cooling.details
	elif part_kind == "EMITTER":
		var emitter := _child(E, EF.make_graph("GAN"), "t13-5-unit03-emitter-gan", 2)
		if not emitter.success:
			return emitter
		parts.emitter = emitter.details
	else:
		return U.failure("T13_5_VARIANT_KIND_INVALID")
	var cannon := _cannon("t13-5-unit03-cannon-" + part_kind.to_lower(), parts, 2)
	if not cannon.success:
		return cannon
	affected.children.cannon = cannon.details
	var module := _compose("T12_TURRET", "t13-5-unit03-" + part_kind.to_lower(), affected.children, 2)
	if not module.success:
		return module
	modules.unit03 = module.details
	var bank := _compose("T12_BANK", "t13-5-bank-" + part_kind.to_lower(), modules, 2)
	if not bank.success:
		return bank
	return _compose("T12_SHIP", "t13-5-ship-" + part_kind.to_lower(), {
		"battery": base.children.battery,
		"bank": bank.details,
	}, 2)

static func make_cooling_variant(base: Dictionary) -> Dictionary:
	return _replace_third_cannon_part(base, "COOLING")

static func make_emitter_variant(base: Dictionary) -> Dictionary:
	return _replace_third_cannon_part(base, "EMITTER")

static func build_families() -> Dictionary:
	reset()
	var base := make_base_ship()
	if not base.success:
		return base
	var cooling := make_cooling_variant(base.details)
	if not cooling.success:
		return cooling
	var battery := make_battery_variant(base.details)
	if not battery.success:
		return battery
	var emitter := make_emitter_variant(base.details)
	if not emitter.success:
		return emitter
	return U.success({
		"family-a": base.details,
		"family-b": cooling.details,
		"family-c": battery.details,
		"family-d": emitter.details,
	})
