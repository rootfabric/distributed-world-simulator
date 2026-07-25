extends RefCounted

const FACE_POS_X: int = 0
const FACE_NEG_X: int = 1
const FACE_POS_Y: int = 2
const FACE_NEG_Y: int = 3
const FACE_POS_Z: int = 4
const FACE_NEG_Z: int = 5


static func direction_to_face_uv(direction_value: Vector3) -> Vector3:
    var direction := direction_value.normalized()
    var ax: float = absf(direction.x)
    var ay: float = absf(direction.y)
    var az: float = absf(direction.z)

    if ax >= ay and ax >= az:
        if direction.x >= 0.0:
            return Vector3(float(FACE_POS_X), -direction.z / ax, direction.y / ax)
        return Vector3(float(FACE_NEG_X), direction.z / ax, direction.y / ax)

    if ay >= ax and ay >= az:
        if direction.y >= 0.0:
            return Vector3(float(FACE_POS_Y), direction.x / ay, -direction.z / ay)
        return Vector3(float(FACE_NEG_Y), direction.x / ay, direction.z / ay)

    if direction.z >= 0.0:
        return Vector3(float(FACE_POS_Z), direction.x / az, direction.y / az)
    return Vector3(float(FACE_NEG_Z), -direction.x / az, direction.y / az)


static func face_uv_to_direction(face: int, u: float, v: float) -> Vector3:
    var direction: Vector3
    match face:
        FACE_POS_X:
            direction = Vector3(1.0, v, -u)
        FACE_NEG_X:
            direction = Vector3(-1.0, v, u)
        FACE_POS_Y:
            direction = Vector3(u, 1.0, -v)
        FACE_NEG_Y:
            direction = Vector3(u, -1.0, v)
        FACE_POS_Z:
            direction = Vector3(u, v, 1.0)
        _:
            direction = Vector3(-u, v, -1.0)
    return direction.normalized()


static func direction_to_address(
    direction_value: Vector3,
    zones_per_face: int,
    chunks_per_zone: int
) -> Dictionary:
    var face_uv := direction_to_face_uv(direction_value)
    var face: int = int(face_uv.x)
    var normalized_u: float = clampf((face_uv.y + 1.0) * 0.5, 0.0, 0.999999999)
    var normalized_v: float = clampf((face_uv.z + 1.0) * 0.5, 0.0, 0.999999999)

    var zone_float_x: float = normalized_u * float(zones_per_face)
    var zone_float_y: float = normalized_v * float(zones_per_face)
    var zone_x: int = clampi(floori(zone_float_x), 0, zones_per_face - 1)
    var zone_y: int = clampi(floori(zone_float_y), 0, zones_per_face - 1)

    var zone_local_u: float = zone_float_x - float(zone_x)
    var zone_local_v: float = zone_float_y - float(zone_y)
    var chunk_x: int = clampi(
        floori(zone_local_u * float(chunks_per_zone)),
        0,
        chunks_per_zone - 1
    )
    var chunk_y: int = clampi(
        floori(zone_local_v * float(chunks_per_zone)),
        0,
        chunks_per_zone - 1
    )

    return {
        "face": face,
        "zone_x": zone_x,
        "zone_y": zone_y,
        "chunk_x": chunk_x,
        "chunk_y": chunk_y,
        "u": face_uv.y,
        "v": face_uv.z,
    }


static func zone_center_direction(
    face: int,
    zone_x: int,
    zone_y: int,
    zones_per_face: int
) -> Vector3:
    var u: float = (
        (float(zone_x) + 0.5) / float(zones_per_face) * 2.0 - 1.0
    )
    var v: float = (
        (float(zone_y) + 0.5) / float(zones_per_face) * 2.0 - 1.0
    )
    return face_uv_to_direction(face, u, v)


static func chunk_center_direction(
    face: int,
    zone_x: int,
    zone_y: int,
    chunk_x: int,
    chunk_y: int,
    zones_per_face: int,
    chunks_per_zone: int
) -> Vector3:
    var total_cells: int = zones_per_face * chunks_per_zone
    var global_x: int = zone_x * chunks_per_zone + chunk_x
    var global_y: int = zone_y * chunks_per_zone + chunk_y
    var u: float = (
        (float(global_x) + 0.5) / float(total_cells) * 2.0 - 1.0
    )
    var v: float = (
        (float(global_y) + 0.5) / float(total_cells) * 2.0 - 1.0
    )
    return face_uv_to_direction(face, u, v)


static func make_east(direction_value: Vector3) -> Vector3:
    var direction := direction_value.normalized()
    var reference := Vector3.UP
    if absf(direction.dot(reference)) > 0.94:
        reference = Vector3.RIGHT
    return reference.cross(direction).normalized()


static func make_north(direction_value: Vector3) -> Vector3:
    var direction := direction_value.normalized()
    var east := make_east(direction)
    return direction.cross(east).normalized()


static func offset_direction(
    center_direction_value: Vector3,
    east_offset_m: float,
    north_offset_m: float,
    moon_radius: float
) -> Vector3:
    var center_direction := center_direction_value.normalized()
    var east := make_east(center_direction)
    var north := center_direction.cross(east).normalized()
    return (
        center_direction
        + east * (east_offset_m / moon_radius)
        + north * (north_offset_m / moon_radius)
    ).normalized()


static func angular_distance_m(
    a_value: Vector3,
    b_value: Vector3,
    moon_radius: float
) -> float:
    var a := a_value.normalized()
    var b := b_value.normalized()
    return acos(clampf(a.dot(b), -1.0, 1.0)) * moon_radius
