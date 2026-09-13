# FABRIC R4 — exact qualification evidence R2

Этот каталог относится **только** к текущему product subject после bounded Repair R2:

```text
PRODUCT_HEAD = 8fe54a498a9a055b232cfe34bfc379088ec4a627
PRODUCT_TREE = 1607ed1c82ea92c11ad26800c3d559d455f26492
BASE         = b88004e77a9a424f1b23ba979f5ce8883a98f1a8
REPAIR_MAP   = 432ba0da426c554a33484cda07231ae02cfe1e30
```

R1 evidence для `989ed83c...` не переписывается и остаётся историческим. Policy R2 закреплена отдельным control commit `2e6528d2ada763699c1b9569c16a2e9586810d0d` и требует новый marker `FABRIC-HOLDOUT-R4-G2-SIGNED-EFFORT: PASS`.

## Exact G2

Повторный локальный запуск выполнен на clean tracked checkout exact source carrier текущего HEAD/TREE с бинарником:

```text
Godot = 4.7.1.stable.double.custom_build.a13da4feb
SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
exit = 0
```

Полный сохранённый stdout находится в `g2-local-exact.log`, SHA256:

```text
1ccd828c9adacf1188491a1f96e39eefadd75d840c076afd5a414793b099dbe9
```

Результаты:

```text
bond_id          17/17 PASS
transport       381/381 PASS
G2                89/89 PASS
signed effort       6/6 PASS
R3 core          187/187 PASS
R3 transient     611/611 PASS
R3 observer/process/cold replay PASS
R2 core/contract/metamorphic PASS
R1 integrity       42/42 PASS
```

Fresh self-hosted exact G2 также относится к этому же subject:

```text
run      = 34683753574 SUCCESS
artifact = 10296483648
artifact digest = sha256:d1488261fa8c882439729b3c84bf435110bd3da3be953e31559eeb3e9290dd93
```

## Fresh current-head cross gates

На `8fe54a... / 1607ed1c...`:

```text
B0.4-D Linux       34683755722 SUCCESS
Complex Labs Linux 34683755707 SUCCESS
CX-VIS0 Linux      34683755714 SUCCESS
B0.4-D Portable    34683755666 SUCCESS
Project Control    34683755651 SUCCESS
B0.6-A             34683755729 SUCCESS
B0.6-B             34683755667 SUCCESS
B0.6-C             34683755680 SUCCESS
B0.6-D             34683755750 SUCCESS
B0.6-E             34683755732 SUCCESS
```

`B0.6-CLOSE` нельзя объявлять PASS: run `34683755670` завершился FAILURE. По полному job log цепочка проходит import, A-E, BRIDGE-2, COMPLEX1B и COMPLEX2 B/C/D/E, после чего падает ровно на вложенном `COMPLEX2-PERF`:

```text
500 parts = 15,660,601 us
budget    = 12,000,000 us
```

Отдельный PERF run `34683755661`, job `103526982968`, на self-hosted runner `dws-linux-outenemy` также FAIL:

```text
500 parts = 16,096,845 us
budget    = 12,000,000 us
```

## Baseline control для PERF

Frozen base `b88004e77a9a424f1b23ba979f5ce8883a98f1a8` на том же runner и том же exact Godot также не проходит тот же неизменённый budget:

```text
run       = 34143404040
job       = 101810134743
result    = FAILURE
500 parts = 15,471,123 us
budget    = 12,000,000 us
runner    = dws-linux-outenemy
```

Поэтому evidence поддерживает **предложенную**, но не самостоятельно принятую классификацию `BASELINE_FAILURE`. Это не PERF PASS и не разрешение ослабить threshold. Reviewer и Director должны независимо решить, допустима ли эта классификация для pre-freeze перехода. Причина server slowdown как host-load не считается доказанной.

`COMPLEX2-CLOSE` run `34683755641` имеет результат `CANCELLED`; он также не переименовывается в PASS.

## Текущий verdict этого evidence

```text
QUALIFICATION_R2 = REVIEW_REQUIRED_BASELINE_PERF_CLASSIFICATION
semantic regression detected = false
PERF PASS                        = false
B0.6-CLOSE PASS                  = false
fresh exact-head review          = required
independent verifier             = required
Director verdict                 = required
production freeze                = locked
unseen holdout                   = locked
R4 accepted                      = false
SCALE-R5                         = locked
```

Этот control evidence не является независимым Reviewer/Verifier verdict и не имеет права сам принять baseline exception. G1 остаётся `FALSIFIED`; отрицательная история не переписывается. Любая новая product mutation после `8fe54a... / 1607ed1c...` делает этот R2 evidence stale и требует нового exact-head цикла.
