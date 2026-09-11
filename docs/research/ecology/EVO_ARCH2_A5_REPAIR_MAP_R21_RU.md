# EVO ARCH2 A5 — Repair Map R21

Дата: 2026-09-11  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## Bounded scope

Источник repair — fresh independent Codex review exact subject `71115b44a0ac059edeea944ae0c0a985a472f4b0` / tree `cd306f9536a26ed712c49dd799c39b4640832c97`, выполненный после полного canonical verifier PASS run `34470904016`.

Fresh finding: `P2 — Bind creation exemptions to verified module history`.

Repair закрывает только этот finding. Accepted A0–A4 contracts, production ecology, simulation/network authority, A6 decomposition и A3 mutation/crossover остаются вне scope.

## Почему RM-A5-33 оказался недостаточен

RM-A5-33 правильно установил, что persistent non-reproductive modules должны усиливать maintenance history. Однако conservative exemption для модулей, якобы созданных на latest development tick, определялся по `development.last_events` / `development.frame.events` с outcome `MODULE_CREATED`.

Эти event arrays являются диагностической записью accepted A2 state. `OrganismStateV1` проверяет их структуру, но не доказывает, что конкретный `MODULE_CREATED` соответствует конкретному текущему module и его фактическому creation tick. Поэтому persisted state мог:

1. добавить синтаксически корректный `MODULE_CREATED`;
2. уменьшить cumulative maintenance на стоимость старого persistent module;
3. вернуть ту же сумму в metabolic reserves;
4. пересчитать persistence hash;
5. сохранить conservation equation и пройти прежний floor.

Следовательно, event count не является authority для освобождения module от исторического maintenance.

## RM-A5-34 — funded module birth maintenance

Repair намеренно не вводит новый self-asserted creation timestamp.

Вместо этого runtime делает creation causality частью resource accounting:

1. обычный maintenance всех уже существующих modules оплачивается до growth, как и раньше;
2. A2 development выполняется как candidate transition;
3. runtime сравнивает число modules до/после candidate;
4. каждый новый non-root module требует один deterministic `birth-maintenance` payment;
5. candidate growth коммитится только если metabolic reserves способны одновременно оплатить A2 grant и весь birth-maintenance;
6. grant ledger, birth-maintenance ledger и development state коммитятся атомарно;
7. если combined budget недостаточен, candidate development отбрасывается, growth ledger не меняется и partial A2 state не публикуется;
8. reproduction выполняется только после этого решения, поэтому новый module не может участвовать в reproduction до оплаты своего birth-maintenance.

Это не ретроактивный maintenance за время до создания. Это однократный post-creation debit, который превращает факт существования каждого current non-root module в проверяемое ресурсное доказательство хотя бы одного maintenance payment.

## Persisted-state floor

`OrganismLifeStateV1.validate()` больше не использует `MODULE_CREATED` events для maintenance exemption.

Conservative floor теперь включает:

- root payments, доказанные survival/development/reproduction history;
- минимум один birth-maintenance payment для каждого текущего non-root module;
- дополнительные payments для гарантированно persistent reproductive modules на provably later paid ticks.

Таким образом forged `MODULE_CREATED` marker не может изменить floor ни на единицу.

## Executable evidence

### RM-A5-33 updated boundary

`validation/ecology/evo_arch2_a5/rm_a5_33_nonreproductive_module_maintenance_history.gd`

Проверяет:

- старый root-only refund по persistent support module отклоняется;
- conservative boundary содержит один birth payment non-root module;
- module, созданный на latest tick, не тарифицируется до создания, но сразу после успешного creation оплачивает ровно один birth-maintenance debit.

### RM-A5-34 adversarial oracle

`validation/ecology/evo_arch2_a5/rm_a5_34_verified_module_birth_maintenance.gd`

Проверяет два класса:

1. **forged creation marker** — синтаксически допустимый `MODULE_CREATED` в A2 events не уменьшает maintenance floor; conservation-preserving refund rejected в validate/serialize/deserialize;
2. **atomic rollback** — если candidate A2 growth может создать module, но после pre-growth maintenance нет бюджета на combined A2 grant + birth-maintenance, lifecycle step остаётся успешным, но development/growth ledger остаются в pre-growth состоянии без partial commit.

Rollback witness использует A4 field с нулевыми stocks, чтобы дополнительный field intake не мог случайно профинансировать проверяемый birth-maintenance.

## Source diff fence

Разрешённые изменения RM-A5-34:

- `scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd`;
- `scripts/research/ecology/v2/organism_life_state_v1.gd`;
- `validation/ecology/evo_arch2_a5/rm_a5_33_nonreproductive_module_maintenance_history.gd`;
- `validation/ecology/evo_arch2_a5/rm_a5_34_verified_module_birth_maintenance.gd`;
- `config/ecology/evo-arch2-a5-work-order.v1.json`;
- этот repair map.

Forbidden accepted A0–A4 core, production ecology, simulation и network paths не должны меняться.

## Acceptance

RM-A5-34 не является self-acceptance.

После заморозки final source HEAD/TREE требуется:

1. pinned Godot `4.7.1.stable.double.custom_build.a13da4feb`, SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`;
2. cold empty-cache import;
3. A5 core + reviewer repairs + RM11..RM34 дважды с byte-identical logs;
4. accepted A4 и A0–A3 regressions;
5. preserved VIS5 `521/521` regression;
6. final exact HEAD/TREE seal;
7. fresh independent review именно final RM-A5-34 subject с zero blocking findings.

Только после этих gates A5 research source может быть объявлен `ACCEPTED`. PR остаётся draft; merge — отдельный human gate.
