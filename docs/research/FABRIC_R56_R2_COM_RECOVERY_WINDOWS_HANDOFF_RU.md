# FABRIC R5.6.1 R2 — Windows exact после COM Recovery Repair

## Миссия

Ты — **Fresh Windows Exact Verifier** для `rootfabric/distributed-world-simulator`, PR [#784](https://github.com/rootfabric/distributed-world-simulator/pull/784).

Проверь **публично опубликованный и неизменённый продуктовый** HEAD. Ранее Windows exact завершился на другом HEAD; запрещено переносить его вердикт на новый. После обычного exact повтори новый COM Recovery RED→GREEN и выполни самостоятельный adversarial сценарий, которого нет в продуктовых тестах. **Не менять продукт, main и не делать merge.**

### Identity

```text
PRODUCT_HEAD  = 60f193d6602d2d6ebb62393d3db6633b14623627
PRODUCT_TREE  = 1a92363e7cc159fef4c42e3443542ebb00a71464
RED_PARENT    = 91223acb7bf79c37e12fc11d44054ad3e2732455
RESEARCH_BASE = 4f301fae461567362d408a51802cc3dde6730999
PR            = #784
WINDOWS_GODOT = 4.7.1.stable.double.custom_build.a13da4feb
GODOT_SHA256  = 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Host: `DESKTOP-QNAGSTI`, PowerShell 7.x, Python 3.11+.

### 1. Fresh checkout

```powershell
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'research/fabric-r5-6-1-r2-dynamic-aggregates-r1'
$Head = '60f193d6602d2d6ebb62393d3db6633b14623627'
$Tree = '1a92363e7cc159fef4c42e3443542ebb00a71464'
$Parent = '91223acb7bf79c37e12fc11d44054ad3e2732455'
$GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Work = 'C:\distributed-world-simulator\work\r56-r2-com-recovery-final-60f193d'
$Evidence = 'C:\distributed-world-simulator\evidence\r56-r2-com-recovery-final-60f193d'

if (!(Test-Path $Repo)) { throw 'REAL_REPOSITORY_NOT_FOUND' }
git -C $Repo fetch origin --prune
if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
$RemoteOutput = git -C $Repo ls-remote origin "refs/heads/$Branch"
if ($LASTEXITCODE -ne 0 -or !$RemoteOutput) { throw 'REMOTE_QUERY_FAILED' }
if (($RemoteOutput -split '\s+')[0] -cne $Head) { throw 'REMOTE_HEAD_DRIFT' }
if (Test-Path $Work) { throw 'WORKTREE_ALREADY_EXISTS' }
if ((Test-Path $Evidence) -and @(Get-ChildItem $Evidence -Force).Count -gt 0) { throw 'EVIDENCE_NOT_EMPTY' }
git -C $Repo worktree add --detach $Work $Head
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_FAILED' }
if ((git -C $Work rev-parse HEAD).Trim() -cne $Head) { throw 'HEAD_MISMATCH' }
if ((git -C $Work rev-parse 'HEAD^{tree}').Trim() -cne $Tree) { throw 'TREE_MISMATCH' }
if (git -C $Work status --porcelain=v1 --untracked-files=no) { throw 'TRACKED_DIRTY' }
git -C $Work diff --check $Parent HEAD
if ($LASTEXITCODE -ne 0) { throw 'DIFF_CHECK_FAILED' }
if ((Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant() -cne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
& $GodotBin --version
```

Если путь репозитория отличается, **выясни путь настоящего клона** и убедись в exact origin. Не создай новый фиктивный репозиторий, не стирай чужие worktree.

### 2. Exact runner (не редактировать)

```powershell
Set-Location $Work
& .\RUN_FABRIC_R5_6_1_R2_TESTS.ps1 `
  -GodotBin $GodotBin `
  -ExpectedHead $Head `
  -ExpectedTree $Tree `
  -EvidenceDir $Evidence `
  -PythonBin 'python'
```

Обязательные predicates:

| Gate | Требуется |
| --- | --- |
| Cold import, 7 script parses | PASS |
| R2 acceptance | 3 × 626/0, побайтовое MATCH |
| 5k/20k/100k scale | 255/0 |
| Existing numeric | 54/0 |
| Existing COM representability | 52/0 |
| **New COM Recovery** | **18/0**; wrong matter, stale source and replay rejected; safe final COM accepted |
| R1, Narrow, BRIDGE-4 | 203/0, 26/0, 49/0 |
| Collector v4 | `fabric.r56_r2.dynamic_aggregates.exact_evidence.v4` PASS |
| Collector tamper probes | **21/21 rejected** |
| HEAD/TREE/Godot before-after | MATCH |
| Runner | `FABRIC_R56_R2_EXACT=PASS` |

R2 canonical deterministic hash:
`7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43`.

Если Godot `breakpoint_mcp` сталкивается с занятым портом 9080, архивируй ошибку как HOST/ADDON issue и повтори **тем же неизменённым** runner на новом пустом evidence-каталоге; не ослабляй fatal regex и не убивай чужой сервер. Ни одна незавершённая попытка не объявляется PASS.

### 3. RED→GREEN и независимые дополнительные проверки

Родительский COM-repair `91223acb...` имеет ошибку восстановления, даже когда исходный COM-guard правильно отказал. Новый mandatory test уже фиксирует правильный путь, но Reviewer обязан независимо повторить его.

Получить опубликованный отдельный **reviewer-owned GDScript** через GitHub:

`review/fabric-r56-r2-com-recovery-liveness-r2` → `tests/research/fabric_bake0/review_r56_r2_owner_com_recovery.gd`.

Переноси этот файл **байт-в-байт**, не через `Set-Content` с изменением encoding. Например, Python `subprocess.run(['git','-C',repo,'show',ref], stdout=open(target,'wb'), check=True)`; сравнить `git hash-object` оригинального скрипта. В отдельных fresh detached worktree на RED parent и текущем HEAD запустить идентичный Godot GDScript.

Ожидается:

- RED parent `91223acb...`: `exit 1`, 12 assertions, 1 failure, second derived rebind fails `R56_R2_RANGE_CENTER_PRECISION_UNSAFE`;
- Current HEAD `60f193d...`: `exit 0`, **18/18**, два реальных Construction Store commit, промежуточный COM query fail-closed, последующий safe COM правильный, mass ledger и replay соблюдены.

**Обязательно создайте собственный дополнительный falsifier**, не копируя этот сценарий: другой осевой компонент/отрицательные координаты, массоперенос, некорректная авторитетная revision, неполный Matter ledger, отказ во время pending и корректный последующий restart/rebind в рамках R2 scope. Проверяйте отсутствие изменения опубликованного состояния при FAIL.

### 4. Publication

Сохрани raw stdout/stderr, все payload, SHA256SUMS, `identity-before.txt`, `identity-after.txt`, RED/GREEN и собственный adversarial script, финальный отчёт и ZIP+SHA256. Опубликуй в PR #784 отчёт с:

```text
FABRIC R5.6.1 R2 COM RECOVERY — FRESH WINDOWS EXACT
PRODUCT_HEAD = 60f193d6602d2d6ebb62393d3db6633b14623627
PRODUCT_TREE = 1a92363e7cc159fef4c42e3443542ebb00a71464
GODOT_SHA256 = 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
R2_3x626 =
SCALE_255 =
NUMERIC_54 =
COM_52 =
COM_RECOVERY_18 =
R1_203 =
NARROW_26 =
BRIDGE4_49 =
COLLECTOR_V4 =
TAMPER_21 =
REVIEWER_RED_TO_GREEN =
NEW_ADVERSARIAL =
HEAD_TREE_BEFORE_AFTER =
ZIP_SHA256 =
BLOCKING_DEFECTS =
VERDICT =
MERGE_READY = false
MAIN_CHANGED = false
MERGE_EXECUTED = false
```

Только после Windows exact на **этом же неизменённом HEAD** — отдельные fresh Reviewer/Verifier verdict и явное разрешение человека на research merge. Не выполнять merge автоматически.
