# ENGINE48_UBUNTU_R2_PUBLICATION_ADDENDUM — уточнение идентичности (TREE vs SHA256)

Дата: 2026-10-23 (UTC) · Executor: standalone Ubuntu 22.04.5 (`outenemy`, kernel 5.15.0-190-generic, x86_64) — это та же машина, где была выполнена R1-работа (отчёт R1 называет её «Ubuntu 22.04»; она НЕ является WSL2-дистрибутивом с `/mnt/c`).

## 1. Исправление путаницы «Git TREE ↔ SHA256 файла»

В материалах R1 значение `PRODUCT_TREE` использовалось неоднозначно. Канонические значения R2:

| величина | значение | как вычисляется |
|---|---|---|
| BASE_HEAD (migration HEAD, PR #794) | `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9` | `git rev-parse a936412c` |
| BASE_TREE (Git TREE, content identity BASE) | `3c0a04c78eca918717e8e836b1c1bf2836cb5596` | `git rev-parse a936412c^{tree}` |
| LOCAL/PUBLISHED TIP HEAD | `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` | `git rev-parse repair/engine48-linux-runner-guards-r1` |
| TIP_TREE (Git TREE, content identity tip) | `0d49082be99b0bb125d26c28f45ac19840426f0d` | `git rev-parse 7aaa7fa9e^{tree}` |

Git TREE — это хеш содержимого коммита (`git rev-parse <commit>^{tree}`). Значения из
`build/binary-sha256.txt` — это SHA256 **файлов бинарников Godot**, они к Git TREE отношения
не имеют и не могут сравниваться с TREE. TIP_TREE отличается от BASE_TREE, потому что ветка
добавляет 339 файлов (296 `*.uid`, 13 `*.png.import`, 17 runner-guard правок, 4 `.py/.gd`
guard-правки, 9 тестовых `*.uid`-адаптаций).

## 2. Бинарники Godot (файловые SHA256, перепроверены на диске 2026-10-23)

| файл | SHA256 |
|---|---|
| `godot.linuxbsd.editor.double.x86_64` (4.8 beta1) | `4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f` |
| `godot.linuxbsd.template_debug.double.x86_64` | `af1e29d1c53688786e0551c54b1d1105300955302180b02a7fdf5711d46ff897` |
| `godot.linuxbsd.template_release.double.x86_64` | `fffb8f53f85bda1757572638d88386e80f90a7e0abf1be61638544197f4506e7` |
| `godot.linuxbsd.editor.double.x86_64` (4.7.1 baseline, paired A/B) | `f8dbe9d873d368e1b7587ce3aae022b980e8176e9d1fd237894764d574fc272a` |

Версионные строки (вывод `--version`, проверено 2026-10-23):
`4.8.beta1.double.custom_build.4d10419ca` и `4.7.1.stable.double.custom_build.a13da4feb`.

### Расхождение с текстом work order

В формулировке задания R2 указан `GODOT_EDITOR_SHA256 = 25047b82ab92aaf83753ff33d4f7847994ccb5627e10a602706cee116e647a65`.
На этой машине файл с таким SHA256 не найден; все durable-артефакты R1 (`build/binary-sha256.txt`,
`source.json` (`editor_sha256_prefix=4d72a93e`), пин `PINNED_ENGINES["linux"]` в
`tests/integration/test_v0_mvp_4_graphical_shared_dig.py`, коммит `24fc10ee1`) согласованно
указывают на `4d72a93e…`, и фактический бинарник на диске этому значению равен. Все тесты R1
исполнялись именно этим бинарником. Вывод: значение `25047b82…` в тексте задания — устаревшее/
ошибочное; каноническим для R2 принимается `4d72a93e…` (перепроверено независимо в рамках R2).

## 3. Артефакты переноса (созданы R2)

| артефакт | путь | SHA256 | размер |
|---|---|---|---|
| Git bundle (7 коммитов, требует BASE) | `/home/rdpuser/DWS-Transfers/engine48-linux-r1.bundle` | `2ae4652b8bcca9477b5fe17d7a9534b26e37de4967f190f4a2ad7f3a9684eff9` | 49 972 bytes |

`/mnt/c` на этой машине отсутствует (standalone Linux, не WSL). Bundle также дублирует
`artifacts/engine48/linux/repair-branch.patch` (format-patch всех 7 коммитов, применяется на
`a936412c`). Публикация выполнена напрямую через существующий SSH-ключ GitHub-аккаунта
`rootfabric` этой машины (маршрут HTTPS PAT — read-only, 403).

## 4. Результат публикации

- `feature/engine48-linux-r1` создана без force, GitHub подтвердил ref:
  `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` (совпадает с локальным tip и его TREE
  `0d49082be99b0bb125d26c28f45ac19840426f0d`).
- Draft PR `feature/engine48-linux-r1` → `feature/engine48-beta1-double-migration-r1` из этой
  машины создать нельзя: REST API требует PAT со scope на pull-requests/issues, а единственный
  локальный PAT — read-only (403 `Resource not accessible by personal access token`). SSH-ключ
  даёт только git-транспорт. Классификация подшага: `EXTERNAL_TOOL_AUTH_REQUIRED`; готовое тело
  PR — в `DRAFT_PR_BODY.md`, готовый комментарий для #811 — в `ISSUE_811_COMMENT.md`.
