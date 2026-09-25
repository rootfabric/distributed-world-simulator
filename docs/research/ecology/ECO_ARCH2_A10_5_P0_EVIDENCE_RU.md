# ECO ARCH2 A10.5 / ECO-POLYGON-1 — Evidence P0 (stage 0)

Статус: P0 evidence. Дата: 2026-09-20 (по roadmap R2).

## База

- `git rev-parse origin/main` = `e200a61cb55930378d11c39dcc5950cf49db603c` — ok
- `git merge-base --is-ancestor e200a61... origin/main` — ok (e200a61 является ancestor of origin/main и равен его HEAD)
- Roadmap-ветка: `origin/docs/eco-arch2-a10-5-polygon-roadmap-r1`, HEAD = `a795e2409c6e48385a56db67403c16a2c578dc70` — подтверждено.
- Feature branch: `feature/eco-arch2-a10-5-polygon-r1` создан от `origin/main`; из roadmap-ветки взят только `docs/research/ecology/EVO_ARCH2_ROADMAP_R2_RU.md`.

## Godot

- Путь: `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`
- GODOT_VERSION: `4.7.1.stable.double.custom_build.a13da4feb` (ожидаемая версия совпала)
- GODOT_SHA256: `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`
- Команды проверки: `--version`, `Get-FileHash -Algorithm SHA256`.

## Итоги этапа

- Создан branch `feature/eco-arch2-a10-5-polygon-r1`.
- Созданы документы: WORK ORDER, OWNER MAP, ARCHITECTURE (P0).
- Создан skeleton-каталог `scripts/ecology/workbench/` (10 contract-файлов, без альтернативной биологии).
- HEAD/TREE зафиксированы в финальном отчёте этапа и в git-истории feature branch.
