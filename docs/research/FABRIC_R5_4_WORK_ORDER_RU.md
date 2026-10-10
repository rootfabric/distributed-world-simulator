# FABRIC R5.4 — R3 bounded repair Work Order

Base: merged R5.3 `044eab40803acf51ffc8bc8ff59ae7e8727947de`.
Branch: `research/fabric-r5-4-mixed-complexity-100k-machine-r1`.
Repair parent: `5a5be1b3e5eeb3f9a46a0585e09486ac80a4491c`.
R2 blocking review: PR #743, comment 6016469344.
Risk: MEDIUM research runtime; immutable predecessor contracts, no production authority change.

## Repair Map

Owner — только R5.4 mixed-machine orchestration. Callers — acceptance и exact Linux/Windows runners. Callees — неизменённые R5.1 source/index/lifecycle и R5.3 compiler/runtime. Ошибка лежит в causal orchestration и evidence contract, не в physical kernel.

R2 неверно приравнивал полный aggregate неизменённой structural source к machine-wide physical causality. Частичный repair изменил runtime, но оставил старые acceptance/collector/docs. Второй дефект — отсутствие общего fail-closed порядка structural/recursive transition.

## Разрешённый scope

Только девять уже добавленных R5.4 файлов. Repair меняет шесть из них: orchestrator, acceptance, collector, collector tests, research note и этот Work Order. Runners и source workflow сохраняются; T1–T16, R5.1, R5.3, main и merge-target refs не меняются.

## Обязательные результаты

1. Сохранить R5.1 canonical structural 100k source/range-index/lifecycle и R5.3 compiler/runtime побайтно.
2. Сохранить local residual FULL=20, reconstruction=20, aggregate scans=0, queries/reads=4/80 и recursive changed/reused=4/11.
3. Разделить reviewer-разрешённые операции: recursive-global revision=15/0 при полном неизменённом structural state; отдельный explicit O(N) non-causal control=100000 без изменения physical state/identity. Не заявлять structural-global physical causality.
4. Завершать structural transition на scratch lifecycle до recursive refresh. При отказе на любой проверяемой границе обе live representations и их counters/identities неизменны. После успешного refresh — только установка полностью готового состояния.
5. Исполняемые отрицательные tests: отказы после restore/UNBAKE/break observation/ReBAKE, invalid index admission, late local/global recursive prepare, cold entrypoints, replay/order violations и успешный retry.
6. Сохранить compact root=24 compile components / 4 executable equations / zero hidden source traversal при 320 steady calls.
7. Новый result v2 и strict collector: 1048 checks, 11/11 full-state rollback, 3 cold rejections; реальные unit falsifiers на входе collector, не сравнение двух чисел в обход validator.
8. Fresh 3× canonical Linux exact, R5.3 1231/0 и R5.1-100k 93/0, затем exact Windows на том же HEAD/TREE и полный payload comparison.
9. Durable implementation/evidence handoff → fresh adversarial Reviewer → independent Verifier. Не self-accept и не merge в рамках этого repair.

## Границы утверждений

Zero local residual scans не означает end-to-end O(1): canonical fixture generation вычисляет expanded source digests за O(N). Ни metadata control, ни изменение одного counter не являются физическим causal event. Nonlinear/hybrid generalization, production/network/persistence integration и новые R5 stages вне scope.

Merge / promotion — отдельное решение после независимых gates. При unavailable host или независимой роли публикуется фактический gap, а не неподтверждённый PASS.
