extends SceneTree

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const Kernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")

const EXPECTED_ANCESTOR_LINEAGE_HASH := "73621a2c49d6496bb89faef63a8350f2a76b553fd718fa88d1bc6b21b83a230f"
const EXPECTED_POPULATION_HASH := "83a114cd712aacac42e0a1b4d74c0876a441fadb019f6640bfd44c921778ce84"
const EXPECTED_CHAIN_HASH := "3792cf995265b622ab8817a973f0bd38aedab8ca34721ca9468178e6e1a35874"
const ANCESTOR_LINEAGE_SEED := 4701001
const MUTATION_SEED := 4702001

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var genome := PlantGenome.create_default()
	var lineage := Kernel.create_ancestor(genome, ANCESTOR_LINEAGE_SEED)
	_check(bool(LineageRecord.validate(lineage).get("success", false)), "fresh-process ancestor validates")
	_check(String(lineage.get("checksum", "")) == EXPECTED_ANCESTOR_LINEAGE_HASH, "fresh-process ancestor hash exact")

	var population: Array = []
	for offspring_index in range(256):
		population.append(Kernel.reproduce(genome, lineage, MUTATION_SEED, offspring_index))
	var population_hash := Kernel.population_hash(population)
	_check(population_hash == EXPECTED_POPULATION_HASH, "fresh-process sibling population hash exact")

	var current_genome := genome
	var current_lineage := lineage
	var chain: Array = []
	for generation_index in range(160):
		var result := Kernel.reproduce(current_genome, current_lineage, MUTATION_SEED + generation_index * 17, generation_index % 11)
		chain.append(result)
		current_genome = result["genome"]
		current_lineage = result["lineage"]
	var chain_hash := Kernel.population_hash(chain)
	_check(chain_hash == EXPECTED_CHAIN_HASH, "fresh-process multigeneration chain hash exact")
	_check(int(current_lineage.get("generation", 0)) == 160, "fresh-process chain reaches generation 160")
	_check(bool(PlantGenome.validate(current_genome).get("success", false)), "fresh-process final genotype validates")

	if failures.is_empty():
		print("ECO.P1B-S1 Restart Replay: PASS (%d assertions) ancestor=%s population=%s chain=%s" % [assertions, EXPECTED_ANCESTOR_LINEAGE_HASH, population_hash, chain_hash])
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1B-S1 Restart Replay FAIL: %s" % failure)
	print("ECO.P1B-S1 Restart Replay: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
