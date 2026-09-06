# FABRIC-REPAIR-R1 — Work Order / Repair Map

Статус: IN_PROGRESS. Риск HIGH (recovery/public contracts/authority).
База: 7120018ad07eb39534e04b50ca842b2c34ed12e5.
Control main, прочитанный перед работой: c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f.
Разрешение: явный запрос пользователя выполнить исправления аудита и скорректировать опыты.
Область: research repair, не product acceptance, не merge в main.

## Причины и canonical fix locations

F01: восстановленный FULL теряет `_compiled`, а новый canonical event ошибочно требует старый bake. Исправлять FABRIC1 lifecycle; не заставлять FULL предварительно запекаться. Проверить два последовательных отказа без rebake и атомарность restore.
F02: successor validator проверяет размер ledger, но не точное продолжение истории. Исправить существующий protocol: history_after = sorted(history_before + exactly_one_new_event). Валидные старые пути сохранить.
F03: BRIDGE4 создаёт настоящий source context, но generic compiler заменяет его synthetic owner/epoch. Передавать существующие Frontier/Authority до artifact и проверять независимый current context при исполнении/переходах/recovery. Capsule не удостоверяет текущую authority.
Соседние поверхности: COMPLEX4 functional projection и составной transition, VIS1 session/callers, fallback малых FULL-объектов, конечность input, строгая проверка capsule.

## Границы

Construction/Matter, canonical mutation store и их schemas остаются владельцами мира. Новая authority/revision система не вводится. Владелец и epochs берутся из явно переданного действующего AuthorityEnvelope, Matter остаётся readonly. Standalone B0.7 benchmarks могут сохранять явно исследовательский source context, но интеграция BRIDGE4 не должна попадать в этот fallback.
Не исправлять в R1 физическую подмену strength_n/conductance: это PHYSICS-R2. Не добавлять четыре домена, нелинейный solver, distributed execution или новые global foundations. Исторический freeze сохраняется как evidence; текущая поправка к runtime оформляется явно, не выдаётся за неизменность старых blobs.

## Проверки

1. Сначала сохранить воспроизведение F01/F02/F03 на старых bytes.
2. Unit и production-entry-point сценарии через COMPLEX4/BRIDGE4: restart FULL, два отказа подряд, pending failure restart/cold rebuild, corrupted/rehashed capsules, changed owner/epoch, stale source, readonly coverage, duplicate/dropped/forged/reordered events.
3. Непринятая операция не должна частично продвигать nested runtimes или canonical store.
4. Валидные маленькие графы не отвергаются только из-за benchmark-минимума. NO_SAFE_BAKE ведёт к валидированному FULL, но не делает некорректную физическую систему безопасной.
5. Cold disk recovery: новый Godot process загружает canonical Construction store/Matter/ledger, derived cache отсутствует; сравнение с uninterrupted.
6. Два fresh-process набора, canonical attached double Godot, exit/fatal scan, log SHA256, source dependency identity. Ограниченный source-slice запуск честно помечается и не выдаётся за full current-head checkout.
7. Сохранить changed files, exact tested subject, evidence carrier, риски и отдельный запрос независимого review. Implementer не выдаёт собственную проверку за независимое принятие.

## Публикация и ограничения среды

Обычный shell Git в текущей среде не разрешает github.com; GitHub connector доступен. Разрешён direct authenticated API и non-force ref update. Actions-транспорт запрещён. Не повторять одинаковую инфраструктурную ошибку более двух раз.

## Следующие опыты

Корректирующий план AUDIT-R0 → REPAIR-R1 → PHYSICS-R2 → COMPOSITION-R3 → HOLDOUT-R4 → SCALE-R5 → INTEGRATION-R6 сохраняется. Все F01–F11 должны иметь явный outcome или downstream gate. Таймаут не снимает acceptance criterion; arithmetic work ratio не объявляется measured speedup; новый процесс/fixture не объявляется независимым reviewer.
