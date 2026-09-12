# EVO ARCH2 A5 — Repair Map R2

Дата: 2026-09-06  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; production/main/network/Matter authority не изменяются.

## Предыстория

Первый A5 source `713f69f1...` реализовал inherited life-history policy, shared A4 allocation, maintenance-first survival, paid A2 growth и funded propagules. Implementer self-review затем закрыл `RM-A5-01` в `864f10b6...`: cumulative `resource_ledger.growth_transferred` обязан точно совпадать с accepted A2 `development.received`.

Fresh independent Reviewer нашёл ещё три blocking P1. Этот Repair Map закрывает их executable-контрпримерами.

## RM-A5-02 — unpaid maintenance blocks reproduction

Проблема: если maintenance не оплачен, но starvation limit ещё не достигнут, старая логика могла дойти до reproduction path. При нулевом/дешёвом propagule budget starving parent мог размножиться, нарушая порядок:

```text
maintenance → growth → reproduction
```

Исправление: reproduction gate теперь требует `maintenance_paid == true`. Неоплаченный maintenance блокирует и development, и reproduction.

Acceptance witness:

- reproductive module уже существует;
- parent остаётся alive на первом starvation tick;
- reproduction endowment и fee разрешены нулевыми;
- maintenance water не оплачен;
- результат: `0 propagules`, `reproduction_count == 0`.

## RM-A5-03 — regulatory suppression freezes prepaid A2 state

Проблема: inherited regulatory gate ранее блокировал только новый A5 growth transfer. Если в accepted A2 `development.reserves` оставался ранее оплаченный surplus, unconditional A2 advancement мог продолжить рост тела при событии `GROWTH_SUPPRESSED`.

Исправление: при `activation == 0` A5 вообще не вызывает A2 advancement. Это относится и к retained reserves, и к уже открытому development frame. Оплаченный ресурс сохраняется в A2 до будущего tick, в котором inherited gate снова разрешит рост.

Acceptance witness:

1. rich/light tick создаёт ненулевой prepaid A2 residual;
2. exact `development` hash фиксируется;
3. тот же blueprint/individual помещается в dark field;
4. dark tick проходит lifecycle, но exact `development` hash остаётся неизменным.

## RM-A5-04 — propagule endowment bound to paid inherited policy

Проблема: persisted/copied propagule мог быть изменён между emission и `materialize_propagule()`. Старый validator принимал любой корректный `BodyGraphV1.stock`, поэтому larger endowment создавал бесплатный child resource, а smaller endowment терял уже оплаченный transfer.

Исправление:

```text
propagule.endowment
==
blueprint.life_history.reproduction.endowment
```

Exact equality проверяется до materialization. Tampered stock fail-closed возвращает `PROPAGULE_ENDOWMENT`.

## Focused repair oracle

Добавлен отдельный bounded oracle:

```text
tests/research/ecology/v2/arch2_a5_reviewer_repairs.gd
```

Он проверяет именно три Reviewer counterexamples и не заменяет основной A5 exact oracle.

Implementer evidence:

```text
EVO_ARCH2_A5_REPAIRS assertions=8 failed=0
fresh process x2: byte-identical
log SHA-256: 44ac32a61a04c0778a2aa9f3a073c370df63ad091d846d0ece37010f4ea5718f
A4 exact regression: 32/32 PASS
```

Основной published A5 oracle остаётся отдельным gate (`69/69`) и включает RM-A5-01 cross-ledger tamper witness.

## Freshness

Все Reviewer/Verifier verdicts на `713f69f1...` и `864f10b6...` являются historical/stale после RM-A5-02..04. A5 можно принять только после fresh exact verifier и fresh independent review финального source HEAD.
