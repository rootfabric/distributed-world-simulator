# MVP3 — FRESH INDEPENDENT VERIFIER R1

## Роль и запреты

Эта ветка является только verifier-carrier и НЕ является новым product subject. Проверяемый продукт — её immutable parent:

- SUBJECT_HEAD = `91c0df9d9e9c36f3519110aea85b5884214b9278`
- SUBJECT_TREE = `1a77202306e5a7f943b24e47d5c84f666b0a2cdc`
- SUBJECT_REF = `freeze/v0-mvp3-r12-91c0df9d-r1`
- ORIGINAL_PRE_REPAIR_FREEZE = `6a750d859d5858ff1f2d76bbf2ef7664a893ee86`
- PARENT = `V0-MVP-R1-WO-001`
- EPOCH = `E2026-09-09-V0-MVP-R1`

Роль: FRESH INDEPENDENT VERIFIER. Нельзя быть Implementer или Reviewer этого subject, нельзя вносить исправления, push в product branch, создавать PREDICATE_VERIFIED, сливать PR, завершать parent/mission или объявлять ручной прогон без реального интерактивного ввода.

## Что проверяется

Predicate-кандидат: `MVP_SEAM_NO_RECONNECT_OR_RESPAWN`.

Verifier обязан независимо установить по exact raw evidence и исходникам, а не по prose-выводам Implementer/Reviewer:

1. Два реальных графических клиента и два native authority плюс gateway являются отдельными процессами, оба игрока независимо управляются и видят общий мир.
2. Визуальный мир использует принятую immutable P7 bootstrap projection, а не отдельную плоскую подмену; canonical Matter/Item/player/persistence/network authority не дублируется.
3. Интерактивное движение проходит через canonical `MOVEMENT_INTENT` и существующую fixed 60 Hz server simulation. Частота клиентских пакетов не создаёт дополнительных физических шагов; replay/no-op не считается движением.
4. Для A реально доказан маршрут A->B->A: source freeze, bounded actor export, warm target, source retirement, target activation, затем ненулевое движение на B и отдельное ненулевое движение после возврата на A. `route_history` двух клиентов — только наблюдение игрока A и не подменяет эти native receipts.
5. Игрок B имеет собственные успешные fixed-tick movement receipts и ненулевое физическое перемещение; наблюдение A не считается управлением B.
6. На seam сохраняются logical/player entity identity, transport session, ownership epoch, input watermark, body/camera instances. Connect count каждого graphical client = 1; reconnects = 0; disconnects during workload = 0; respawns/rebinds/identity changes = 0.
7. Frozen source и warm target fail closed; stale/conflicting replay, invalid checksum, premature activation, wrong proof/token и excess same-tick input реально отвергаются без canonical mutation.
8. Idle authority ENet link обслуживается без retry/reconnect и не теряется до первого transfer.
9. Item Graph не переносится как часть player seam и не мутируется handoff-операцией. Это НЕ доказательство MVP4 item preservation.
10. Harness использует production event-ledger reconciliation; исторические quarantined bytes не удалены, duplicate sequence и изменённый pin остаются отрицательными контролями.
11. Exact CI проверяет тот же SUBJECT_HEAD/TREE, approved double Godot hash, clean tracked state, full Harness, actual five-process graphical path, MVP1/MVP2 regression, canonical full world/core и PC0/directional observations. Все raw logs/JSON/PNG доступны как GitHub artifacts и manifest hashes совпадают с bytes.
12. Manual/keyboard evidence — отдельный последующий gate. Его отсутствие не превращать ни в PASS, ни в runtime defect; verifier verdict должен явно отделять machine verification от manual acceptance.

## Evidence route

Финальный exact matrix: workflow `MVP3 Closure R12 Exact Candidate Evidence`, run должен быть получен live из ветки `control/v0-mvp3-closure-6a750d85-r1` и проверен по `EXPECTED_HEAD=91c0df9d...`, а не принят из этого документа. На момент создания carrier run был RUNNING; verifier запускается только после terminal result и обязан live-получить run ID/jobs/artifacts.

Fresh Reviewer R4: live-получить из PR #597; принимать только review, явно привязанный к `91c0df9d...`. Старые R1/R2/R3 — historical evidence, не verdict для финального subject.

## Требуемый результат

Вернуть один verdict: `PASS`, `FAIL` или `INSUFFICIENT_EVIDENCE`.

Обязательно указать:
- independently resolved SUBJECT_HEAD/TREE и freeze ref;
- Reviewer R4 exact binding и результат;
- exact run ID, все job conclusions, engine SHA, artifact IDs/digests и результаты повторного rehash manifest members;
- конкретные process/connection/identity/movement/transfer/replay/world-core/Harness факты;
- REQUIRED_FIXES отдельно от RANK_UP_MOVES;
- `manual_input_verified=false`, пока нет отдельного настоящего manual/MCP evidence;
- `mvp3_predicate_verified=false` и `parent=IN_PROGRESS` в verifier carrier независимо от PASS machine verification.

Verifier PASS означает только независимую machine verification финального subject. Он не закрывает MVP3 самостоятельно.
