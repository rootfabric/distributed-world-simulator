# FABRIC R5.6.1 R2 — FINAL WINDOWS COM NUMERIC EXACT / INDEPENDENT REVIEW

**Фиксированная работа:** проверить новый R2 COM representability repair на реальной Windows-машине DESKTOP-QNAGSTI, затем провести две раздельные свежие agent-сессии Reviewer/Verifier. Исходный численный дефект и прежний Windows runner уже исправлены; не заменять unmodified exact локальной копией. Не менять main, продукт и не выполнять merge.

## Frozen identity

- Repo: `rootfabric/distributed-world-simulator`
- PR: https://github.com/rootfabric/distributed-world-simulator/pull/784
- Feature branch: `research/fabric-r5-6-1-r2-dynamic-aggregates-r1`
- **HEAD:** `91223acb7bf79c37e12fc11d44054ad3e2732455`
- **TREE:** `3bb5f214a563ce2bb66b548555cf5f049e6fe932`
- COM RED parent: `1b2e707c3605c502280efe157ed112816f85c6df`
- Research base: `4f301fae461567362d408a51802cc3dde6730999`
- Canonical Windows Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Windows executable SHA256: `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`

## PowerShell 7: чистый detached worktree + точный runner

```powershell
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'research/fabric-r5-6-1-r2-dynamic-aggregates-r1'
$Head = '91223acb7bf79c37e12fc11d44054ad3e2732455'
$Tree = '3bb5f214a563ce2bb66b548555cf5f049e6fe932'
$GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Work = 'C:\distributed-world-simulator\work\r56-r2-com-win-91223acb'
$Evidence = 'C:\distributed-world-simulator\evidence\r56-r2-com-win-91223acb'

git -C $Repo fetch origin --prune
if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
$remote = git -C $Repo ls-remote origin "refs/heads/$Branch"
if ($LASTEXITCODE -ne 0 -or !(($remote -split '\s+')[0] -eq $Head)) { throw 'REMOTE_DRIFT' }
if (Test-Path $Work) { throw 'WORKTREE_ALREADY_EXISTS' }
git -C $Repo worktree add --detach $Work $Head
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_FAILED' }
if ((git -C $Work rev-parse HEAD).Trim() -ne $Head) { throw 'HEAD_MISMATCH' }
if ((git -C $Work rev-parse 'HEAD^{tree}').Trim() -ne $Tree) { throw 'TREE_MISMATCH' }
$sha = (Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
if ((& $GodotBin --version).Trim() -ne '4.7.1.stable.double.custom_build.a13da4feb') { throw 'GODOT_VERSION_MISMATCH' }
if (Test-Path $Evidence) { if (@(Get-ChildItem $Evidence -Force).Count -gt 0) { throw 'EVIDENCE_DIR_NOT_EMPTY' } }

Set-Location $Work
& .\RUN_FABRIC_R5_6_1_R2_TESTS.ps1 -GodotBin $GodotBin -ExpectedHead $Head -ExpectedTree $Tree -EvidenceDir $Evidence -PythonBin 'python'
# R2 runner throws on failures; also require final PASS marker and inspect all raw logs.
```

Строгое ожидание:

- import PASS; 6 parse gates PASS (включая новый `parse-com`)
- R2 acceptance **3×626/0**, raw payload byte-MATCH
- 5k/20k/100k scale **255/0**
- прежний Numeric Conditioning **54/0**
- **новый COM Precision 52/0**: `unsafe_centers_rejected=6`, `safe_centers=2`, multi-axis 2, state unchanged true, `center_budget_m=1e-6`
- inherited R1 203/0, R1 Narrow 26/0, BRIDGE-4 49/0
- collector schema `fabric.r56_r2.dynamic_aggregates.exact_evidence.v3` PASS
- corrupt evidence **16/16 REJECT**
- R2 deterministic hash `7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43` MATCH
- HEAD/TREE/Godot SHA before/after MATCH, tracked tree clean
- SHA256SUMS заново проверен, сырые логи приложены и архив ZIP создан с полным SHA256.

## Отдельный RED→GREEN adversarial

Скрипт независимого Reviewer на GitHub:

`review/fabric-r56-r2-com-representation-precision-r1:tests/research/fabric_bake0/review_r56_r2_com_precision_falsifier.gd`

В отдельном detached worktree на RED parent (`1b2e707c...`) скопировать **бинарно-побайтово** скрипт через `git cat-file` или корректную запись UTF-8 без модификаций. Старое поведение: RED exit 1, 20 checks / 4 нарушенных предложенных COM accuracy-утверждения. На R2 новым HEAD: ожидается GREEN 20/0, шесть? Исходный Reviewer скрипт содержит 5 источников; четыре больших offset должны быть отвергнуты, offset 1e9 может быть принят с ошибкой меньше 1e-6. Подтвердить исключение `R56_R2_RANGE_CENTER_PRECISION_UNSAFE`, а не false Iyy.

**Reviewer A (отдельная свежая сессия):** новое independent adversarial за пределами имеющихся 8 тестов (mass asymmetry, negative coordinate, near 1µm budget, multiple source offsets, aggregate retry). Проверить что `1e-6 m` относится только к conversion error абсолютного COM; не обещать total physics precision. Определить SOUND/CONCERN/DEFECT/BLOCKER; при дефекте опубликовать executable RED.

**Verifier B (отдельная свежая сессия):** fresh exact + raw checksum + результат новых входов Windows/Linux, numerical fail-closed и опубликованный HEAD без дрейфа. Reviewer и Verifier обязаны быть **разными агентскими сессиями в разных worktree**, не одним и тем же исполнителем с двумя логами.

Вывести `REVIEWER=PASS` и `VERIFIER=VERIFIED` на точно одном HEAD только при доказанных результатах. Даже если оба PASS, **не выполнять merge без отдельного human gate**. Публиковать отчёты, RED→GREEN, evidence ZIP checksum и итоговый статус в PR #784.

## Инфраструктура

Self-hosted Windows workflow проверки запущен на verification-only ветке `verify/fabric-r56-r2-com-91223acb-exact-r1`, GitHub Actions run `39523271734`. Если job Windows в `queued`, сначала проверить, что существующий DESKTOP-QNAGSTI runner **уже зарегистрирован** и listener запущен с существующими credentials; не создавать новый runner, не менять labels, не выполнять destructive re-registration. Не допускать параллельного cold import в одну `.godot` директорию.
