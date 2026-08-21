# ECO P4.7 — Production Integration Soak — ACCEPTED

Статус: `ACCEPTED_EXACT_WINDOWS_ISOLATED_HEADLESS_BOUNDED_ROTATING_A_B`.

Exact tested commit:

```text
cb5f6c69bfb0299770e09d3acff41a8fbf8aa61c
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Accepted committed surfaces:

```text
soak test blob = 49821079787479212feb78a10a4703bc52ba89b3
runner blob    = 2bd6e1da8951238ff36b61e9ca5813a125e0dcd4
```

Canonical isolated headless A/B both passed with `242 assertions`, fresh-process logs were byte-identical, and strict unexpected-Godot-ERROR policy remained enabled.

Frozen identities:

```text
soak_hash           = d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe
final_interest_hash = 62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e
```

Exact accepted counts:

```text
regions                    = 8
cycles                     = 12
ecology_generation_steps   = 8
handoffs                   = 4
save_loads                 = 12
client_updates             = 12
interest_projections       = 14
restarts                   = 3
max_remaining_due_steps    = 0
```

The test uses a temporary minimal Godot project with NTFS junctions to the exact committed `scripts/` and `tests/` trees. This isolates ecology acceptance from unrelated gameplay/Breakpoint MCP project autoloads while preserving exact committed code. No ERROR allowlist was introduced.

P4.7 remains an **accelerated deterministic bounded integration soak**, not a wall-clock production-duration soak, scheduler, network transport, or runtime-authority implementation.

Legacy output note: the script prints `parent_p4_6=c966...`; the value is actually `ReadModel.PARENT_P4_5_AGGREGATE` and therefore denotes the accepted P4.5 aggregate, not a P4.6 aggregate identity.

P4.7 acceptance opens the P4.8 final manifest gate. P4 itself is not accepted until that final manifest passes and the final P4 lifecycle checkpoint is written.
