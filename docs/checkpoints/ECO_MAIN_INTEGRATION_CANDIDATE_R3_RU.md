# ECO MAIN Integration R3 — fresh candidate / WAITING_HUMAN

Дата: 2026-08-11  
Project Epoch: `E2026-08-11-ECO-MAIN-R3`  
Work Order: `ECO-MAIN-INTEGRATION-WO-003`

## Почему понадобился R3

R2 был корректно остановлен fail-closed: до human merge target ECO сдвинулся с `67e23224ae153a9fc43ca5feea21c50165a99f1d` на `2a4c3103234717f813cd6fe8f60de0d50f3012ba`. Поэтому R2 и Draft PR #68 сохранены как историческое evidence, но не могут авторизовать merge нового target.

R2 теперь terminal `EPOCH_INVALIDATED` / `REFRESH_REQUIRED`.

## Fresh R3 pins

```text
main                 5ba1dcb7b7671bff519739387513a50d90e8feac
ECO source           2a4c3103234717f813cd6fe8f60de0d50f3012ba
ECO passport blob    ee47c97bfbda186c4efe4704281020741d31d3ac
ECO source tree      b78d75da0f23308f74961f4951e7087c2d514f65
pre-merge head       f257d4398a2c36699735f7ebe6be3909d5906418
merge candidate      64592d414fc1d2cdd904b6954d8fa32e3aa6064c
candidate tree       33509ee7d4164107c0d735f0ce9b894db985a194
Draft PR             #70
```

## Source-tree proof

Точный current ECO tree был восстановлен из сохранённого R2 tree плюс полного `67e23224 → 2a4c3103` delta. Получен tree:

```text
b78d75da0f23308f74961f4951e7087c2d514f65
```

Одноразовый verification object с этим tree поверх exact ECO source дал zero-file compare. Следовательно source-tree pin не является предположением.

## HIGH pre-build review

Exact reviewed head:

```text
47f465f61b681199a1374a07a8365fd0b1b316d5
```

Verdict: `PASS`.

После review создан final pre-merge control head:

```text
f257d4398a2c36699735f7ebe6be3909d5906418
```

Перед merge construction повторно подтверждены exact `main` и exact ECO target.

## Candidate topology

Candidate:

```text
64592d414fc1d2cdd904b6954d8fa32e3aa6064c
```

Parents:

```text
1: f257d4398a2c36699735f7ebe6be3909d5906418
2: 5ba1dcb7b7671bff519739387513a50d90e8feac
```

Candidate tree равен immediate first-parent tree:

```text
33509ee7d4164107c0d735f0ce9b894db985a194
```

То есть меняется ancestry, но не ECO content.

`main` является exact merge-base/ancestor candidate. Diff `first-parent → candidate` пустой. Diff `ECO source → candidate` содержит только шесть append-only R3 control records.

Не изменены:

- runtime;
- ecology research truth;
- ECO passport;
- main-owned registry;
- global architecture;
- ownership contracts.

## Synthetic PC0

Canonical PC0 auditors являются pure Git/JSON checks. В текущем execution sandbox сетевой Git clone недоступен, поэтому `CONTROL_PROJECT.ps1` здесь не объявляется запущенным.

Вместо ложного shell evidence выполнен exact-ref semantic replay canonical predicates через GitHub control surface:

- exact main pin fresh;
- exact ECO pin fresh;
- candidate merge-base с main = exact `5ba1dcb7...`;
- ECO critical main dependency drift после подстановки candidate отсутствует;
- полный новый P1B delta проверен против current watched/critical-watched paths G/T/TS/CH/DOCTRINE/NX;
- новых directional watched hits = `0`;
- новых directional critical hits = `0`.

Result:

```text
standard PC0:    NON_RED
 directional PC0: NON_RED
```

R2 baseline на том же exact main ранее был `YELLOW/NON_RED` standard и `YELLOW` directional с zero RED; R3 не переиспользует stale ECO verdict, а заново доказывает новый ECO ancestry и новый P1B directional delta.

## Independent review / verification

```text
HIGH pre-build Reviewer       PASS
Independent Verifier          PASS
Post-build critique           NO_MATERIAL_REFACTOR_REQUIRED
Independent post-build Review PASS
Evidence Map                  PASS
```

## Draft PR

Открыт Draft PR #70:

```text
control/eco-main-integration-r3
        ↓
feature/eco-evolutionary-ecology
```

Base при открытии:

```text
2a4c3103234717f813cd6fe8f60de0d50f3012ba
```

Merge не выполнялся.

## Текущее состояние

```text
R2                      EPOCH_INVALIDATED
PR #68                  HISTORICAL / DO_NOT_MERGE
R3 candidate            VERIFIED
synthetic PC0            NON_RED
Draft PR #70             OPEN / DRAFT / UNMERGED
Human Attention          OPEN
runtime C22/NX           FORBIDDEN
state                    WAITING_HUMAN
```

## Единственный следующий разрешённый шаг

Требуется явное human решение:

```text
CONTROL_DOCS_ONLY_MERGE
```

Перед фактическим merge обязательно ещё раз проверить exact:

```text
main SHA
ECO target SHA
ECO passport blob
ECO source tree
```

Если любой pin сдвинулся — R3 немедленно `EPOCH_INVALIDATED`, merge запрещён и требуется fresh epoch.

Если approval дан и pins fresh:

1. merge Draft PR #70 в ECO;
2. выполнить live PC0 уже на фактическом ECO target;
3. требовать aggregate `NON_RED` и directional без RED;
4. закрыть ECO Human Attention;
5. только затем возвращаться к H0.0 epoch audit / phase-independent harness tests.

До `H0_0_SCAFFOLD_READY` runtime-разработка C22/NX остаётся запрещённой.
