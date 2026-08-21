# ECO EVO3 E3.8 — ACCEPTED

Статус: `RESEARCH_ONLY`.

## Точная идентификация

- E3.8 PR: `#188`.
- Director authorization: PR #187 comment `#5371006859` на базе `0abae91237ec05cf974a793fae7097ea40ac35ca`.
- reviewed/verified/accepted HEAD: `7a6bb752d17c4fb3a8db992d492a88eaa2315c11`.
- canonical E3.8 merge: `847ea24b7e010e6db2d8221ed7c2706083edc6c4` (= точный кандидат в точную принятую базу).
- fresh independent Reviewer PASS: PR #188 comment `#5371446287`.
- fresh independent Verifier PASS: PR #188 comment `#5371650661`.
- Formal Acceptance decision (Director gate): PR #188 comment `#5371658138`.
- exact-head E3.8 Closure: `32492640806 / #2 — SUCCESS`, job `96803640072`, artifact `9450353810`, ZIP SHA-256 `cb494c6269cbd73891d74fdcba48b9004a6d3a688c0dba139dbfabd408d37db7`; tests `26/26`; predicates `18/18`.
- exact-head Project Control: `32492640816 / #1127 — SUCCESS`, job `96803640136`, artifact `9450352383`, ZIP SHA-256 `6fec87eec644656dfa53fe9e6f7016fba4c661f52542b0cae57163e1050622d1`.

## Принятая идентичность матрицы обобщения

```text
path                 validation/ecology/eco-evo3-e3-8-cross-planet-generalization-matrix.generated.json
bytes                9348
SHA-256              44de8474647483a6b18b6e5d88202358857f3b2b09171ae302b1c8497ea5b79c
Git blob             28edbe05d89daa219105fcddff20d5edaf6dd57f
provenance hash      3ede4a18fb0fa8b8895813452fe6ae4f62e633f6d7ea9188ab49ec18f6fd76be
matrix hash          707ee5bc4235ef2fcef917b8fcc825455440f7d1fa6511f5802a9a480479404e
```

Predeclared матрица 6 семейств (dry/wet/cold/hot/seasonal/isolated) зафиксирована контрактом до результатов. Ретюнинг исключён: использованы неимпортированно-неизменённые билдеры принятых E3.2/E3.3 и примитивы E3.4 core с принятыми порогами; каталог дословный; дайджесты модулей записаны в артефакт.

Результаты: dry — оба вида LOST_REVERSAL → NO_COLONIZATION (null-исход сохранён); wet/cold/hot — PRESERVED_COLONIZED (cold/hot идентичны baseline — thermal context не является fitness); seasonal — один LOST_REVERSAL; isolated — species-level PRESERVED с сжатием дисперсии 22 → 2 занятых патчей.

Authority: `RESEARCH_DERIVED_NON_AUTHORITATIVE`; `canonical_binding_resolved=false`; `production_binding_authorized=false`. Индивидуальные сущности, canonical species/time/environment ownership, history writes, forecast, network/persistence/transaction authority, asset scatter truth, XFER1 — запрещены.

## Project Control interpretation

```text
global       RED
ECO          RED
directional  RED
NX -> ECO    YELLOW / WATCH_HIT
ECO critical directional intersections = 0
critical RED intersections = NX -> V0, V0 -> NX
```

RED не переинтерпретирован.

## Frontier

`ECO.EVO3/E3.8 = ACCEPTED`.

`ECO.EVO3/E3.FINAL = BLOCKED` — требуется отдельная Director-авторизация на основании resulting accepted ECO control state (precommitted unseen planet fields).

XFER1 остаётся `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`. Production ECO authority остаётся inactive. Production binding остаётся forbidden.
