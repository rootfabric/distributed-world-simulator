# ENGINE48 R1 Ubuntu — воспроизведение

## Среда

- Ubuntu 22.04.5 LTS, x86_64, kernel 5.15.0-190-generic, GCC 11.4.0, Python 3.10.12
- SCons 4.11.1 в venv: `~/.local/src/godot-scons-venv` (+ `zstandard`)
- Xvfb: rootless в `~/.local/opt/xvfb-root` (apt-get download + dpkg -x), display `:99`

## Сборка движка

```bash
cd ~/.local/src/godot-4.8-beta1
GODOT_VERSION_STATUS=beta1 ~/.local/src/godot-scons-venv/bin/scons \
  platform=linuxbsd target=editor arch=x86_64 precision=double -j12
# затем target=template_debug и target=template_release с теми же флагами
```

Бинарники: `~/.local/opt/godot-double-4.8-beta1/godot.linuxbsd.{editor,template_debug,template_release}.double.x86_64`
Версия: `4.8.beta1.double.custom_build.4d10419ca`

## Worktree

```bash
git -C ~/distributed-world-simulator fetch origin
git -C ~/distributed-world-simulator worktree add --detach \
  worktrees/engine48-ubuntu a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9
```

## Cold import

```bash
cd ~/distributed-world-simulator/worktrees/engine48-ubuntu
GODOT_BIN=~/.local/opt/godot-double-4.8-beta1/godot.linuxbsd.editor.double.x86_64
BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 \
  "$GODOT_BIN" --headless --path . --editor --import --quit
# exit 0; 0 SCRIPT/Parse/Compile errors; 0 ERROR
```

## Матрица headless-тестов (exact HEAD worktree)

```bash
BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 \
  "$GODOT_BIN" --headless --path . --script res://tests/network/test_v0_live2_enet_rollover.gd
# и т.д. по списку artifacts/engine48/linux/matrix/*.log
```

## M7 networked playground

```bash
cd worktrees/engine48-linux-guards   # repair branch с корректными guards
GODOT_BIN=... M7_PORT=24612 M7_CLIENT_COUNT=2 \
M7_CLIENT_NETWORK_PROFILE=BAD_MOBILE DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
  bash PLAY_M7_NETWORKED_PLAYGROUND.sh
bash STOP_M7_NETWORKED_PLAYGROUND.sh
```

Reconnect: kill клиента `--node-id=m7-client-b` и перезапуск с той же identity;
server restart: kill dedicated-server и перезапуск с тем же
`--m6-persistence-root` и `--network-session-token`.

## PERF paired

```bash
artifacts/engine48/linux/perf/perf_pair_run.sh 48-r1 "$GODOT_BIN" 24701 \
  <worktree-4.8> <outdir>; python3 analyze_perf_run.py <outdir>
# то же для 4.7.1 с worktree bench-471-mvp5 (4.7 feature marker, benchmark-only)
```

## GUI evidence (MCP host по docs/MCP_GODOT.md)

```bash
python3 artifacts/engine48/linux/gui/mcp_runtime_evidence.py \
  <worktree> "$GODOT_BIN" artifacts/engine48/linux/gui/mcp-main "" ""
```
