# MVP7 Post-Build Critique R1 — frozen `ad48b24d`

## Subject

Frozen runtime product: `ad48b24d8cde350db8c26adb958d9a0d62c6ff56` / tree `f306e84ebce87ea3644c60b5dd75779d7980f8bb`. Это critique Implementer-а перед независимым review; не verdict и не acceptance.

## Что получилось хорошо

MVP7 не создал нового canonical world owner. Recovery построен как orchestration поверх уже существующих M6/M4/MW5/M0/C17/SM1 surfaces. Gameplay/replay checkpoint, terrain/Matter cut и Construction repository восстанавливаются из durable canonical state, а не из ожидаемых test fixtures. Два последовательных exact Linux запуска полного `mvp7-recovery` gate прошли на одном HEAD/TREE.

Recovery отрицательно проверяет mixed/corrupt/rollback state до допуска mutation. Старые transport credentials после restart очищаются и отвергаются; новый session/ownership epoch нужен до продолжения. Material replay и Construction terminal operations не создают вторую canonical identity/effect.

Construction restart теперь отдельный реальный process proof: producer и два recovery PID открывают тот же M0 repository, восстанавливают C17 single-writer/read-only topology, после чего клиентский runtime view заново выводит collision из canonical Construction. Проверяется collision по обе стороны seam и непосредственно на границе; удалённый leaf не появляется снова.

Live reconnect доказан свежим шестым процессом и новым ENet peer. Current-state read не перезаписывает исторические MVP4/MVP5 observer caches. После resync новый клиент видит post-Construction terrain/material/Construction, получает 100 collision parts и продолжает движение через authoritative fixed tick. Финальное закрытие протокола требует delivery witness FINISH ACK: gateway закрывает accepted run только после того, как reconnect peer сам disconnect-ится.

Отдельный MVP7 backend liveness сохраняет authority links во время длинной graphical evidence-фазы, но не меняет ENet timeout policy, не вводит backend reconnect и не мутирует canonical state. Унаследованный MVP6 read-only Construction witness сохранён реальным RPC к обеим authority, а не синтетическим заполнением отчёта.

## Что потребовало repair

Первый live reconnect вариант показал три orchestration/evidence дефекта, не потерю canonical state:

1. historical MVP5 pre-Construction material projection ошибочно использовалась как current post-Construction invariant;
2. current-state read мутировал inherited historical observer cache;
3. после полного MVP6 Construction долгий evidence interval оставлял backend authority без liveness traffic; затем ранний timer-close gateway создавал FINISH ACK race.

Repairs разделили historical evidence и current state, сохранили backend traffic без policy relaxation и сделали client ACK delivery частью terminal proof. После этого exact run и fresh rerun зелёные.

## Ограничения доказательства

Recovery model — **confirmed quiescent checkpoint**, а не arbitrary power-loss. Операции, которые не вошли в подтверждённый checkpoint, не обещаются восстановленными.

Transport session и open-container lease не durable. Durable container identity/content восстанавливаются, но открытый lease после restart должен быть получен заново.

Server/process restart и live graphical reconnect пока доказаны двумя разными execution surfaces на одном exact HEAD/TREE. Это соответствует bounded MVP7 recovery/reconnect leaf, но не утверждает единый сценарий «клиенты остаются в одном workload, сервер падает посередине и всё продолжается». Более сильный combined workload явно остаётся для MVP8 (`SERVER_OR_WORLD_RESTART_AND_CONTINUE`).

Текущий exact evidence — Linux double Godot. Fresh Windows MVP7 execution не заявлен. Это не скрывается и должно быть отдельно оценено Verifier-ом относительно platform requirements.

Full world/core финальный regression, Human checkpoint acceptance и runtime/main merge не закрываются этим leaf. PR остаётся draft, Work Order — `IN_PROGRESS`.

## Evidence quality

- exact run: `35447331651`;
- attempt 1 job: `105908424301`, PASS;
- attempt 2 fresh rerun: `105909777021`, PASS;
- native recovery: 549 assertions / 0 failures на каждом запуске;
- graphical reconnect: 106 checks, failed checks = 0;
- inherited MVP6 falsifiers: 13/13 rejected;
- MVP7 falsifiers: 7/7 rejected;
- tracked checkout after native validation: clean;
- engine SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

## Следующая роль

Harness state после product run: `PENDING_POST_BUILD_REVIEW`. Следующий допустимый шаг — fresh independent Reviewer exact-head review, затем independent Verifier. Только после их отдельных durable verdicts Director может решать leaf closure; Human gate/merge остаются отдельными.
