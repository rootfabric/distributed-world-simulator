extends RefCounted
## ECO ARCH2 A12 canonical bounded scale contract.
## This is a capacity contract, not a culling policy. Reaching a bound fails
## closed; no organism, corpse or history may be silently discarded.
const SCHEMA := "dws.ecology.scale-contract.v1"
const REVISION := 1

# A11 closed at 128/128. A12 R1 advances one bounded, testable step.
const MAX_POPULATION := 256
const MAX_CORPSES := 256
const MAX_PROPAGULES_PER_STEP := 1024
const MAX_OUTBOX := 1024

# Evidence targets, not runtime semantics.
const ACCEPTANCE_TARGET_GENERATION := 3
const ACCEPTANCE_HORIZON_TICKS := 512

static func descriptor() -> Dictionary:
	return {
		"schema": SCHEMA,
		"revision": REVISION,
		"max_population": MAX_POPULATION,
		"max_corpses": MAX_CORPSES,
		"max_propagules_per_step": MAX_PROPAGULES_PER_STEP,
		"max_outbox": MAX_OUTBOX,
	}

static func validate_descriptor(value: Variant) -> String:
	if not value is Dictionary:
		return "SCALE_CONTRACT_TYPE"
	return "" if value == descriptor() else "SCALE_CONTRACT_MISMATCH"
