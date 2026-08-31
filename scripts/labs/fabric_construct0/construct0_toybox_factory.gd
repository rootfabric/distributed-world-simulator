class_name FabricConstruct0ToyboxFactory
extends RefCounted

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Contract = preload("res://scripts/labs/fabric_construct0/construct0_toybox_contract.gd")

static func build(experiment_id: String) -> Dictionary:
	var spec := _spec(experiment_id)
	if spec.is_empty():
		return _failure("TOYBOX_UNKNOWN_EXPERIMENT")
	var aggregate = AggregateScript.new()
	var checked: Dictionary = aggregate.setup(
		"construct/construct0/toybox/%s" % experiment_id.to_lower(),
		"item/construct0/toybox/%s/root" % experiment_id.to_lower()
	)
	if not bool(checked.get("success", false)):
		return checked

	var part_specs: Array = spec["parts"]
	for index in range(part_specs.size()):
		var p: Dictionary = part_specs[index]
		var metadata := {
			"geometry": {"bounding_box_m": Array(p["size"]).duplicate(true)},
			"local_rotation_quaternion": Array(p.get("rotation", [0.0, 0.0, 0.0, 1.0])).duplicate(true),
			"condition": "INTACT",
			"construct0_toybox": true,
			"structural": {
				"capacity_n": float(p.get("capacity_n", 1000000.0)),
			},
		}
		var part := PartScript.create(
			String(p["part_id"]),
			String(p["item_id"]),
			String(p["kind"]),
			String(p["role"]),
			float(p["mass_kg"]),
			Array(p["position"]).duplicate(true),
			metadata
		)
		checked = aggregate.add_part(
			"toybox/%s/add-part-%03d" % [experiment_id.to_lower(), index],
			aggregate.state_revision,
			part
		)
		if not bool(checked.get("success", false)):
			return checked

	var relation_specs: Array = spec["relations"]
	for index in range(relation_specs.size()):
		var relation: Dictionary = relation_specs[index]
		var strength_n := float(relation.get("strength_n", 1000000.0))
		var bond := BondScript.create(
			String(relation["bond_id"]),
			String(relation["part_a_id"]),
			String(relation["part_b_id"]),
			String(relation["kind"]),
			strength_n,
			"INTACT",
			Contract.relation_metadata(
				String(relation["kind"]),
				Dictionary(relation.get("parameters", {}))
			)
		)
		checked = aggregate.add_bond(
			"toybox/%s/add-bond-%03d" % [experiment_id.to_lower(), index],
			aggregate.state_revision,
			bond
		)
		if not bool(checked.get("success", false)):
			return checked

	var snapshot := aggregate.export_snapshot()
	checked = SnapshotScript.validate(snapshot)
	if not bool(checked.get("success", false)):
		return checked

	var result := {
		"success": true,
		"experiment_id": experiment_id,
		"runtime_kind": String(spec["runtime_kind"]),
		"snapshot": snapshot,
		"relations": relation_specs.duplicate(true),
		"environment": Dictionary(spec["environment"]).duplicate(true),
		"controls": Dictionary(spec["controls"]).duplicate(true),
		"runtime_params": Dictionary(spec["runtime_params"]).duplicate(true),
		"view": Dictionary(spec["view"]).duplicate(true),
	}
	var valid := Contract.validate_experiment(result)
	if not bool(valid.get("success", false)):
		return valid
	return result

static func _spec(experiment_id: String) -> Dictionary:
	match experiment_id:
		"INCLINED_PLANE":
			return _inclined_plane()
		"SEESAW":
			return _seesaw()
		"CART":
			return _cart()
		"CATAPULT":
			return _catapult()
		"BREAKABLE_BRIDGE":
			return _breakable_bridge()
		_:
			return {}

