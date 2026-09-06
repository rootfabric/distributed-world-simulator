# P7 full world/core — EG1 diagnostic R1

Ограниченное validation-only продолжение `V0-P7-EG1-DIAGNOSTIC-R1`.
Родитель: P7 canonical closure, PR #577. Runtime subject c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f,
TREE04679a6e67fc86ec156d4341140fd5b0225d6085. Нет runtime mutation или dispatch.

Факт: full world/core run34038561062, artifact9991187468, ZIP SHA256
38366deba510bf36bc72fc0382922e02bc95b252982cb0bb27984bd22823f844,
прошёл221 шаг; step222 test_eg1_gateway_processes завершился exit1 после63s:
SIM_TIMEOUT/GATEWAY_TIMEOUT/CLIENT_TIMEOUT, sim ledger содержит3item operations,
четвёртый movement отсутствует. Это НЕ полный world/core PASS.
M2 graphical test с Xvfb прошёл. Причина EG1 пока не классифицирована.

Нефатальные сообщения о breakpoint TCP9081 сопровождают ошибку, но не доказывают
причину: локальный диагностический predecessor с неизменёнными runtime blobs
прошёл EG1 с включённым и выключенным bridge. Это НЕ canonical acceptance.

Проверить unchanged exactc14 EG1 на том же hosted Ubuntu с двумя изолированными
user profiles, bridge enabled/disabled. Сохранить exit/logs и реальные child JSON
reports, включая counters; не редактировать тесты, transport или production.
Нельзя объявлять missing movement инфраструктурным дефектом без доказательства,
увеличивать timeout вслепую, пропускать EG1 либо объявлять весь gate по одному
повторно прошедшему тесту. Далее — только доказанная scoped repair/retest.

Actions используется для исполнения тестов и артефактов. Предсобранный exactGodot
получается из artifact dependency предыдущего run, source скачивается обычным
checkout(c14); никакого .git/source transport workaround. Allowed paths этого
validation-only продолжения: данный каталог и .github/workflows/p7-eg1-diagnostic.yml.
Независимые Reviewer/Verifier и human acceptance gates не снимаются.
