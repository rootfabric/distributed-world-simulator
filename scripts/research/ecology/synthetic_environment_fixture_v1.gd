extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const FIXTURE_ID := "eco-fixture/p1a-s1-river-valley"
const ENVIRONMENT_REVISION := "ECO.P1A-S1.1"
const DEFAULT_SEED := 104701
const SIZE_M := 4000.0
const HALF_SIZE_M := SIZE_M * 0.5
const LOGICAL_GRID_SIZE := 128
const LOGICAL_CELL_SIZE_M := SIZE_M / float(LOGICAL_GRID_SIZE)
const CONTROL_POINTS := {
	"river_bank": Vector2(-900.0, -70.0),
	"floodplain": Vector2(-500.0, 120.0),
	"wet_lowland": Vector2(250.0, 260.0),
	"lower_slope": Vector2(850.0, 500.0),
	"sunny_slope": Vector2(1150.0, -650.0),
	"shaded_slope": Vector2(-1150.0, 700.0),
	"plateau": Vector2(1450.0, 1150.0),
	"dry_ridge": Vector2(1750.0, -1500.0),
}


static func sample_at(
	world_x_m: float,
	world_z_m: float,
	seed: int = DEFAULT_SEED,
	environment_revision: String = ENVIRONMENT_REVISION
) -> Dictionary:
	var x := clampf(world_x_m, -HALF_SIZE_M, HALF_SIZE_M)
	var z := clampf(world_z_m, -HALF_SIZE_M, HALF_SIZE_M)
	var phase := float(posmod(seed, 100000)) * 0.000071
	var river_center_z := 180.0 * sin(x / 620.0 + phase) + 55.0 * sin(x / 190.0 - phase * 0.5)
	var river_distance := absf(z - river_center_z)
	var river_influence := exp(-pow(river_distance / 260.0, 2.0))
	var flood_influence := exp(-pow(river_distance / 135.0, 2.0))

	var nx := x / HALF_SIZE_M
	var nz := z / HALF_SIZE_M
	var lowland := exp(-pow((x - 120.0) / 820.0, 2.0) - pow((z - 260.0) / 680.0, 2.0))
	var plateau := exp(-pow((x - 1350.0) / 720.0, 2.0) - pow((z - 1050.0) / 760.0, 2.0))
	var dry_ridge := exp(-pow((x - 1700.0) / 520.0, 2.0) - pow((z + 1450.0) / 520.0, 2.0))
	var broad_relief := 0.28 * sin(x / 880.0 + phase) + 0.18 * cos(z / 760.0 - phase)
	var elevation_proxy := clampf(0.42 + 0.24 * plateau + 0.22 * dry_ridge + broad_relief * 0.18 - 0.26 * lowland, 0.0, 1.0)

	var moisture_wave := 0.035 * sin(x / 430.0 + z / 570.0 + phase)
	var soil_moisture := clampf(
		0.28 + 0.54 * river_influence + 0.24 * lowland - 0.19 * plateau - 0.22 * dry_ridge + moisture_wave,
		0.0,
		1.0
	)

	var slope_orientation := sin(x / 950.0 + 0.35) - cos(z / 1050.0 - 0.2)
	var sunlight := clampf(
		0.62 + 0.15 * slope_orientation - 0.09 * lowland + 0.04 * cos((x - z) / 530.0 + phase),
		0.08,
		0.98
	)

	var nutrients := clampf(
		0.36 + 0.28 * river_influence + 0.20 * lowland + 0.12 * flood_influence - 0.16 * dry_ridge - 0.08 * plateau,
		0.05,
		0.95
	)

	var flood_frequency := clampf(
		0.015 + 0.78 * flood_influence * (0.70 + 0.30 * lowland) + 0.08 * lowland,
		0.0,
		0.98
	)

	var latitude_proxy := nz
	var temperature_c := 18.5 - 8.0 * elevation_proxy - 3.0 * latitude_proxy + 1.1 * sin(nx * 1.7 + phase)

	return EnvironmentSample.create(
		x,
		z,
		temperature_c,
		soil_moisture,
		sunlight,
		nutrients,
		flood_frequency,
		seed,
		environment_revision
	)


static func control_point(name: String, seed: int = DEFAULT_SEED) -> Dictionary:
	if not CONTROL_POINTS.has(name):
		return {}
	var position: Vector2 = CONTROL_POINTS[name]
	return sample_at(position.x, position.y, seed)


static func grid_position(ix: int, iz: int, grid_size: int = LOGICAL_GRID_SIZE) -> Vector2:
	assert(grid_size >= 2)
	assert(ix >= 0 and ix < grid_size)
	assert(iz >= 0 and iz < grid_size)
	var denominator := float(grid_size - 1)
	return Vector2(
		-HALF_SIZE_M + SIZE_M * float(ix) / denominator,
		-HALF_SIZE_M + SIZE_M * float(iz) / denominator
	)


static func environment_hash(grid_size: int = LOGICAL_GRID_SIZE, seed: int = DEFAULT_SEED) -> String:
	assert(grid_size >= 2)
	var checksums := PackedStringArray()
	checksums.resize(grid_size * grid_size)
	var offset := 0
	for iz in range(grid_size):
		for ix in range(grid_size):
			var position := grid_position(ix, iz, grid_size)
			var sample := sample_at(position.x, position.y, seed)
			checksums[offset] = String(sample["checksum"])
			offset += 1
	return (FIXTURE_ID + "|" + ENVIRONMENT_REVISION + "|" + str(seed) + "|" + "\n".join(checksums)).sha256_text()


static func logical_cell_boundary_x(boundary_index: int) -> float:
	assert(boundary_index > 0 and boundary_index < LOGICAL_GRID_SIZE)
	return -HALF_SIZE_M + LOGICAL_CELL_SIZE_M * float(boundary_index)


static func logical_cell_boundary_z(boundary_index: int) -> float:
	assert(boundary_index > 0 and boundary_index < LOGICAL_GRID_SIZE)
	return -HALF_SIZE_M + LOGICAL_CELL_SIZE_M * float(boundary_index)
