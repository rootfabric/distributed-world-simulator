extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")

const EXPECTED_REFERENCE_HASH := "da2345004422b3fe6e53eff32f5c2e9e6417e164abdff7a27471ac989fdedf10"
const EXPECTED_SHADE_HASH := "bf939daf1cd04e0b06f48e23feae9714326827a8e86d2125a03484f1892537f0"
const EXPECTED_SUN_HASH := "b195338cc51b717893a6e23e9e7e962cef0e9b7b0f764054c1dc90962998fdaa"

func _init() -> void:
	var results := Probes.run_all()
	var checks := 0
	assert(String(results["REFERENCE"]["phenotype_hash"]) == EXPECTED_REFERENCE_HASH); checks += 1
	assert(String(results["SHADE"]["phenotype_hash"]) == EXPECTED_SHADE_HASH); checks += 1
	assert(String(results["SUN"]["phenotype_hash"]) == EXPECTED_SUN_HASH); checks += 1
	assert(String(results["REFERENCE"]["genome_checksum"]) == String(results["SHADE"]["genome_checksum"])); checks += 1
	assert(String(results["REFERENCE"]["inherited_traits_checksum"]) == String(results["SUN"]["inherited_traits_checksum"])); checks += 1
	print("ECO.PH2 Restart Replay: PASS (%d assertions) reference=%s" % [checks, EXPECTED_REFERENCE_HASH])
	quit(0)
