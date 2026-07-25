extends "res://scripts/world/terrain/procedural_moon_terrain.gd"

# Stable façade for the application layer.
#
# The current implementation is a procedural terrain provider. A future
# NASA DEM or hybrid provider can replace the implementation behind this
# façade without changing players, zones, UI or simulation systems.

const TERRAIN_GENERATOR_VERSION: int = 9


func get_world_seed() -> int:
	return int(WORLD_SEED)


func get_generator_version() -> int:
	return TERRAIN_GENERATOR_VERSION
