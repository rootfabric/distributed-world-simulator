class_name FabricConstruct0PresetFactory
extends RefCounted

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionRequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const ProjectionCompilerScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_compiler.gd")
const ContactCompiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const ContactRuntime = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_runtime_v1.gd")

const PRESETS: Array[String] = ["TABLE", "BRIDGE", "CART"]
const CONTACT_GRID: int = 21
const AUTHORITY_HASH := "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

static func build(preset: String) -> Dictionary:
	var spec := _spec(preset)
	if spec.is_empty():
		return _failure("CONSTRUCT0_UNKNOWN_PRESET", {"preset": preset})
	var aggregate = AggregateScript.new()
	var checked: Dictionary = aggregate.setup(
		"construct/construct0/%s" % preset.to_lower(),
		"item/construct0/%s/root" % preset.to_lower()
	)
	if not bool(checked.get("success", false)):
		return checked
	for index in range(Array(spec["parts"]).size()):
		var part_spec: Dictionary = spec["parts"][index]
		var part := PartScript.create(
			String(part_spec["part_id"]),
			String(part_spec["item_id"]),
			String(part_spec["kind"]),
			String(part_spec["role"]),
			float(part_spec["mass_kg"]),
			Array(part_spec["position"]).duplicate(true),
			{
				"geometry": {"bounding_box_m": Array(part_spec["size"]).duplicate(true)},
				"local_rotation_quaternion": Array(part_spec.get("rotation", [0.0, 0.0, 0.0, 1.0])).duplicate(true),
				"construct0_preset": preset,
			}
		)
		checked = aggregate.add_part(
			"construct0/%s/add-part-%03d" % [preset.to_lower(), index],
			aggregate.state_revision,
			part
		)
		if not bool(checked.get("success", false)):
			return checked
	for index in range(Array(spec["bonds"]).size()):
		var bond_spec: Dictionary = spec["bonds"][index]
		var bond := BondScript.create(
			String(bond_spec["bond_id"]),
			String(bond_spec["a"]),
			String(bond_spec["b"]),
			"RIGID",
			float(bond_spec.get("strength_n", 1000000.0))
		)
		checked = aggregate.add_bond(
			"construct0/%s/add-bond-%03d" % [preset.to_lower(), index],
			aggregate.state_revision,
			bond
		)
		if not bool(checked.get("success", false)):
			return checked
	var snapshot: Dictionary = aggregate.export_snapshot()
	checked = SnapshotScript.validate(snapshot)
	if not bool(checked.get("success", false)):
		return checked
	var projection_request := ProjectionRequestScript.create(
		snapshot,
		[],
		{},
		{},
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 1.0],
		1,
		1
	)
	var projection := ProjectionCompilerScript.compile(projection_request)
	if not bool(projection.get("success", false)):
		return projection
	var points := _contact_points(Vector2(float(spec["patch_size"][0]), float(spec["patch_size"][1])))
	var contact_request := _contact_request(snapshot, preset, spec, points)
	var baked := ContactCompiler.compile(contact_request)
	if not bool(baked.get("ok", false)):
		return _failure("CONSTRUCT0_CONTACT_BAKE_FAILED", {"b0_3": baked})
	var reverse_request: Dictionary = contact_request.duplicate(true)
	var reversed_points: Array = points.duplicate(true)
	reversed_points.reverse()
	reverse_request["points"] = reversed_points
	var reverse_baked := ContactCompiler.compile(reverse_request)
	if not bool(reverse_baked.get("ok", false)):
		return _failure("CONSTRUCT0_REVERSE_CONTACT_BAKE_FAILED", {"b0_3": reverse_baked})
	var model: Dictionary = baked["model"]
	var slide := ContactRuntime.maximum_dissipation_wrench(
		model,
		[1.0, 0.25, 0.35, 0.08, -0.12, 0.05]
	)
	if not bool(slide.get("ok", false)):
		return _failure("CONSTRUCT0_CONTACT_RUNTIME_FAILED", {"b0_3": slide})
	var tip := ContactRuntime.support(model, [0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	if not bool(tip.get("ok", false)):
		return _failure("CONSTRUCT0_TIP_QUERY_FAILED", {"b0_3": tip})
	var support_guard := ContactRuntime.normal_support_guard(
		model,
		float(model["normal_support_limit"]) * 0.75
	)
	if not bool(support_guard.get("ok", false)):
		return _failure("CONSTRUCT0_SUPPORT_GUARD_FAILED", {"b0_3": support_guard})
	return {
		"success": true,
		"preset": preset,
		"snapshot": snapshot,
		"runtime_descriptor": projection["descriptor"],
		"contact_points": points,
		"contact_model": model,
		"reverse_model_hash_equal": String(model["model_hash"]) == String(reverse_baked["model"]["model_hash"]),
		"maximum_dissipation": slide,
		"tip_support": tip,
		"support_guard": support_guard,
		"spec": spec.duplicate(true),
	}

static func unsupported_non_coplanar_probe(preset: String = "TABLE") -> Dictionary:
	var built := build(preset)
	if not bool(built.get("success", false)):
		return built
	var snapshot: Dictionary = built["snapshot"]
	var spec: Dictionary = built["spec"]
	var points: Array = Array(built["contact_points"]).duplicate(true)
	var changed: Dictionary = Dictionary(points[points.size() / 2]).duplicate(true)
	var p: Vector3 = changed["position"]
	changed["position"] = Vector3(p.x, p.y + 0.01, p.z)
	points[points.size() / 2] = changed
	return ContactCompiler.compile(_contact_request(snapshot, preset, spec, points))

static func _contact_request(snapshot: Dictionary, preset: String, spec: Dictionary, points: Array) -> Dictionary:
	var normal_support := _total_mass(snapshot) * 9.81
	return {
		"model_id": "artifact/construct0/%s/contact" % preset.to_lower(),
		"patch_id": "patch/construct0/%s/support" % preset.to_lower(),
		"source_frontier_hash": String(snapshot["checksum"]),
		"physical_graph_hash": _hash({"construct_checksum": snapshot["checksum"], "preset": preset}),
		"parent_artifact_checksum": _hash({"construct0_parent": snapshot["checksum"]}),
		"authority_checksum": AUTHORITY_HASH,
		"origin": Vector3.ZERO,
		"normal": Vector3.UP,
		"t1": Vector3.RIGHT,
		"t2": Vector3.BACK,
		"points": points,
		"normal_support_limit": normal_support,
		"mu_tangent": float(spec.get("mu_tangent", 0.65)),
		"mu_rolling": float(spec.get("mu_rolling", 0.04)),
		"mu_torsion": float(spec.get("mu_torsion", 0.03)),
		"effective_radius": 0.5 * minf(float(spec["patch_size"][0]), float(spec["patch_size"][1])),
		"minimum_reduction_ratio": 2.0,
	}

static func _contact_points(size: Vector2) -> Array:
	var points: Array = []
	for iz in range(CONTACT_GRID):
		for ix in range(CONTACT_GRID):
			var fx := float(ix) / float(CONTACT_GRID - 1)
			var fz := float(iz) / float(CONTACT_GRID - 1)
			points.append({
				"id": "contact/%03d/%03d" % [iz, ix],
				"position": Vector3(
					lerpf(-size.x * 0.5, size.x * 0.5, fx),
					0.0,
					lerpf(-size.y * 0.5, size.y * 0.5, fz)
				),
			})
	return points

static func _total_mass(snapshot: Dictionary) -> float:
	var total := 0.0
	for part_any in snapshot["parts"]:
		total += float(Dictionary(part_any)["mass_kg"])
	return total

static func _spec(preset: String) -> Dictionary:
	match preset:
		"TABLE":
			return _table_spec()
		"BRIDGE":
			return _bridge_spec()
		"CART":
			return _cart_spec()
		_:
			return {}

static func _table_spec() -> Dictionary:
	var parts: Array = [
		_part("part/construct0/table/top", "PLATE", "structure", [0.0, 1.5, 0.0], [3.0, 0.20, 2.0], 18.0),
	]
	var leg_positions := [
		Vector3(-1.25, 0.70, -0.75),
		Vector3(1.25, 0.70, -0.75),
		Vector3(-1.25, 0.70, 0.75),
		Vector3(1.25, 0.70, 0.75),
	]
	for index in range(4):
		var id := "part/construct0/table/leg-%d" % index
		parts.append(_part(id, "BEAM", "structure", _arr3(leg_positions[index]), [0.22, 1.40, 0.22], 4.0))
	return {
		"parts": parts,
		"bonds": _star_bonds("table", "part/construct0/table/top", parts),
		"patch_size": [3.0, 2.0],
		"mu_tangent": 0.72,
		"mu_rolling": 0.04,
		"mu_torsion": 0.035,
	}

static func _bridge_spec() -> Dictionary:
	var parts: Array = [
		_part("part/construct0/bridge/deck-center", "PLATE", "structure", [0.0, 1.05, 0.0], [2.0, 0.18, 1.5], 14.0),
		_part("part/construct0/bridge/deck-left", "PLATE", "structure", [-1.9, 1.05, 0.0], [1.8, 0.18, 1.5], 12.0),
		_part("part/construct0/bridge/deck-right", "PLATE", "structure", [1.9, 1.05, 0.0], [1.8, 0.18, 1.5], 12.0),
		_part("part/construct0/bridge/support-left", "BEAM", "support", [-2.2, 0.48, 0.0], [0.45, 0.95, 1.4], 22.0),
		_part("part/construct0/bridge/support-right", "BEAM", "support", [2.2, 0.48, 0.0], [0.45, 0.95, 1.4], 22.0),
	]
	return {
		"parts": parts,
		"bonds": _star_bonds("bridge", "part/construct0/bridge/deck-center", parts),
		"patch_size": [5.0, 1.5],
		"mu_tangent": 0.66,
		"mu_rolling": 0.035,
		"mu_torsion": 0.03,
	}

static func _cart_spec() -> Dictionary:
	var parts: Array = [
		_part("part/construct0/cart/frame", "FRAME", "structure", [0.0, 0.80, 0.0], [2.8, 0.40, 1.6], 38.0),
	]
	var wheel_positions := [
		Vector3(-1.05, 0.38, -0.72),
		Vector3(1.05, 0.38, -0.72),
		Vector3(-1.05, 0.38, 0.72),
		Vector3(1.05, 0.38, 0.72),
	]
	for index in range(4):
		var id := "part/construct0/cart/wheel-%d" % index
		parts.append(_part(id, "WHEEL", "support", _arr3(wheel_positions[index]), [0.30, 0.62, 0.62], 6.0))
	return {
		"parts": parts,
		"bonds": _star_bonds("cart", "part/construct0/cart/frame", parts),
		"patch_size": [2.7, 1.7],
		"mu_tangent": 0.78,
		"mu_rolling": 0.025,
		"mu_torsion": 0.02,
	}

static func _part(part_id: String, kind: String, role: String, position: Array, size: Array, mass_kg: float) -> Dictionary:
	return {
		"part_id": part_id,
		"item_id": "item/%s" % part_id.trim_prefix("part/"),
		"kind": kind,
		"role": role,
		"position": position.duplicate(true),
		"size": size.duplicate(true),
		"mass_kg": mass_kg,
	}

static func _star_bonds(prefix: String, root_id: String, parts: Array) -> Array:
	var bonds: Array = []
	for part_any in parts:
		var part: Dictionary = part_any
		var part_id := String(part["part_id"])
		if part_id == root_id:
			continue
		bonds.append({
			"bond_id": "bond/construct0/%s/%03d" % [prefix, bonds.size()],
			"a": root_id,
			"b": part_id,
			"strength_n": 1000000.0,
		})
	return bonds

static func _hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value, "", false).to_utf8_buffer())
	return context.finish().hex_encode()

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
