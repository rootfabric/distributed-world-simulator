# FABRIC R4.1 — Numeric Envelope + Diagnostic Integrity Repair

## Boundary

```text
PREDECESSOR = e6228a39b6b3006a3d14ad0884c09266570fcd00
PREDECESSOR_TREE = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
HISTORICAL_HOLDOUT_R4 = ACCEPTED / PRESERVED
NEW_SUBJECT = repair/fabric-r4-1-numeric-envelope-diagnostics-r1
```

Это новый product subject. Он не переписывает исторический R4 acceptance и не наследует его Reviewer/Verifier freshness.

## Defect A — numeric fail-open

На exact predecessor воспроизводятся конечные входы, после которых generalized resistive graph возвращает `success=true` с `inf/nan` в derived токах/мощности. Repair обязан:

- отклонять non-finite conductance / assembly / current / balance / power / residual / condition estimate;
- использовать алгебраически эквивалентный `delta_v * current` для Joule power, чтобы не создавать лишнее intermediate overflow там, где итог конечен;
- сохранить nominal и большой, но representable finite случай;
- не расширять физическую capability за declared model.

## Defect B — diagnostic masking

`COMPLEX2-CLOSE` не должен после первичного `Perf.run_matrix()` failure падать вторичной ошибкой отсутствующего `matrix_hash`.

Repair:

- matrix-level PERF failure имеет `matrix_hash=""` и сохраняет original nested error;
- CLOSE читает hash fail-safe через `.get()`;
- при primary failure печатаются `COMPLEX2_PERF_PRIMARY_FAILURE_CODE` и `...DETAILS`;
- successful matrix hash, budgets и closure hash не изменяются.

## Acceptance

Required exact subject gates:

```text
R4.1 focused numeric/diagnostic       PASS
old G2 bond-id                        PASS
old G2 transport                      PASS
old G2 target                         PASS
old G2 signed-effort                  PASS
COMPLEX2-PERF                         62/62 PASS
COMPLEX2PERF_MATRIX_HASH              698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607
COMPLEX2-CLOSE                        PASS
COMPLEX2_CLOSE_HASH                   f429d2743dab5f31fed87901186b03868039b13c2e087a86f3473f84e5b60855
B0.6-CLOSE                            PASS
B06_CLOSURE_HASH                      892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584
threshold relaxation                  FORBIDDEN
historical R4 mutation                FORBIDDEN
```

После exact CI нужен fresh Reviewer/Verifier на новом HEAD. Только затем можно freeze этого subject и preregister R4.2.

## R4.2 entry contract

R4.2 не повторяет old fixed-family holdout. До future-beacon reveal должны быть заморожены grammar/generator/runner/oracles для:

1. electrical topology family selection (chain / branch / bridge / cyclic, variable 4–12 nodes, 2–4 ports within declared solver limit);
2. supported mechanical topology variation (variable nodes/mobile DOF/anchors/coupler, permutation/reversal/metamorphic checks);
3. nearly-singular / numeric-envelope / unreducible negative controls;
4. at least one coupled dynamic trajectory case using existing generalized runtime;
5. at least one lifecycle case that exercises physical proposal → canonical mutation boundary → local refinement/rebake/continuation without fixture-selected outcome.

R4.2 expected values must come from independent analytic/rational or independently implemented numerical oracles; agreement of two paths through the same production assembler is insufficient.
