# EVO ARCH2 A5 — Repair Map R17

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## RM-A5-30 — Parent proof depth must fit CanonicalValueV1 depth 24

Fresh review подтвердил boundedness blocker в exact-parent-state provenance: RM27/RM29 рекурсивно вкладывают `parent_state` в `origin_receipt`, а accepted `CanonicalValueV1` fail-closed отклоняет nesting depth `> 24`. Предварительный research-cap `MAX_PARENT_PROOF_DEPTH = 32` поэтому был недостаточен: validator мог разрешить lineage, которую canonical encoder уже не способен сериализовать/хешировать.

## Canonical budget

Accepted `CanonicalValueV1` задаёт:

```text
encode(value, depth): reject if depth > 24
_normalize(value, depth): DEPTH_LIMIT if depth > 24
```

Для текущего A5 persistent state консервативный worst-case budget:

```text
full A5 state before lineage nesting      <= 7 levels
life-state-file wrapper                    + 1
one origin_receipt.parent_state link       + 2 per generation
canonical limit                             24
```

Отсюда текущий bounded research-format допускает максимум:

```text
8 + 2 * parent_transfer_links <= 24
parent_transfer_links <= 8
```

Поэтому:

```text
MAX_PARENT_PROOF_DEPTH = 8
```

Это не заявка на production lineage architecture. Это fail-closed граница именно текущего nested exact-preimage research format.

## Runtime / validation semantics

- поколения parent-transfer `1..8` должны оставаться semantically valid;
- generation 8 state должен успешно `LS.serialize()` и `LS.deserialize()`;
- parent generation 8 всё ещё может выполнить полностью оплаченный reproduction transition и emit propagule;
- materialization поколения 9 обязана fail closed до создания persisted noncanonical child;
- recursive semantic validation также не проходит глубже этой границы.

## Executable evidence

Обновлён:

```text
validation/ecology/evo_arch2_a5/rm_a5_29_bounded_parent_proof_depth.gd
```

Теперь он проверяет exact boundary `8 PASS / generation 9 FAIL` и canonical roundtrip на границе.

Добавлен отдельный RM30 oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_30_canonical_parent_depth_budget.gd
```

Он проверяет:

1. synthetic canonical depth 24 encodes;
2. synthetic canonical depth 25 rejects;
3. A5 parent-proof cap равен 8;
4. реальная funded lineage materialize проходит через generation 8;
5. generation 8 lifecycle state сериализуется канонически;
6. generation 8 parent может emit paid propagule;
7. generation 9 materialization fail closed.

## Future route

Практически неограниченная lineage не должна реализовываться дальнейшим увеличением nested state depth. Следующий масштабируемый вариант — отдельный bounded design для fixed-size authoritative birth/lineage receipt reference (registry/trust anchor), который не входит в A5 Work Order.

## Acceptance

После RM30 A5 снова требует новый immutable HEAD/TREE, fresh exact canonical verifier и fresh independent review ровно этого subject. Старые verifier/review результаты на более ранних HEAD не считаются финальным acceptance evidence.