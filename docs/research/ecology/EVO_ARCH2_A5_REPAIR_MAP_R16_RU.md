# EVO ARCH2 A5 — Repair Map R16

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## RM-A5-29 — Bounded recursive parent provenance

RM27 сделал persisted `PARENT_TRANSFER` provenance семантически проверяемым, встроив exact paid-parent state preimage. Но если каждый parent-transfer parent сам содержит exact parent state, lineage proof растёт рекурсивно с каждым поколением. Без явной границы это оставляло два boundedness-риска:

- размер persisted lifecycle state не имел generation-depth cap;
- recursive `LS.validate()` мог получить неограниченную глубину вызовов на длинной допустимой lineage.

Для research A5 введена явная bounded policy:

```text
MAX_PARENT_PROOF_DEPTH = 32
```

Это не production lineage design и не cryptographic registry. Это ограничение research-candidate, необходимое, чтобы exact-preimage provenance оставался конечным и проверяемым в текущем scope.

## Validation semantics

`LS.validate(v, blueprint, parent_proof_depth=0)` передаёт глубину при рекурсивной проверке exact parent state.

Для `FOUNDER_ENDOWMENT` recursion заканчивается.

Для `PARENT_TRANSFER`:

```text
if parent_proof_depth >= MAX_PARENT_PROOF_DEPTH:
    reject LIFE_PARENT_TRANSFER_DEPTH

validate exact parent witness at parent_proof_depth + 1
```

`validate_parent_transfer_witness()` также имеет bounded depth и fail-closed error `PROPAGULE_PARENT_PROOF_DEPTH` / `PROPAGULE_PARENT_STATE` для prospective child, чей parent chain уже исчерпал лимит.

Таким образом:

- lineage до 32 parent-transfer links валидируется и persist/restart поддерживается;
- попытка материализовать поколение 33 fail closed;
- parent на самой границе всё ещё может выполнить resource-funded reproduction и emitted propagule, но этот propagule не может быть материализован в новый persisted A5 child в рамках текущего bounded provenance contract.

## Executable oracle

Добавлен:

```text
validation/ecology/evo_arch2_a5/rm_a5_29_bounded_parent_proof_depth.gd
```

Oracle строит реальную цепочку поколений через:

```text
founder
→ funded development
→ reproduction
→ exact paid parent witness
→ materialize child
```

и проверяет:

- все поколения `1..32` materialize + validate;
- proof depth реально достигает 32;
- state на границе serialize/deserialize roundtrip;
- generation-32 parent может породить оплаченный propagule;
- materialization поколения 33 отклоняется;
- прямой witness для overflow также fail closed.

## Дальнейшая архитектура

Если проекту понадобится practically unbounded lineage, этот nested proof должен быть заменён отдельным bounded этапом на authoritative lineage/birth receipt registry или иной внешний trust anchor с fixed-size child reference. Это намеренно не вносится в A5, чтобы не расширять research Work Order в production persistence authority.

## Acceptance

RM29 сам по себе не является acceptance. После freeze нового exact HEAD/TREE обязательны fresh canonical verifier и fresh independent review одного и того же subject.