static func _inclined_plane() -> Dictionary:
	var block := _part("inclined/block", "BLOCK", "payload", [0.0, 1.10, 0.0], [0.72, 0.72, 0.72], 10.0)
	var anchor := _part("inclined/anchor", "ANCHOR", "support", [0.0, 0.10, 0.0], [0.35, 0.20, 0.35], 1000.0)
	return {
		"parts": [block, anchor],
		"relations": [
			_relation("inclined/slider", anchor["part_id"], block["part_id"], "SLIDER", 1000000.0, {
				"axis": [1.0, 0.0, 0.0],
				"coordinate": "distance_m",
			}),
		],
		"environment": Contract.environment("RAMP", {
			"angle_deg": 20.0,
			"mu_tangent": 0.40,
			"gravity_m_s2": 9.81,
		}),
		"controls": {
			"FORCE": true,
			"IMPULSE": true,
			"TORQUE": false,
			"ADD_LOAD": false,
			"BREAK_BOND": false,
		},
		"runtime_kind": "SLIDER_FRICTION",
		"runtime_params": {
			"moving_part_id": block["part_id"],
			"slider_bond_id": "bond/construct0/toybox/inclined/slider",
			"mass_kg": 10.0,
			"initial_position_m": 0.0,
			"initial_velocity_m_s": 0.0,
			"force_n": 0.0,
		},
		"view": {"camera_target": [0.0, 0.8, 0.0]},
	}

static func _seesaw() -> Dictionary:
	var support := _part("seesaw/support", "ANCHOR", "support", [0.0, 0.45, 0.0], [0.45, 0.90, 0.45], 1000.0)
	var beam := _part("seesaw/beam", "BEAM", "structure", [0.0, 1.10, 0.0], [5.0, 0.22, 0.35], 22.0)
	var left := _part("seesaw/left-weight", "WEIGHT", "payload", [-1.75, 1.45, 0.0], [0.55, 0.55, 0.55], 14.0)
	var right := _part("seesaw/right-weight", "WEIGHT", "payload", [1.55, 1.45, 0.0], [0.65, 0.65, 0.65], 24.0)
	return {
		"parts": [support, beam, left, right],
		"relations": [
			_relation("seesaw/hinge", support["part_id"], beam["part_id"], "HINGE", 1000000.0, {
				"axis": [0.0, 0.0, 1.0],
				"pivot": [0.0, 1.10, 0.0],
				"angle_limits_rad": [-0.65, 0.65],
			}),
			_relation("seesaw/left-rigid", beam["part_id"], left["part_id"], "RIGID"),
			_relation("seesaw/right-rigid", beam["part_id"], right["part_id"], "RIGID"),
		],
		"environment": Contract.environment("FLOOR", {"gravity_m_s2": 9.81}),
		"controls": {
			"FORCE": false,
			"IMPULSE": false,
			"TORQUE": true,
			"ADD_LOAD": false,
			"BREAK_BOND": false,
		},
		"runtime_kind": "HINGE_OSCILLATOR",
		"runtime_params": {
			"moving_part_id": beam["part_id"],
			"dependent_part_ids": [left["part_id"], right["part_id"]],
			"hinge_bond_id": "bond/construct0/toybox/seesaw/hinge",
			"inertia_kg_m2": 32.0,
			"initial_angle_rad": 0.0,
			"initial_omega_rad_s": 0.0,
			"constant_torque_nm": -55.0,
			"damping_nm_s": 8.0,
			"spring_nm_rad": 0.0,
			"rest_angle_rad": 0.0,
			"min_angle_rad": -0.65,
			"max_angle_rad": 0.65,
			"pivot": [0.0, 1.10, 0.0],
			"axis": [0.0, 0.0, 1.0],
		},
		"view": {"camera_target": [0.0, 1.0, 0.0]},
	}

