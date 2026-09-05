extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const RESOURCES := ["material_mg", "water_mg", "energy_mj"]
const MAX_STOCK := 1000000000000

static func stock(amount: int = 0) -> Dictionary:
	return {"material_mg": amount, "water_mg": amount, "energy_mj": amount}

static func valid_stock(value: Variant) -> bool:
	if not C.keys(value, RESOURCES):
		return false
	for name in RESOURCES:
		if not C.integer(value[name], 0, MAX_STOCK):
			return false
	return true

static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x

static func length_mm(a: Array, b: Array) -> int:
	var squared := 0
	for i in 3:
		var d: int = b[i] - a[i]
		squared += d * d
	var root := isqrt(squared)
	return root if root * root == squared else root + 1

static func cost(module: Dictionary) -> Dictionary:
	if module.id == "m000000":
		return stock()
	var length := maxi(1, length_mm(module.start_mm, module.end_mm))
	# Fixed-point pi and explicit prototype tissue density 1 mg/mm^3.
	var volume: int = (3141593 * module.radius_mm * module.radius_mm * length + 999999) / 1000000
	var collector: int = (module.area_mm2 + 49) / 50
	var material := maxi(1, volume + collector)
	return {"material_mg": material, "water_mg": (material + 1) / 2, "energy_mj": (material + 4) / 5}

static func root() -> Dictionary:
	return {"id": "m000000", "parent": "", "role": "attachment", "start_mm": [0, 0, 0], "end_mm": [0, 0, 0], "radius_mm": 0, "area_mm2": 0, "reach_mm": 0, "cost": stock()}

static func validate(modules: Variant) -> String:
	if not modules is Array or modules.is_empty() or modules.size() > 256:
		return "BODY_SIZE"
	if modules[0] != root():
		return "BODY_ROOT"
	var known := {}
	for i in modules.size():
		var m: Variant = modules[i]
		if not C.keys(m, ["id", "parent", "role", "start_mm", "end_mm", "radius_mm", "area_mm2", "reach_mm", "cost"]):
			return "MODULE_FIELDS"
		if m.id != "m%06d" % i or not m.role in P.ROLES or not m.parent is String:
			return "MODULE_ID_ROLE"
		if not C.vector(m.start_mm, 10000000) or not C.vector(m.end_mm, 10000000):
			return "MODULE_COORDINATES"
		if not C.integer(m.radius_mm, 0 if i == 0 else 1, 1000) or not C.integer(m.area_mm2, 0, 4000000) or not C.integer(m.reach_mm, 0, 10000):
			return "MODULE_DIMENSIONS"
		if (m.role != "collector" and m.area_mm2 != 0) or (not m.role in ["absorber", "attachment"] and m.reach_mm != 0):
			return "MODULE_ROLE_DIMENSIONS"
		for axis in 3:
			if abs(m.end_mm[axis] - m.start_mm[axis]) > 10000:
				return "MODULE_LENGTH"
		if i > 0 and (not known.has(m.parent) or m.start_mm != known[m.parent].end_mm):
			return "MODULE_ATTACHMENT"
		if not valid_stock(m.cost) or m.cost != cost(m):
			return "MODULE_COST"
		known[m.id] = m
	return ""

static func topology_signature(modules: Array) -> String:
	if not validate(modules).is_empty():
		return ""
	var signatures := {}
	for i in range(modules.size() - 1, -1, -1):
		var children: Array[String] = []
		for child in modules:
			if child.parent == modules[i].id:
				children.append(signatures[child.id])
		children.sort()
		signatures[modules[i].id] = modules[i].role + "(" + ",".join(children) + ")"
	return signatures["m000000"].sha256_text()
