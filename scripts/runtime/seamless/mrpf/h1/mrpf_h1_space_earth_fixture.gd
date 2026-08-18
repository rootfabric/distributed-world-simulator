extends RefCounted

const H0Contract = preload("res://scripts/runtime/seamless/mrpf/mrpf_h0_projection_contract.gd")

const EARTH_SUBJECT_ID := "earth"
const EARTH_GROUP_ID := "earth/full"
const EARTH_COVERAGE := "earth/full"
const EARTH_FRAME_ID := "frame/earth"
const SPACE_ROUTE_ID := "route/space"
const EARTH_ROUTE_ID := "route/earth"
const SPACE_COARSE_ID := "rep/earth/space-coarse"
const EARTH_FINE_ID := "rep/earth/earth-fine"

static func make_space_coarse(source_revision: int = 1) -> Dictionary:
	return H0Contract.create_representation(
		SPACE_COARSE_ID,
		EARTH_SUBJECT_ID,
		"domain/space",
		"authority/space/projection-source",
		"publisher/space",
		source_revision,
		"PLANETARY_LAYER",
		0,
		EARTH_COVERAGE,
		EARTH_FRAME_ID,
		"fixture/earth/coarse/r%d" % source_revision,
		0,
		EARTH_GROUP_ID,
		"SPACE"
	)

static func make_earth_fine(source_revision: int = 1) -> Dictionary:
	return H0Contract.create_representation(
		EARTH_FINE_ID,
		EARTH_SUBJECT_ID,
		"domain/earth",
		"authority/earth/projection-source",
		"publisher/earth",
		source_revision,
		"PLANETARY_LAYER",
		1,
		EARTH_COVERAGE,
		EARTH_FRAME_ID,
		"fixture/earth/fine/r%d" % source_revision,
		0,
		EARTH_GROUP_ID,
		"EARTH"
	)

static func make_for_role(role: String, source_revision: int) -> Dictionary:
	match role.strip_edges().to_lower():
		"space":
			return make_space_coarse(source_revision)
		"earth":
			return make_earth_fine(source_revision)
		_:
			return {}

static func route_id_for_role(role: String) -> String:
	return SPACE_ROUTE_ID if role.strip_edges().to_lower() == "space" else EARTH_ROUTE_ID