static func _cart() -> Dictionary:
	var frame := _part("cart/frame", "PLATE", "structure", [0.0, 0.80, 0.0], [2.8, 0.35, 1.55], 32.0)
	var payload := _part("cart/payload", "WEIGHT", "payload", [0.0, 1.35, 0.0], [0.85, 0.75, 0.85], 18.0)
	var parts: Array = [frame, payload]
	var relations: Array = [
		_relation("cart/payload-rigid", frame["part_id"], payload["part_id"], "RIGID"),
	]
	var wheel_positions := [
		Vector3(-1.05, 0.42, -0.72),
		Vector3(1.05, 0.42, -0.72),
		Vector3(-1.05, 0.42, 0.72),
		Vector3(1.05, 0.42, 0.72),
	]
	var wheel_ids: Array = []
	for index in range(4):
		var wheel := _part("cart/wheel-%d" % index, "WHEEL", "support", _arr3(wheel_positions[index]), [0.30, 0.62, 0.62], 4.0)
		parts.append(wheel)
		wheel_ids.append(wheel["part_id"])
		relations.append(_relation("cart/axle-%d" % index, frame["part_id"], wheel["part_id"], "AXLE", 1000000.0, {
			"axis": [0.0, 0.0, 1.0],
			"radius_m": 0.31,
		}))
	return {
		"parts": parts,
		"relations": relations,
		"environment": Contract.environment("FLOOR", {
			"gravity_m_s2": 9.81,
			"rolling_resistance": 0.035,
		}),
		"controls": {
			"FORCE": true,
			"IMPULSE": true,
			"TORQUE": false,
			"ADD_LOAD": true,
			"BREAK_BOND": false,
		},
		"runtime_kind": "ROLLING_CART",
		"runtime_params": {
			"moving_part_id": frame["part_id"],
			"dependent_part_ids": [payload["part_id"]],
			"wheel_part_ids": wheel_ids,
			"mass_kg": 66.0,
			"wheel_radius_m": 0.31,
			"rolling_resistance": 0.035,
			"force_n": 120.0,
			"initial_position_m": 0.0,
			"initial_velocity_m_s": 0.0,
		},
		"view": {"camera_target": [0.0, 0.8, 0.0]},
	}

static func _catapult() -> Dictionary:
	var base := _part("catapult/base", "ANCHOR", "support", [0.0, 0.30, 0.0], [2.2, 0.35, 1.3], 1000.0)
	var arm := _part("catapult/arm", "BEAM", "structure", [0.65, 1.00, 0.0], [2.8, 0.18, 0.28], 12.0)
	var payload := _part("catapult/payload", "WEIGHT", "payload", [1.85, 1.25, 0.0], [0.42, 0.42, 0.42], 3.0)
	return {
		"parts": [base, arm, payload],
		"relations": [
			_relation("catapult/hinge", base["part_id"], arm["part_id"], "HINGE", 1000000.0, {
				"axis": [0.0, 0.0, 1.0],
				"pivot": [-0.55, 0.90, 0.0],
			}),
			_relation("catapult/spring", base["part_id"], arm["part_id"], "SPRING_DAMPER", 1000000.0, {
				"stiffness_nm_rad": 125.0,
				"damping_nm_s": 2.5,
				"rest_angle_rad": 0.78,
			}),
			_relation("catapult/payload-latch", arm["part_id"], payload["part_id"], "BREAKABLE", 250.0, {
				"release_coordinate_rad": 0.48,
			}),
		],
		"environment": Contract.environment("FLOOR", {"gravity_m_s2": 9.81}),
		"controls": {
			"FORCE": false,
			"IMPULSE": false,
			"TORQUE": true,
			"ADD_LOAD": false,
			"BREAK_BOND": true,
		},
		"runtime_kind": "HINGE_SPRING_RELEASE",
		"runtime_params": {
			"moving_part_id": arm["part_id"],
			"payload_part_id": payload["part_id"],
			"hinge_bond_id": "bond/construct0/toybox/catapult/hinge",
			"spring_bond_id": "bond/construct0/toybox/catapult/spring",
			"latch_bond_id": "bond/construct0/toybox/catapult/payload-latch",
			"inertia_kg_m2": 9.0,
			"initial_angle_rad": -0.42,
			"initial_omega_rad_s": 0.0,
			"spring_nm_rad": 125.0,
			"damping_nm_s": 2.5,
			"rest_angle_rad": 0.78,
			"release_angle_rad": 0.48,
			"arm_length_m": 2.35,
			"gravity_m_s2": 9.81,
			"pivot": [-0.55, 0.90, 0.0],
			"axis": [0.0, 0.0, 1.0],
		},
		"view": {"camera_target": [0.6, 1.2, 0.0]},
	}

