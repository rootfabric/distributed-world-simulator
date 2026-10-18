# FABRIC R5.6.1 R1 — FINAL WINDOWS INDEPENDENT ACCEPTANCE

Ты — Windows Acceptance Coordinator проекта `rootfabric/distributed-world-simulator`. Твоя задача — организовать **две реально отдельные fresh subagent-сессии**: независимый семантический Reviewer A и exact Verifier B. У каждого должна быть отдельная сессия, отдельный detached worktree и собственный вывод. Reviewer не должен полагаться на результаты Verifier, и наоборот. Если не можешь создать отдельные subagents, честно закрой только доступную роль и оставь вторую `PENDING`. Нельзя выдавать два вызова из одной сессии за separate-actor acceptance.

**Не изменять product code и HEAD, не делать merge, не трогать `main`.** Все негативные тесты живут только untracked в reviewer worktree или отдельной review-ветке.

## 1. Frozen identity (обязательно)

- PR: https://github.com/rootfabric/distributed-world-simulator/pull/774
- PRODUCT_HEAD: `fd83b61f87d27ba812fe058c6d3a728c4d54588e`
- PRODUCT_TREE: `000f15d373b396520042b663b59fc84c734180c9`
- BASE_R1 (оригинальный RED): `ee1fa655981bba4c7adadd3e7d1d64b3635dfae1`
- R5.5 research merge: `e74c20725a760e56cac01ffd9eaf39a5e9ad5a90`
- Target: `research/fabric-r5-2-t14-observation-refinement-r1` (НЕ `main`)
- Feature: `research/fabric-r5-6-1-canonical-delta-binding-r1`
- Windows Godot version: `4.7.1.stable.double.custom_build.a13da4feb`
- Windows Godot SHA256: `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`
- Canonical binary candidate: `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe` — проверить существование и SHA, не доверять пути без проверки.
- Host: `DESKTOP-QNAGSTI`, PowerShell 7.x, Python 3.11.x.

Текущий независимый Ubuntu exact PASS + adversarial reviewer PASS_WITH_NONBLOCKING_FINDINGS на двух чистых worktree, но организован в одной ассистентской сессии. Windows должна выполнить **действительно separate-actor acceptance**. Отчёт Ubuntu не заменяет собственную Windows проверку.

## 2. Подготовка двух fresh worktree

Открой PowerShell 7 в каталоге репозитория (не запускать параллельные cold imports в одном и том же worktree):

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'C:\distributed-world-simulator'
$Head = 'fd83b61f87d27ba812fe058c6d3a728c4d54588e'
$Tree = '000f15d373b396520042b663b59fc84c734180c9'
$Parent = 'ee1fa655981bba4c7adadd3e7d1d64b3635dfae1'
$Feature = 'research/fabric-r5-6-1-canonical-delta-binding-r1'
$GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$ReviewerWork = 'C:\distributed-world-simulator\work\r56-final-review-fd83b61f'
$VerifierWork = 'C:\distributed-world-simulator\work\r56-final-verify-fd83b61f'
$RedWork = 'C:\distributed-world-simulator\work\r56-final-red-ee1fa655'
$ReviewerEvidence = 'C:\distributed-world-simulator\evidence\r56-final-review-fd83b61f'
$VerifierEvidence = 'C:\distributed-world-simulator\evidence\r56-final-verify-fd83b61f'

