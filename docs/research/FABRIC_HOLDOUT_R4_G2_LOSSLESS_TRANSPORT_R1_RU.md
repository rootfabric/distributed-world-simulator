# G2-C R1 — явный lossless wire вместо изменения общего v1 hash

Статус: IMPLEMENTED_CANDIDATE, не ACCEPTED. Risk: HIGH.
Work Order: FABRIC-R4-QUALIFICATION-WO-001, control/fabric-r4-qualification-r1,
commit 75d9c8ec91b0acbb9bbdcd4d5dbe3527c13c5801,
`docs/research/FABRIC_HOLDOUT_R4_G2_QUALIFICATION_WORK_ORDER_RU.md`.

Исходный HEAD: ddb91770c1aa3b8e0ce7e22a513ff0e84e7caef7.
Проверенный TREE: e0d619f80c48c9ead11cd9d66a68ead5f91b5ce2.
Baseline: b88004e77a9a424f1b23ba979f5ce8883a98f1a8.

## Причина, а не обход

Orbit-normalization была внесена в общий NetworkUtils. Поэтому исследовательский
G2 изменил checksum старых Construction/BAKE-потребителей. B0.4-A перестал
создавать состояние с конечным числом около 1.5868896825778374e-155: orbit
исчерпывает 4096 шагов. COMPLEX0@2000 перестал совпадать с историческим checksum.
На одинаковом exact double binary база проходит оба теста, ddb91770 их проваливает.

Общий `network_contract_utils.gd` восстановлен byte-for-byte из baseline.
Старые BAKE-тесты, golden checksums, физические thresholds и canonical owners
не изменены. Поднятие orbit budget и округление не используются.

## Контракт нового профиля

`dws.fabric.r3.lossless-json.v1` — opt-in research envelope, а не глобальная
смена схемы. Все узлы типизированы: nil/bool/int/string/float/array/dictionary.
Double переносится ровно восемью байтами IEEE754 little-endian в hex;
StreamPeerBuffer имеет явно заданный big_endian=false. JSON видит только строки
и массивы, поэтому numeric stringify/parse drift не затрагивает физические числа.
Данные пользователя не могут столкнуться с tags: dictionary представлен списком
упорядоченных пар. Сохраняются типы, signed zero и все биты допустимого double.

Сохраняется v1 safe-integer envelope. NaN/Inf, неподдерживаемые Godot Variant,
нестроковые ключи, неизвестные tags, повторяющиеся/неупорядоченные dictionary keys,
неверный checksum, >100000 узлов и глубина >64 отклоняются. Текст ограничен
8 MiB. `parse_json` требует canonical wire text, в том числе отвергает дубли
верхнеуровневых JSON keys. `decode(Dictionary)` принимает уже разобранный объект:
он не утверждает, что может восстановить lexical duplicates исходного текста.
Нет bytes_to_var, object deserialization, обхода checksums или numeric округления.

Checksum envelope — integrity, не аутентификация. Внешний trusted
`expected_replay_checksum` остаётся обязательным для replay. Внутренние v1
checksums переносятся неизменными; новый внешний checksum не легализует
повреждённый inner journal.

## Entry points и совместимость

Новый `lossless_replay_bridge_v1.gd` наследует существующий R3 bridge и добавляет
только `export_replay_transport` / `replay_transport`. Существующий bridge,
Construction Store, authority/fence predicates, native replay API и физический
runtime не изменены. Новый код не владеет вторым состоянием.

Использование: export_replay_transport -> JSON.stringify/parse envelope ->
replay_transport с externally trusted checksum. Для текстового входа сначала
`lossless_json_v1.parse_json`; прямой decode допускается для уже parsed Dictionary.

Это явная коррекция G2-C. Naked JSON numeric transport без профиля больше НЕ
объявляется lossless/стабильным. Старый orbit-based claim не переименовывается
в PASS. Непринятые orbit-generated G2 journals не объявляются совместимыми
с восстановленным baseline v1; accepted baseline semantics сохраняются.
Независимый Reviewer проверяет эту коррекцию до любого freeze.

## Focused controls и оставшиеся gates

До commit, на рабочем дереве: transport 381/381, G2 89/89; B0.4-A, COMPLEX0@2000
и COMPLEX2-PERF проходят. G2 дополнительно доказывает, что повторная упаковка
повреждённого inner checksum не обходит trusted replay checksum.
Эти focused результаты НЕ являются exact-head evidence нового commit.

После commit нужны полный exact G2/R1/R2/R3, B0.4-D portable и Linux closure,
Complex Labs, CX-VIS0, полный B0.6-CLOSE, qualification manifest, fresh independent
Reviewer/Verifier. B0.6 CI performance failure не освобождается автоматически.
G1 frozen bytes и FALSIFIED остаются неизменными. Unseen holdout не раскрыт,
production freeze не выполнен, R4/R5/R6 не закрыты и не разблокированы.

Post-build critique: уменьшен blast radius; общий v1 восстановлен, R3 bridge не
модифицирован, транспорт opt-in. Новый оркестратор/owner не создан.
NO_MATERIAL_REFACTOR_REQUIRED в пределах этого bounded repair; independent review pending.
