# V0-P2 — R7 P1 Base Replay Repair Map

Дата: 2026-08-16

Risk: HIGH

PR: #109

Предыдущий P2 head:

`10471c3c97231006fcf23671c7b4de5d635fdebb`

Предыдущий P2 merge-base / frozen P1:

`bf24bb7cbea6fcf3aa48e341ce634f7be4146bef`

Текущий independently-reviewed + exact-Windows-tested P1 head:

`f7ab0a8b91394724b66e3f4ee387de3441a676ca`

## Причина replay

Независимый review P2 обнаружил lower-layer P1 canonical-clock defect: старый P1 мог оставлять ordinary INVENTORY state без `location.slot_index`, а затем лениво нормализовать canonical representation из rejection-capable path. R7 исправил этот класс и hotbar-displacement escape в P1.

P2 хранит замороженную копию прежнего P1 adapter в:

`scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p1.gd`

Поэтому простое продолжение P2 с `10471c3...` повторно вносило бы отвергнутую P1 семантику.

## Repair Map

### R2-BASE — stale P1 provenance

Root cause:

P2 был построен от `bf24bb7...`, тогда как current P1 уже `f7ab0a8b...`.

Correction:

Сделать merge-resolution replay существующей P2 ветки на exact P1 `f7ab0a8b...`, без force-push. Итоговый P2 commit должен иметь P2 history и repaired P1 history в ancestry.

Regression:

`git merge-base` итогового P2 и P1 должен быть `f7ab0a8b...`; full inherited `RUN_V0_P1_TESTS.ps1` обязан проходить внутри P2 gate.

### R2-P1-COPY — frozen rejected P1 semantics

Root cause:

`canonical_multiplayer_item_graph_service_p1.gd` содержит R6/bf24 implementation, включая existing-player lazy normalization и старый hotbar path.

Correction:

Заменить compatibility parent точной production реализацией P1 из `f7ab0a8b...`. P2 current service продолжает наследовать этот parent и добавляет только pure snapshot / explicit durable migration boundary.

Regression:

Inherited P1 canonical-clock suite должна давать `66 assertions, 0 failures` внутри P2 checkout. Дополнительно P2 restore-purity tests должны подтверждать, что normal P1 commands уже canonical-valid до P2 read boundary.

### R2-PURE — P2 read/recovery boundary must stay pure

Root cause risk:

При переносе repaired P1 нельзя вернуть `create_snapshot()` normalization в P2 current canonical service.

Correction:

Сохранить P2 override `create_snapshot()` как pure serializer. Единственная compatibility normalization P2 — explicit post-restore migration с собственным revision/tick publication при фактическом изменении representation.

Regression:

`V0-P2 Item Graph restore purity` остаётся GREEN и отдельно проверяет pure read + one-time migration semantics.

## Scope

Разрешено:

- replay topology P2 на repaired P1;
- P2 compatibility-parent refresh;
- существующие P2 bootstrap/fingerprint/reconnect файлы;
- targeted test/runner correction, необходимая только для exact-head trust boundary.

Не разрешено:

- новый Item Graph owner;
- изменение network authority;
- P3/resource semantics;
- Construction redesign;
- UI authority;
- новый persistence owner;
- merge P1 или P2 через human runtime gate.

## Required exit evidence

Перед новым independent review итоговый P2 exact head должен иметь:

- Project Control SUCCESS;
- inherited P1 full regression GREEN, включая canonical-clock `66/0`;
- P2 restore purity GREEN;
- P2 canonical fingerprint GREEN;
- real UDP shared-state reconnect GREEN;
- exact Windows Godot `4.7.1.stable.double.custom_build.a13da4feb`;
- fresh Reviewer + Verifier + Director routing for HIGH risk.
