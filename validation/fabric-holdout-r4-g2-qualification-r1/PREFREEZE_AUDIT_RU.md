# Pre-freeze audit после локальной qualification

Subject: 989ed83c10d861f151423b4e7dae6952c7177b68 / aefd109b76a5ebc5ee98f35e730bb07a895f59fe.

Локальная обязательная матрица PASS не объявляет все GitHub workflow зелёными.
При последнем чтении: Linux B0.4-D 34666974989, Complex Labs 34666974943,
CX-VIS0 34666974920 и B0.6-CLOSE 34666974977 ещё QUEUED. COMPLEX2-CLOSE
34666974959 CANCELLED — не PASS. Project Control 34666974890 SUCCESS.

## Дополнительный PERF CI FAIL не скрыт

На новом subject отдельный COMPLEX2-PERF run 34666975051 / job 103480745910
завершён FAILURE: COMPLEX2PERF_CASE_BUDGET_EXCEEDED, 500 деталей,
15633939 us > 12000000 us. Полный job log прочитан через GitHub connector.
Runner dws-linux-outenemy; canonical Godot SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.

Независимое повторное чтение baseline run 34143404040 / job 101810134743:
HEAD b88004e77a9a424f1b23ba979f5ce8883a98f1a8,
TREE c22cac6d6b7a652305ee4d770ea325bf0c08c0f4,
тот же runner, workflow и exact Godot. FAILURE в том же assertion:
500 деталей, 15471123 us > 12000000 us. Это наблюдения 8 и 12 сентября,
не синхронный controlled benchmark; их нельзя использовать как доказательство
отсутствия небольшого performance regression или как объяснение нагрузки хоста.

Дополнительно статический обход quoted res:// зависимостей PERF test + runner,
workflow и project.godot нашёл 38 файлов: все Git blobs совпадают base/candidate,
динамических load(expr) в этой выборке не найдено. Это поддерживает классификацию
BASELINE_FAILURE, но не является формальным доказательством полноты runtime closure.
Все изменения полного PR к b880 находятся в G2/R3 research path, G2 runner/workflow/docs/tests;
общий NetworkUtils восстановлен до baseline. Старые PERF threshold/test не менялись.

Локальная полная B0.6-CLOSE на новом subject проходит все 26 runners, включая
PERF и COMPLEX2-CLOSE. PERF 500/1000/2000: 5945964/5822361/5864152 us.
B0.6 closure hash 892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584.

## Решение в рамках этой миссии

Техническая qualification шести заранее заданных gates = PASS. Дополнительный
server PERF остаётся FAIL / BASELINE_FAILURE_PROPOSED, а не переименовывается в PASS
и не удаляется. Классификация и допустимость локального exact evidence требуют
Fresh Reviewer + Director acknowledgment перед freeze. До этого freeze/holdout/acceptance
остаются LOCKED. Новый semantic CI failure или иной failing assertion блокирует
переход и требует bounded triage. Автоматического waiver квалификатор не выдаёт.

Fresh review можно проводить для этого immutable subject и полного evidence pack;
это не финальное release approval и не разрешение unseen. Не требуется менять
production лишь ради документирования этого baseline долга. Нельзя увеличивать
12-second budget ради зелёного CI или заявлять INFRASTRUCTURE без доказательств.