static func _breakable_bridge() -> Dictionary:
	var left_support := _part("bridge/support-left", "ANCHOR", "support", [-3.0, 0.45, 0.0], [0.55, 0.90, 1.4], 1000.0)
	var right_support := _part("bridge/support-right", "ANCHOR", "support", [3.0, 0.45, 0.0], [0.55, 0.90, 1.4], 1000.0)
	var deck0 := _part("bridge/deck-0", "BEAM", "structure", [-2.0, 1.05, 0.0], [1.8, 0.22, 1.2], 20.0, 6000.0)
	var deck1 := _part("bridge/deck-1", "BEAM", "structure", [0.0, 1.05, 0.0], [1.8, 0.22, 1.2], 20.0, 6000.0)
	var deck2 := _part("bridge/deck-2", "BEAM", "structure", [2.0, 1.05, 0.0], [1.8, 0.22, 1.2], 20.0, 6000.0)
	var load := _part("bridge/load", "WEIGHT", "payload", [0.0, 1.55, 0.0], [0.75, 0.75, 0.75], 25.0, 4000.0)
	return {
		"parts": [left_support, right_support, deck0, deck1, deck2, load],
		"relations": [
			_relation("bridge/left", left_support["part_id"], deck0["part_id"], "BREAKABLE", 1100.0),
			_relation("bridge/01", deck0["part_id"], deck1["part_id"], "BREAKABLE", 900.0),
			_relation("bridge/12", deck1["part_id"], deck2["part_id"], "BREAKABLE", 900.0),
			_relation("bridge/right", deck2["part_id"], right_support["part_id"], "BREAKABLE", 1100.0),
			_relation("bridge/load-rigid", deck1["part_id"], load["part_id"], "RIGID", 1000000.0),
		],
		"environment": Contract.environment("FLOOR", {"gravity_m_s2": 9.81}),
		"controls": {
			"FORCE": false,
			"IMPULSE": false,
			"TORQUE": false,
			"ADD_LOAD": true,
			"BREAK_BOND": true,
		},
		"runtime_kind": "STRUCTURAL_LOAD",
		"runtime_params": {
			"support_part_ids": [left_support["part_id"], right_support["part_id"]],
			"load_part_id": load["part_id"],
			"load_step_n": 250.0,
			"initial_external_load_n": 0.0,
			"safety_factor": 1.0,
			"degraded_capacity_factor": 0.5,
		},
		"view": {"camera_target": [0.0, 1.0, 0.0]},
	}

static func _part(
	suffix: String,
	kind: String,
	role: String,
	position: Array,
	size: Array,
	mass_kg: float,
	capacity_n: float = 1000000.0
) -> Dictionary:
	return {
		"part_id": "part/construct0/toybox/%s" % suffix,
		"item_id": "item/construct0/toybox/%s" % suffix,
		"kind": kind,
		"role": role,
		"position": position.duplicate(true),
		"size": size.duplicate(true),
		"mass_kg": mass_kg,
		"capacity_n": capacity_n,
	}

static func _relation(
	suffix: String,
	part_a_id: String,
	part_b_id: String,
	kind: String,
	strength_n: float = 1000000.0,
	parameters: Dictionary = {}
) -> Dictionary:
	return {
		"bond_id": "bond/construct0/toybox/%s" % suffix,
		"part_a_id": part_a_id,
		"part_b_id": part_b_id,
		"kind": kind,
		"strength_n": strength_n,
		"parameters": parameters.duplicate(true),
	}

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
