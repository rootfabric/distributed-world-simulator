# ECO.EVO1 / P2.8 — Deterministic Save/Restart Plant World Proof — STAGE-PROVEN CANDIDATE

Статус: `REPAIRED_CANDIDATE / RESEARCH_ONLY / EXACT WINDOWS STAGE PROOF PASS / FULL CANONICAL RUNNER PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Parent: `ECO.EVO1/P2.7 ACCEPTED`, aggregate `7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

P2.8 остаётся последним gate EVO1. Этот checkpoint **не является acceptance record**: полный `RUN_ECO_EVO1_P2_8_TESTS.ps1` после repair ещё обязан пройти целиком.

## Что доказывает P2.8

Plant-world research truth должна пережить process boundary и продолжить ту же причинную историю, что и непрерывный запуск:

```text
UNINTERRUPTED
  year 0 ------------------------------> 30

SAVE/RESTART
  year 0 ----> 14
              SAVE A / RESTORE
              ----> 18
                   SAVE B / RESTORE
                   ---------------------> 30
```

Persisted truth включает absolute year, patch geometry/environment, adult и seed-bank cohorts, genomes/recruitment traits, transport/disturbance schedules, regional history, transition/migration/disturbance logs, cumulative conservation accounting, occupancy maps и P2.7 diagnostic evidence.

Это research-only proof: production persistence ownership, network authority, canonical Time/Spatial ownership и species taxonomy не заявляются.

## Два найденных codec defect и repair

### P2_8_CODEC_001_JSON_NUMBER_VARIANT_ERASURE

Первый exact-Windows run показал, что JSON round-trip стирал `TYPE_INT` identity. Repair сохраняет integer как typed wrapper.

### P2_8_CODEC_002_JSON_DOUBLE_PRECISION_ERASURE

После первого repair выяснилось, что JSON number path также не гарантирует exact IEEE-754 double round-trip. Repair commit:

`1e74792c53bbcaa5807097630321dd7abc0ba88c` — `fix(eco): preserve exact floating variants in P2.8 checkpoints`.

`TYPE_FLOAT`, `Vector2` и `Rect2` теперь проходят как:

```text
Variant -> var_to_bytes -> base64 -> JSON -> base64 -> bytes_to_var -> exact Variant
```

Strengthened preflight commit:

`6f60f6eacfe58f60740318cd9f91262f83f508f5`.

Ни один accepted P2.7-or-earlier ecology source и ни один runtime path этим repair не изменён.

## Exact Windows stage proof — PASS

Canonical environment:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
checkout source head c8ba594e683c34340b66dddeee98080e57f49849
```

Codec gate:

```text
ECO.EVO1-P2.8 Codec Preflight: PASS (25 assertions)
value_hash=d39b60931c5c3a69102897af57e28555de6cdd9bf00cd035d06540afd5a4da44
bytes=1174
```

Stage probe proved:

```text
P2.7 parent      = 7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
baseline result  = 06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
final state      = 50ca2aca3acd98d54eaff88cc709db12094a8b2cec33a97762680526d55e2345
diagnostics      = b76b0afda1b4fdf298313934d4cb5bd06764a3959f8c599bc163eb2953495c79
initial world    = 069e64ff8a7ab44477164e1dd8e6b8746547fc70e3e3743e7f2479e916c921f7
```

Uninterrupted stateful execution exactly matched P2.6-equivalent baseline:

```text
06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
==
06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
```

Cut A:

```text
year=14
world_hash=e907052c74c3996a6c2eb9864b3e03940de355ea649a55dfb32baa201b7c8c65
serialized_bytes=84465
checkpoint_hash=827a13fa52c80569d37bbabe744cd8c41e6e192c5ab64ff4d88779ad4ccfa7fd
deserialize=PASS
```

Cut B:

```text
year=18
world_hash=75e968b042e1e8271b22f051061ec7d32ae4bf6f90e172e0036a26b49bbb0f19
checkpoint_hash=bd177a95662a7e80c11881163178c555d7704b5035abcac6fa85a1e577359915
deserialize=PASS
```

После двух restore финальный result hash снова точно совпал с baseline:

```text
resumed=06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
baseline=06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
```

Итог stage probe:

```text
ECO.EVO1-P2.8 Failure Stage Probe: PASS
```

Таким образом exact-Windows уже доказал:

- P2.7 parent identity;
- fixture validity;
- P2.6 baseline validity;
- stateful world creation;
- uninterrupted P2.6 result equivalence;
- SAVE/deserialize at year 14;
- continuation to year 18;
- second SAVE/deserialize;
- continuation to year 30;
- final resumed result equality.

## Оставшийся final acceptance gate

Stage proof не заменяет полный runner. Остаются объединённые acceptance assertions, disk checkpoint write/read, tamper rejection, fresh-process A/B и полный accepted parent regression в одном exact-Windows execution.

Запуск:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_8_TESTS.ps1 -GodotPath $Godot
```

Fail-fast order:

```text
acceptance parser/preload
failure-stage parser/preload
25-assertion checkpoint codec preflight
fail-closed execution stage probe
full accepted P2.7 parent regression
P2.8 acceptance + disk checkpoint write/read
fresh-process A restore
fresh-process B restore
aggregate/result equality gates
```

До полного PASS:

```text
P2.8 = STAGE_PROVEN_CANDIDATE
P2.8 != ACCEPTED
EVO1 != COMPLETE
EVO2 / XFER0 post-EVO1 route = NOT YET OPENED
```

После полного exact-Windows runner PASS этот candidate checkpoint должен быть заменён durable ACCEPTED checkpoint с canonical aggregate/evidence, а EVO1 может быть закрыт.
