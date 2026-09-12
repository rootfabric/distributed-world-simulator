# EVO ARCH2 A5 — Repair Map R15

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## RM-A5-28 — Distinct post-event paid ticks retain root maintenance

Fresh review показал ещё одну causal дыру в RM25. После первого reproduction новый lower bound добавлял стоимость гарантированных reproductive modules на доказуемых post-event paid ticks, но root-level `required_paid_ticks` оставался объединён через `max(...)`. Из-за этого distinct paid tick после reproduction мог получить стоимость reproductive module, но не обязательную стоимость root на том же tick.

Минимальный counterexample:

```text
first reproduction tick = 1
age_ticks = 2
starvation_ticks = 0
development.grant_seq = 1
required_reproductive_modules = 1
large starvation_limit
```

Tick 1 обязан быть paid из-за reproduction. Tick 2 обязан быть paid, потому что текущий starvation suffix равен 0 и last paid tick = age. После tick 1 reproductive module уже доказан и A2 его не удаляет. Следовательно минимальный history cost:

```text
tick 1: root

tick 2: root + reproductive

minimum = 3 module-payments
```

Старый RM25 floor давал только 2.

## Repair

Для ненулевой reproduction history теперь отдельно считаются:

```text
required_paid_ticks
    = global root lower bound

post_reproduction_paid_ticks
    = lower bound на distinct paid ticks после first reproduction
```

Post-event bound учитывает:

- subsequent reproduction event ticks;
- survival-required paid ticks в suffix;
- development grants, которые не могли поместиться до first reproduction;
- terminal last-paid tick, если `age_ticks - starvation_ticks` находится строго после последнего reproduction tick.

После этого:

```text
guaranteed_root_payment_ticks
    = max(required_paid_ticks,
          1 + post_reproduction_paid_ticks)

guaranteed_module_payment_ticks
    = guaranteed_root_payment_ticks
      + post_reproduction_paid_ticks
        * required_reproductive_modules
```

`1 + post...` — это first reproduction paid tick плюс все доказуемо distinct post-event paid ticks. Только затем поверх каждого post-event tick добавляется стоимость persistent reproductive modules.

## Executable oracle

Добавлен:

```text
validation/ecology/evo_arch2_a5/rm_a5_28_post_event_root_maintenance.gd
```

Oracle строит реальный двухтактовый witness:

1. tick 1: maintenance paid → growth creates reproductive module → reproduction;
2. tick 2: maintenance paid, growth regulatory-suppressed, поэтому `grant_seq` остаётся 1;
3. реальный ledger содержит минимум три module payments;
4. conservation-preserving refund до старого двух-payment floor обязан отклоняться;
5. serialize/deserialize такого forge также обязаны fail closed.

## Acceptance

RM28 не является acceptance сам по себе. После freeze нового product HEAD/TREE обязательны fresh exact verifier и fresh independent review того же exact subject. Любой следующий causal/provenance/boundedness finding становится новым bounded repair.