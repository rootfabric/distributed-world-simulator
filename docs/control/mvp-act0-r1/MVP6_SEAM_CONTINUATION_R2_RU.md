# MVP6 seam — continuation R2

Исходный Windows handoff перепроверен через GitHub: feature HEAD `182d93872bfddbf52a72ab170371ebb9489690bb`, TREE `1f3a31e1aa2ea341ff164e96844e3686ed63af08`; наблюдаемый main `6982a563dd0c88c81449566131852c601ae89868`. Продолжается тот же `V0-MVP-R1-WO-001`, без второго runtime worker. Главный источник требований — `MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM_REQUIREMENTS_RU.md` и machine contract R1.

## Граница

`HA-V0-MVP6-JOURNAL-BASELINE-MERGE-R1` остаётся OPEN. Поручение продолжить работу не является разрешением merge PR646 или main. Этот slice — ограниченное воспроизведение и подготовка in-scope composition исправлений, а не product acceptance, directional clearance или закрытие seam predicate.

## Причины и план

1. `construction_authority_server_endpoint.gd::submit` вызывает raw gateway без trusted actor. M3 bridge уже проверяет client/session и передаёт `logical_player_id` в canonical gateway. Сначала один и тот же valid BUILD command проверяется в двух свежих native factory fixtures: C17/raw (ожидаемый P4_BUILD_PLAYER_CONTEXT_REQUIRED) и M3 (реальное списание ore и создание Construction). Нельзя переиспользовать terminal rejection первого gateway как доказательство второго.
2. P4 factory передаёт в executor ненастроенный C9 DamageProcess. После штатного трёхстадийного BUILD и отдельного server-owned DAMAGE grant выполнить valid REMOVE leaf: ожидаемый CONSTRUCTION_DAMAGE_PROCESS_NOT_CONFIGURED, с неизменными item/construct snapshots. Это не доказательство работающего REMOVE.
3. После сохранения отрицательных контролей допустима новая ограниченная composition factory в уже разрешённом `scripts/runtime/networked_gameplay/mvp/**`. Она собирает существующие P4 BuildProcess/LivePort/M0/AuthoritativeAdapter/C9, не дублирует owners и не изменяет foundation файлы. Будущий server-owned план 100 частей должен использовать эти же native transactions.
4. C17 routing получает короткоживущий authenticated ingress context через MVP glue к штатному M3 bridge; command не может сам назначить actor. Контекст ограничен exact command и синхронным вызовом, очищается после возврата, не является ledger. Direct submit вне authenticated ingress обязан отвергаться. Native C17 и canonical gateway сохраняют собственные fencing/replay/permission проверки.

## Обязательные ограничения

Не изменять старые native/MVP3/MVP4/MVP5 тесты. Не менять P4/M4/C9/C17 owners вне allowed_paths. Не вставлять final snapshot напрямую. Один canonical writer, read-only spatial sections, отсутствие независимых половин. Пять процессов, 100 частей, реальный server movement по derived collision, ADD/REMOVE, client agreement и persistence остаются отдельными обязательными доказательствами. Положительный backend diagnostic не закрывает их.

## Исполнение и evidence

Локальный executor подтвердил DNS failure для github.com; повторный ad-hoc clone/download не используется. Read/write — GitHub connector; точное выполнение — существующий repository-owned workflow с canonical double Godot. В разрешённом workflow добавляется отдельный явно помеченный seam diagnostic job: exact event HEAD/TREE, scoped delta от handoff, отсутствие source mutation во время теста, raw command exits/JSON/fatal scan и SHA256 manifest. Это не обход main merge gate: acceptance flags остаются false и реальный Drive/Close сохраняется отдельно.

Обнаруженный устаревший `required_predicates == old` guard исправляется только на сохранение всех прежних predicates в прежнем порядке и точное наличие принятого дополнительного seam predicate; arbitrary additions/removals не разрешаются. Прежний acceptance job не превращается в диагностический PASS.

Следующий resume action: прочитать последний exact run нового seam diagnostic, сверить хеши и literal native errors; затем bounded composition fix и новые positive/negative tests. До этого никакой runtime PASS этой версии не заявляется.