git -C $Repo fetch origin --prune
$Remote = git -C $Repo ls-remote origin "refs/heads/$Feature"
if (($Remote -split '\s+')[0] -ne $Head) { throw 'REMOTE_HEAD_DRIFT' }
if ((& $GodotBin --version).Trim() -ne '4.7.1.stable.double.custom_build.a13da4feb') { throw 'GODOT_VERSION_MISMATCH' }
if ((Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant() -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }

foreach ($path in @($ReviewerWork, $VerifierWork, $RedWork, $ReviewerEvidence, $VerifierEvidence)) {
    if (Test-Path $path) { throw "PATH_ALREADY_USED: $path - choose fresh suffixed path; DO NOT REMOVE existing worktrees" }
}
git -C $Repo worktree add --detach $ReviewerWork $Head
git -C $Repo worktree add --detach $VerifierWork $Head
git -C $Repo worktree add --detach $RedWork $Parent
foreach ($p in @($ReviewerWork, $VerifierWork)) {
    if ((git -C $p rev-parse HEAD).Trim() -ne $Head) { throw 'HEAD_MISMATCH' }
    if ((git -C $p rev-parse 'HEAD^{tree}').Trim() -ne $Tree) { throw 'TREE_MISMATCH' }
    if (git -C $p status --porcelain=v1 --untracked-files=no) { throw 'TRACKED_DIRTY' }
    git -C $p diff --check $Parent HEAD
    $changed = @(git -C $p diff --name-only $Parent HEAD)
    if ($changed.Count -ne 6) { throw 'NARROW_SCOPE_DRIFT' }
}
```

## 3. Агент A — FRESH INDEPENDENT REVIEWER (СВОЯ сессия)

**Задача: семантическое adversarial review, а не повторить только зелёные тесты.** Сделай source review на HEAD:

- `scripts/research/fabric_bake0/r5_6_1_canonical_delta_session_v1.gd`
- `scripts/research/fabric_bake0/r5_6_1_canonical_delta_contract_v1.gd`
- `scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd`
- `scripts/construction/authoritative/construction_construct_store.gd`
- `tests/research/fabric_bake0/fabric_r5_6_1_r1_source_admission_acceptance.gd`

Проверь, что F1 fake/reflection-subclass Store невозможно принять вместо точного `ConstructionConstructStore`; Store instance ID фиксирован, другой объект не может заменить исходный. В F2 `_pending` после `prepare(BREAK_BOND)` подменяется валидным другим `SET_BOND_STRENGTH` с тем же event ID: нет публикации графа, есть `R56_PENDING_PROVENANCE_MISMATCH`; original prepare-intent bound to lexically captured digest/event/source/store identity, не вычисляется из изменённого pending. В обоих случаях canonical source остаётся внешним.

**Обязательно RED→GREEN без редактирования логики falsifier**:

Source branch: `review/fabric-r56-1-r1-canonical-provenance-falsifiers`.

Source file: `tests/research/fabric_bake0/review_r56_1_owner_and_proposal_falsifier.gd`.

Получи исходный скрипт командой `git show origin/review/fabric-r56-1-r1-canonical-provenance-falsifiers:tests/research/fabric_bake0/review_r56_1_owner_and_proposal_falsifier.gd`, сохрани как untracked файл в ReviewerWork и RedWork. Не коммить его в продукт. Зафиксируй SHA256 файла до и после; проверь неизменность логики. Запусти в обоих worktree:

```powershell
& $GodotBin --headless --editor --path $RedWork --import
& $GodotBin --headless --path $RedWork --script res://tests/research/fabric_bake0/review_r56_1_owner_and_proposal_falsifier.gd
# RED parent: ненулевой exit; checks=9, failures=3, duck_store_start_accepted=true, forged_pending_observed=true

& $GodotBin --headless --editor --path $ReviewerWork --import
& $GodotBin --headless --path $ReviewerWork --script res://tests/research/fabric_bake0/review_r56_1_owner_and_proposal_falsifier.gd
# GREEN repair: exit 0; checks=7, failures=[], duck_store_start_accepted=false, forged_pending_observed=false
```

**Новый независимый falsifier обязателен:** создай свой собственный сценарий, отсутствующий среди F1/F2. Варианты: реальный Store применяет *другую* операцию с тем же event ID без подмены `_pending`; изменение Matter/authority во время pending; попытка мутировать caller-owned DTO возвращённого `read_binding()`; внешнее изменение после успешного commit и stale fence; повтор после late failure. Для каждой атаки фиксируй до/после live source/context/events/hash, ожидаемую ошибку и отсутствие чужого canonical write со стороны FABRIC. В Ubuntu новый тест из 27 проверок уже закрыл несколько таких сценариев, **но Windows Reviewer должен самостоятельно придумать и выполнить ещё одну независимую вариацию**, не просто скопировать Ubuntu evidence.

Не считай блокером R1 то, что он не аутентифицирует удалённый сервер криптографически, не имеет durable owner-issued receipts или не гарантирует стойкость к произвольной замене самого Callable вредоносным привилегированным кодом. Это задокументированные границы. Но реальный обход через обычную разрешённую операцию и DTO — блокер.

Reviewer выносит один вердикт: `REVIEWER_PASS` / `PASS_WITH_NONBLOCKING_FINDINGS` / `REVIEWER_FAIL_WITH_FALSIFIER` / `REVIEW_BLOCKED`. Если FAIL, сохрани executable RED в отдельной review-ветке, **не чини product**.

## 4. Агент B — FRESH INDEPENDENT VERIFIER (отдельная сессия)

На `VerifierWork` с ранее проверенными frozen HEAD/TREE выполни **немодифицированный** штатный Windows runner:

```powershell
& (Join-Path $VerifierWork 'RUN_FABRIC_R5_6_1_TESTS.ps1') `
    -GodotBin $GodotBin `
    -ExpectedHead $Head `
    -ExpectedTree $Tree `
    -EvidenceDir $VerifierEvidence `
    -PythonBin 'python'
if ($LASTEXITCODE -ne 0) { throw 'EXACT_RUNNER_FAIL' }
```

Не меняй runner, collector, таймауты, пороги, test asserts. Не допускай параллельного Godot cold-import в этом же checkout. Дождись полного завершения; не объявляй PASS по одним числам из stdout при отсутствующем strict collector или log-файлах.

Обязательные gates:

| Гейт | Ожидается |
|---|---|
| Godot exact / SHA256 | MATCH |
| Cold import, parse × 2 | PASS |
| R5.6.1 acceptance | `3×203/0`, byte-identical raw payload |
| R1 source admission | `26/0`, F1/F2 rejected |
| BRIDGE-4 | `49/0` |
| Strict collector v2 | PASS |
| Deterministic hash | `29defdc33cb1192b9e1577517561c6fcc0f5693daa889deebe585ab8816e043b` |
| HEAD/TREE/engine SHA before/after | MATCH |
| SHA256SUMS | каждое имя/содержимое совпадает |

Дополнительно самостоятельно проверь evidence tamper negatives: неверные F1/F2 verdict, пропущенный/дублированный payload, неверный hash/count и fatal Godot output должны отклоняться collector'ом в **отдельном копированном** evidence каталоге (не менять оригинальное evidence). Cross-platform сравнение выполняй с Ubuntu hash и данными этого Work Order, но не считай его самостоятельной проверкой без запуска Windows binary.

## 5. Отдельные отчёты, handoff и критерий закрытия

Reviewer и Verifier должны независимо подготовить:

- `FABRIC_R5_6_1_R1_FRESH_WINDOWS_REVIEWER_REPORT_RU.md`;
- `FABRIC_R5_6_1_R1_FRESH_WINDOWS_VERIFIER_REPORT_RU.md`;
- `FABRIC_R5_6_1_R1_WINDOWS_FINAL_ACCEPTANCE_RU.md` — общий record только **после** двух отдельных заключений.

Для каждого: frozen HEAD/TREE, роль/сессия, exact Godot SHA, команды, raw logs, новые falsifiers, expected/actual и SHA256 manifest. Создай durable ZIP в Windows work/evidence; посчитай SHA256, добавь ссылки/локальные пути. Опубликуй два отдельных комментария с verdict в PR #774, затем итоговую сводку. PR остаётся DRAFT, никаких force push, merge или изменений main.

**Финальные вердикты:**
- `ACCEPTANCE_PASS / MERGE_READY` только если два реально отдельных Reviewer и Verifier = PASS/VERIFIED на неизменном HEAD/TREE, Windows exact + adversarial PASS, blockers=0. Даже тогда **MERGE НЕ ВЫПОЛНЯТЬ** — нужно отдельное разрешение пользователя.
- `REPAIR_REQUIRED`, если есть blocking falsifier (сохрани RED).
- `VERIFICATION_INCOMPLETE`, если отдельная роль или обязательные evidence отсутствуют.
- `HOST_BLOCKED`, если canonical binary/репозиторий не доступны.

Обязательно в ответе покажи `REVIEWER_VERDICT`, `VERIFIER_VERDICT`, `PRODUCT_HEAD`, `PRODUCT_TREE`, `GODOT_SHA256`, `ORIGINAL_RED_GREEN`, `NOVEL_FALSIFIER`, `EXACT_RESULT`, `EVIDENCE_ZIP_SHA256`, `PR_COMMENT_URL`, `MERGE_READY`, `MAIN_CHANGED=false`, `MERGE_EXECUTED=false`.

Не устраняй новые дефекты тайным переписыванием product tests или ослаблением контрактов. Цель — строгая независимая приёмка и воспроизводимые доказательства.
