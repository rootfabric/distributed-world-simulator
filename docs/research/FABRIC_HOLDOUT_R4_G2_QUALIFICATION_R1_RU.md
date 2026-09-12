# FABRIC R4: bounded qualification R1

Статус инструмента: IMPLEMENTED_CANDIDATE. Не ACCEPTED, не production freeze.
Work Order: FABRIC-R4-QUALIFICATION-WO-001.

## Две независимые линии

Product subject находится в PR #592:
HEAD `989ed83c10d861f151423b4e7dae6952c7177b68`,
TREE `aefd109b76a5ebc5ee98f35e730bb07a895f59fe`.

Инструмент и evidence находятся в `control/fabric-r4-qualification-r1`.
Control HEAD нельзя подставлять вместо product HEAD. Добавление документов или
результатов в control не переименовывает существующие product runs. Смена любого
product HEAD требует нового qualification/review cycle; freeze не переносится.

Исходный HEAD ddb91770c1aa3b8e0ce7e22a513ff0e84e7caef7 имел TREE
`e0d619f80c48c9ead11cd9d66a68ead5f91b5ce2`. TREE e0d6aa9996237d6710db5152ce77470f28cadbb7
в исходном сообщении был неверен. Проверка использовала GitHub Git API, source
bundle и CI identity, а не скопированное заявление.

## Что исправлено в product

Глобальная orbit-normalization меняла v1 hashes и не сходилась на конечных
малых double. Это давало два независимых проявления: B0.4-A prerequisite FAIL
и исторический COMPLEX0@2000 transaction checksum FAIL в Complex Labs/CX-VIS0.
Общий NetworkUtils восстановлен byte-for-byte из b88004e77a9a424f1b23ba979f5ce8883a98f1a8;
старые тесты, golden, физические thresholds и canonical owners не менялись.
Lossless replay вынесен в явный opt-in `dws.fabric.r3.lossless-json.v1`.
Контракт и ограничения: product `FABRIC_HOLDOUT_R4_G2_LOSSLESS_TRANSPORT_R1_RU.md`.
Это коррекция прежнего G2-C claim, а не PASS старого naked-numeric JSON профиля.

## Инструмент

`qualification-policy.r1.json` задаёт шесть обязательных gates: exact G2/R3/R2/R1,
B0.4-D Linux closure, Complex Labs, CX-VIS0, B0.6-CLOSE и portable B0.4-D smoke.
G1 исторически FALSIFIED и проверяется по Git blob identities семи frozen файлов.
Состояния BASELINE_FAILURE/INFRASTRUCTURE/CANCELLED/INDETERMINATE не дают waiver.
B0.6 включает неизменённый performance gate; отдельный быстрый PERF не заменяет
полный CLOSE. У инструмента нет права принимать checkpoint или менять Harness.

`qualify.py` последовательно исполняет pinned команды в отдельном чистом product
worktree, сохраняет полные stdout+stderr, exit code, actual binary SHA256,
HEAD/TREE, policy digest, длительность и проверку tracked source до/после.
Timeout завершает process group и получает 124. Existing output directory не
перезаписывается. Новые результаты не затирают предыдущую отрицательную историю.

`qualification.py` отдельно проверяет evidence: exact identities, policy digest,
команды, binary/workflow bindings, полные логи, обязательные PASS-маркеры, fatal
маркеры, SHA256, отсутствие пропусков и frozen drift. Reject: дубли JSON keys,
NaN/Inf, path traversal, escaping symlink, corrupt/missing logs, stale receipts,
CANCELLED, fake PASS substring и недоказанные исключения.

CI portable workflow не записывает SHA256 официального бинарника. Поэтому для
него используется отдельный режим `ci_workflow`: pinned workflow blob, run/job IDs,
успешные обязательные steps, exact HEAD/TREE из identity step и явно обозначенный
log excerpt. Это НЕ полный архив CI log и НЕ exact-double evidence. Полный log
прочитан через connector; независимый Reviewer обязан повторно прочитать связанный
job и подтвердить происхождение. Квалификатор проверяет согласованность свидетельств,
но не аутентифицирует автора или GitHub API ответ. Самостоятельное редактирование
receipt не создаёт доверия. Эта граница относится и к локальным self-validation logs.

