# ECO EVO3 E3.7 — IMPLEMENTATION CANDIDATE

Статус: `RESEARCH_ONLY / IMPLEMENTED_CANDIDATE / NOT_ACCEPTED`.

## Основание

- canonical ECO base: `c9f0b0becb3d2494097d946202788b9d1aa292f4`;
- E3.6: `ACCEPTED`;
- E3.7: `AUTHORIZED_NOT_STARTED` на входе;
- Work Order: `ECO-E3-7-R1-WO-001`, risk `HIGH`;
- implementation branch: `feature/eco-evo3-e3-7-deterministic-planet-compilation`;
- first executable implementation commit: `54b3c349183cdcae0309fdd344f5ffecf3f007a8`.

## Реализовано

E3.7 собирает единый `PlanetEcologyProgram` только из exact accepted E3.1-E3.6 chain и полного persisted EVO2 SpeciesCatalog. Build/serialization authority требует exact raw Git/SHA identities и verified capability; serialization независимо пересобирает программу из сохранённых raw bytes и требует canonical-byte equality.

`PlanetEcologyProgram` остаётся `RESEARCH_DERIVED_NON_AUTHORITATIVE` и не получает canonical G/ENV/MAT/WQ/SD/TF, species taxonomy, individual entity, persistence, transaction, network, XFER1 или production authority.

## Детерминизм

Запрещены global RNG, local clock и ambient process environment. Closure обязан подтвердить два fresh-process build с одинаковыми bytes и program hash.

## Текущий gate

Committed generated `PlanetEcologyProgram` ещё не заморожен: первый CI предназначен для получения exact machine output. До byte-binding generated artifact, полного Closure PASS, post-build critique, Evidence Map, fresh independent Reviewer PASS и independent Verifier PASS E3.7 не принят.

E3.8 остаётся `BLOCKED`. XFER1 остаётся blocked. Production ECO authority остаётся inactive.
