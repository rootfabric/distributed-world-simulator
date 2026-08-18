# ECO VIS2.2 — Final Acceptance Repair / Ubuntu Full Validation

Дата: 2026-08-18

Ветка:

`feature/eco-vis2-2-replicated-causal-observatory`

Exact tested evidence HEAD:

`1a5309af32b9b0ed3df7a3b526ae982bdfb9b4db`

Final-repair code-under-test:

`f22cffc27e3aee9833837d42849db6ce9650232c`

Fresh-review FAIL input:

`48e4700ef64b5ba233407cba46d2c076335eb87a`

Accepted VIS2.1-V base:

`731f9d892e7747d391a79b88b24bae69769b3340`

Статус:

`FULL_UBUNTU_GATE_PASS / STRICT_SHUTDOWN_SCAN_CLEAN / NOT_SELF_ACCEPTED`

Runtime, tests, scenes и research model в этом evidence checkpoint не менялись.

## 1. Exact engine evidence

Использован приложенный архив:

`godot-4.7.1-linux-double-x86_64-a13da4f.tar(1).gz`

Archive SHA-256:

`d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92`

Встроенный `SHA256SUMS` архива: `PASS`.

Godot executable SHA-256:

`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Exact version:

`4.7.1.stable.double.custom_build.a13da4feb`

Build identity:

```text
commit=a13da4feb8d8aefc283c3763d33a2f170a18d541
platform=linuxbsd
target=editor
arch=x86_64
precision=double
```

## 2. Canonical command

```bash
bash RUN_ECO_VIS2_2_TESTS.sh /workspace/scratch/c6b146ea06e0/godot_exact/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64
```

Из-за restricted execution environment Godot user-data/cache были направлены в отдельные writable XDG-каталоги внутри `/tmp`. Код проекта, runner и тестовая последовательность не изменялись.

## 3. Full Ubuntu result

Canonical runner выполнил в одном isolated ecology project:

| Gate | Result |
|---|---:|
| Exact engine identity | PASS |
| Shutdown matcher self-coverage | PASS |
| Superseded red B/B-R1 active surface | ABSENT |
| Isolated dependency graph | PASS |
| Parser preflight | 12/12 PASS |
| Runtime chain | 12/12 PASS |
| Strict ObjectDB/RID/resource/StringName/error scan | CLEAN |
| Timeout/forced-kill enforcement | ACTIVE |
| Final runner marker | `ECO.VIS2.2 full Ubuntu acceptance gate: PASS` |

Runtime assertion results:

| Test | Assertions |
|---|---:|
| VIS2.1 Control | 82 |
| VIS2.1 Treatment | 96 |
| VIS2.1 Comparator | 82 |
| VIS1.8B | 51 |
| VIS1.9 | 29 |
| VIS2.0 | 33 |
| VIS2.1 integrated long smoke G20..G220 | 57 |
| VIS2.1-V realtime LOD | 25 |
| VIS2.2-A PairSet | 131 |
| VIS2.2-B R2 canonical aggregate | 300 |
| VIS2.2-C observatory panel | 42 |
| VIS2.2-D integrated observatory | 114 |
| **Total** | **1042** |

VIS2.2-D exact runtime covered:

- all-replicate selection immutability;
- advance beyond the 64-generation rolling window;
- common floor equality between PairSet and aggregate;
- rewind request below floor clamped exactly to `G25`;
- Treatment future truncation with preserved Control future;
- stable CRN roots;
- aggregate truncation to the effective rewind generation;
- Treatment rebranch beginning at `effective_generation + 1`;
- exactly one visible Treatment population field;
- restart and owned-node teardown.

Aggregate B R2 covered 71 points, true eviction to exactly 64 retained points, expected oldest `fork + 7`, rejection below the aggregate floor without mutation and valid truncation at the floor.

## 4. Log evidence

Runner produced 24 logs under the ignored local evidence path:

`artifacts/runtime/eco-vis2-2-full-ubuntu`

Combined deterministic digest of the sorted per-log SHA-256 list:

`f7107a4a354ac46da7baf140bcc98d7a0f5e0fe94a64e72c4bba3660edd4742e`

Independent post-run strict diagnostic scan result:

`STRICT_DIAGNOSTIC_SCAN: CLEAN`

## 5. Graphical boundary

Эта execution environment не предоставляет `DISPLAY`, `WAYLAND_DISPLAY` или Godot MCP runtime tools, поэтому `RUN_ECO_VIS2_2D_LAB_UBUNTU.sh` в этой сессии не запускался как interactive graphical observation.

Предыдущее exact-Ubuntu graphical evidence на `48e4700e...` остаётся действительным для one-visible-Treatment world и replicated observatory presentation. Новые rewind/clamp/rebranch semantics доказаны exact-engine integrated D runtime test на `1a5309a...`.

Fresh independent Reviewer должен отдельно решить, достаточно ли этой композиции evidence для hard invariant 19 или требуется новый interactive graphical rewind observation.

## 6. Control verdict

Final acceptance repair и полный canonical Ubuntu automated gate подтверждены на exact remote HEAD.

Этот документ не выполняет self-acceptance и не закрывает VIS2.2 сам по себе. Формальное закрытие требует fresh independent exact-head verdict согласно VIS2.2 plan и project review policy.
