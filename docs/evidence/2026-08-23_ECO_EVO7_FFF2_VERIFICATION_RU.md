# ECO.EVO7 FFF2 — Независимая верификация воспроизводимости (R1)

**Дата:** 2026-08-23
**Вердикт:** **VERIFIED**
**Роль:** независимый верификатор (изолированная свежая роль, стадия FFF2 research)
**Проверяемая голова:** `f63f3d928bbdc8b745b49b42b113bc37ea73220c` (ветка `feature/eco-evo7-fff-r1`)
**Метод:** чистый detached-чеккаут во временном git worktree, прогон полного acceptance-раннера и детерминизм-регрессии, сверка каждого наблюдаемого значения с `docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md` (блок «Focused evidence»).

## 1. Точная голова и факт чистого чекаута

- `git rev-parse HEAD` в верификационном worktree → `f63f3d928bbdc8b745b49b42b113bc37ea73220c` — **точное совпадение** с ожидаемым SHA.
- Worktree создан командой `git worktree add … f63f3d928bbdc8b745b49b42b113bc37ea73220c --detach` (4203 файла выгружено).
- До первого запуска: `git status --short` — **0 записей** (полностью чистый чекаут); каталога `.godot` **не существовало** (правило fresh-worktree import соблюдено: импорт-префлайт выполнял сам раннер при первом прогоне).
- Побочный эффект импорта (ожидаемое поведение Godot 4.7): сгенерированы `.godot/` (включая `uid_cache.bin`) и новые untracked `.uid`-файлы. Существующие файлы не изменялись; весь worktree удалён после проверки.

## 2. Ожидаемое vs наблюдаемое

Прогон 1 (первый, с импорт-префлайтом) и прогон 2 (повторный, без префлайта) дали **побайтово идентичные** строки PASS и хеши — дополнительное подтверждение детерминизма самой цепочки FFF2.

| Проверка | Ожидаемое | Наблюдаемое (прогон 1 = прогон 2) | Совпадение |
|---|---|---|---|
| Терминальная строка | `ECO.EVO7 FFF2 Morphology Evolution candidate: PASS` | `ECO.EVO7 FFF2 Morphology Evolution candidate: PASS` | ✅ |
| FFF2 morphology evolution acceptance | PASS (56) | `PASS (56 assertions)` | ✅ |
| FFF1 functional phenotype chain | PASS (110) | `PASS (110 assertions)` | ✅ |
| FFF0 contract mapping chain | PASS (112) | `PASS (112 assertions)` | ✅ |
| P1B-S1 mutation lineage kernel | PASS (5834) | `PASS (5834 assertions)`; `ancestor_lineage_hash=73621a2c…3a230f`, `population_hash=83a114cd…778ce84`, `chain_hash=3792cf99…1a35874` | ✅ |
| PH2 environment-coupled development | PASS (107) | `PASS (107 assertions)` | ✅ |
| P1A-S1 parent environment | PASS (109), `environment_hash b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | `PASS (109 assertions)`, `environment_hash=b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | ✅ точное совпадение |
| P1A-S2 parent resource | PASS (235), `simulation_hash 618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c` | `PASS (235 assertions)`, `simulation_hash=618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c` | ✅ точное совпадение |
| P1C-S4 parent aggregate | PASS (15), `aggregate 0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112` | `PASS (15 assertions)`, `aggregate=0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112` | ✅ точное совпадение |
| PH0 development trait contract | PASS (63), `development_traits_hash 9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | `PASS (63 assertions)`, `development_traits_hash=9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | ✅ точное совпадение |
| EVO6-WATER `-SkipBaseline` | evolution PASS (24 assertions); `result_hash 7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` идентичен в evolution и visual observatory | `evolution: PASS (24 assertions)` с `result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`; visual observatory: `READY plants=72 result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` — идентичен | ✅ точное совпадение |

### Сверка с контрольной точкой

`docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md`, блок «Focused evidence»:
- все счётчики assertions (56 / 110 / 112 / 5834 / 107 / 109 / 235 / 15 / 63) совпадают с наблюдаемыми;
- усечённые хеши документа `b862c4fc…` (P1A-S1), `9d812950…` (PH0), `7010e307…` (EVO6-WATER) совпадают с префиксами полных наблюдаемых хешей;
- строка окружения документа `Godot 4.7.1.stable.double.custom_build.a13da4feb` совпадает с фактическим баннером раннера;
- расхождений не обнаружено. Статус: **VERIFIED**.

## 3. Команды

```text
git -C C:\distributed-world-simulator\worktrees\eco-water-r1 worktree add C:\distributed-world-simulator\worktrees\eco-evo7-fff2-verify f63f3d928bbdc8b745b49b42b113bc37ea73220c --detach
git -C C:\distributed-world-simulator\worktrees\eco-evo7-fff2-verify rev-parse HEAD
powershell -NoProfile -Command ".\RUN_ECO_EVO7_FFF2_TESTS.ps1"          # в корне чистого worktree
powershell -NoProfile -Command ".\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline"  # там же
git -C C:\distributed-world-simulator\worktrees\eco-water-r1 worktree remove C:\distributed-world-simulator\worktrees\eco-evo7-fff2-verify --force
```

Примечание о первом прогоне: первый запуск был обёрнут в `2>&1 | Tee-Object`, из-за чего stderr Godot (штатные parse-предупреждения о трёх ранее существовавших lab-сценах `scenes/labs/ecology/eco_evo5_*.tscn`, не входящих в тестируемую цепочку) был повышен PowerShell до error-записей, и job-обёртка вернула exit code 1 при полном PASS-выводе. Повторный запуск без такой обёртки вернул **exit code 0** при идентичных результатах. Артефакт обёртки, а не отказ тестов; зафиксировано для честности протокола.

## 4. Окружение

- Godot: `Godot Engine v4.7.1.stable.double.custom_build.a13da4feb (2026-07-13 21:00:28 UTC)` — 4.7.1 stable, double-сборка; бинарник `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`, режим headless.
- ОС: Microsoft Windows 10 Pro, 10.0.19045, build 19045; PowerShell 5.1.19041.6456.
- Исходный репозиторий: `C:\distributed-world-simulator\worktrees\eco-water-r1`, HEAD `f63f3d928bbdc8b745b49b42b113bc37ea73220c` (до и после проверки не изменялся).

## 5. Заявление о независимости

Верификация выполнена изолированной свежей ролью независимого верификатора, не участвовавшей в реализации FFF2/FFF1/FFF0 и не связанной с авторами коммита. Проверка проведена на чистом detached-чеккауте точного коммита `f63f3d928bbdc8b745b49b42b113bc37ea73220c` во временном worktree; ожидаемые значения взяты из постановки задачи и документа контрольной точки до прогона. Никаких commit/push не выполнялось, существующие файлы не изменялись; создан единственный артефакт — настоящий отчёт. Временный worktree удалён (путь отсутствует, `git worktree list` его не содержит).