## Повторяемый запуск

Нужны Python >=3.10, git, bash, точный приложенный Linux double Godot.
Инструменты берутся из закреплённого control commit; product checkout — отдельно.
Сначала live-разрешить PR HEAD и canonical main policy, прочитать AGENTS/Harness.
Не выводить ожидаемый policy digest из непроверенного receipt.

```bash
CONTROL=/path/to/pinned-control-checkout
PRODUCT=/path/to/clean-product-worktree
GODOT_BIN=/path/to/godot.linuxbsd.editor.double.x86_64
Q="$CONTROL/scripts/research/fabric_holdout_r4_g2"

python3 "$CONTROL/tests/research/fabric1/fabric_holdout_r4_g2_qualification_test.py"

# POLICY_SHA256 берётся из независимого закреплённого evidence manifest.
python3 "$Q/qualify.py" \
  --repo "$PRODUCT" \
  --head 989ed83c10d861f151423b4e7dae6952c7177b68 \
  --tree aefd109b76a5ebc5ee98f35e730bb07a895f59fe \
  --godot "$GODOT_BIN" \
  --policy "$Q/qualification-policy.r1.json" \
  --policy-sha256 "$POLICY_SHA256" \
  --ci-observation "b04d_portable=/path/to/rechecked-observation.json" \
  --out "$PRODUCT/artifacts/r4-qualification-fresh"
```

Без CI observation результат остаётся BLOCKED/MISSING, не PASS.
Offline перепроверка уже собранного пакета не исполняет product:

```bash
python3 "$Q/qualification.py" \
  --repo "$PRODUCT" --head "$PRODUCT_HEAD" --tree "$PRODUCT_TREE" \
  --policy "$Q/qualification-policy.r1.json" --policy-sha256 "$POLICY_SHA256" \
  --receipts "$EVIDENCE/receipts.json" --evidence-root "$EVIDENCE" \
  --out "$EVIDENCE/recheck.json"
```

Exit 0 = technical qualification PASS; exit 2 = BLOCKED; exit 3 = INVALID_EVIDENCE.
Положительный результат означает только READY_FOR_INDEPENDENT_REVIEW.
Всегда false: production_freeze_allowed, unseen_holdout_allowed, checkpoint_accepted.

## Следующие переходы и acceptance boundary

1. Сверить актуальный product HEAD, main-owned policy и все новые CI reds. Если
   новый красный run противоречит локальному PASS, не скрывать его: обновить
   classification/qualification и выяснить первую ошибку на одинаковой среде.
2. Fresh independent Reviewer проверяет repair, изменение wire-контракта, canonical
   ownership, qualification policy/tool/evidence и подтверждает exact SUBJECT.
3. Fresh independent Verifier повторяет требуемые runs/controls. Наши локальные
   и self-hosted executions — self-validation, а не независимая verification.
4. Только после требуемых main-owned Harness approvals — immutable production
   freeze и зафиксированный preregistered протокол новой unseen проверки.
5. Отдельный автор создаёт genuinely unseen corpus. Frozen implementation не
   изменяется после раскрытия. Повтор после инфраструктурного INVALID допустим
   только по заранее заданному правилу и с тем же subject; semantic FAIL остаётся
   FALSIFIED и требует нового epoch/нового unseen набора, а не подгонки к кейсам.
6. PASS нового holdout + независимая verification + canonical acceptance record
   закрывают R4. Инструмент сам этого не делает; SCALE-R5/INTEGRATION-R6 не открыты.

Не делались: main merge, global CI redesign, physics refactor, threshold/golden
relaxation, раскрытие unseen corpus, само-APPROVE, фиктивный CloseMission.
PowerShell Harness в этой среде не запускался; это явно остаётся обязанностью
канонического review/acceptance контура, а не заявляется выполненным.

Post-build critique: scope bounded, два небольших CLI без daemon/broker/нового
runtime owner. Qualification policy/tool требует отдельного независимого review
перед переиспользованием в других программах. Повторная общая унификация CI отложена.
