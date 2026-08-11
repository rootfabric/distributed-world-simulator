extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_morphology_resource_probes_v1.gd")

const EXPECTED_REFERENCE_HASH := "58161227616f083ab29426931ce91e24f6354f5b3d96d9020af6f8b60b72a43e"
const EXPECTED_SHADE_HIGH_HASH := "d437d45d4beea747df717703afb1e536e5712df837677956f16c24953e5c2759"
const EXPECTED_DRY_WIDE_HASH := "ef7a8f84bd1a6bf27ad87d0e8d2933627b755d200cae7722f31d6c83d54e4466"

func _init() -> void:
	var suite := Probes.run_suite()
	var checks := 0
	assert(String(suite["REFERENCE/BASE"]["coupling"]["coupling_hash"]) == EXPECTED_REFERENCE_HASH); checks += 1
	assert(String(suite["SHADE/HEIGHT_HIGH"]["coupling"]["coupling_hash"]) == EXPECTED_SHADE_HIGH_HASH); checks += 1
	assert(String(suite["DRY/CROWN_WIDE"]["coupling"]["coupling_hash"]) == EXPECTED_DRY_WIDE_HASH); checks += 1
	assert(String(suite["REFERENCE/BASE"]["coupling"]["coupling_hash"]) != String(suite["SHADE/HEIGHT_HIGH"]["coupling"]["coupling_hash"])); checks += 1
	assert(String(suite["REFERENCE/BASE"]["coupling"]["coupling_hash"]) != String(suite["DRY/CROWN_WIDE"]["coupling"]["coupling_hash"])); checks += 1
	print("ECO.PH3 Restart Replay: PASS (%d assertions) reference=%s shade_high=%s dry_wide=%s" % [checks, EXPECTED_REFERENCE_HASH, EXPECTED_SHADE_HIGH_HASH, EXPECTED_DRY_WIDE_HASH])
	quit(0)
