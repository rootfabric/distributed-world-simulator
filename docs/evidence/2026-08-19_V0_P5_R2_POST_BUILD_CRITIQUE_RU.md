# V0-P5 R2 — post-build critique

Дата: 2026-08-19

Project Epoch: `E2026-08-19-V0-P5-R2`

Work Order: `V0-P5-R2-WO-001`

Проверенный control HEAD: `cd5521c2e518d11857cd8b375472949240b5448a`

Source implementation commit: `d66694312ad79db65d35e12d18fce5e9ee2afcc9`

## Итог

Implementer-side результат: **PASS для передачи fresh independent Reviewer/Verifier**, но не P5 acceptance и не разрешение на merge/P6.

R2 создан не как новая feature-разработка, а как control-correct closure carrier после того, как технически работающие prototype repairs #156/#158 оказались шире исходного P5 Work Order. В R2 авторизация материализована до source mutation: exact base `dd50af56...` -> Project Epoch/Work Order -> `0002 DIRECTOR DISPATCHED` -> один source implementation commit.

## Scope discipline

Implementation commit `d666943...` меняет ровно 25 путей, перечисленных в `allowed_paths`. Все 25 Git blobs повторно использованы byte-for-byte из уже испытанного donor `fe051261...`; доказательство зафиксировано в `P5-R2-DONOR-BLOB-EQUIVALENCE-001`.

За пределами test/control/harness единственный production path относительно `dd50af56...`:

`src`: `scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd`

Изменение не ослабляет same-revision rejection. `MULTIPLAYER_SAME_REVISION_MUTATION` очищается только если последующая обработка compact snapshot:

- не добавила нового compact rejection;
- приняла более новый snapshot **или** clock-only authoritative update;
- текущий stale health code равен именно `MULTIPLAYER_SAME_REVISION_MUTATION`.

Network protocol, authority, persistence, Item Graph canonical truth, M7 command bridge и P5 equipment/mining domain не изменялись.

## Validation

Engine: `4.7.1.stable.double.custom_build.a13da4feb`.

Exact-source artifact для `cd5521c...`:

- workflow: `V0 P5 R2 Closure Source Probe`;
- run: `32250018965` — SUCCESS;
- artifact: `p5-r2-closure-cd5521`;
- digest: `sha256:9d44bd08c9a9fb4fbcdf46318c35ced14e8e5a82822ae458cf3c23b781a8b399`.

Project Control `#1005 / 32249954175` на `cd5521c...`: SUCCESS.

Editor import: RC=0, parser/compile markers=0.

Clean focused batch: **18/18 PASS**, включая:

- P1 world items/containers `67/67`;
- strict P2 live shared-state `41/41`;
- P4 publication/fallback `60/60`;
- P4 two-client reconnect `46/46`;
- P3 live mining `43/43`;
- M7 playground `63/63`;
- полный P5 focused gate `14/14`.

Full world/core: **239/239 standalone PASS в одном непрерывном run без retry**, затем `main_scene_cli_all` RC=0, failure marker=false. Финальный marker: `FULL_WORLD_CORE_REGRESSION_PASS`.

## Transient observation

Первый fresh R2 focused batch один раз получил RED в P4 two-client reconnect на `actor stage 0 runtime has no persistent error`. Этот результат не был проигнорирован.

Проверка после него:

1. локальная диагностика печатала report только если error уже присутствует;
2. пять из пяти изолированных P4 повторов прошли `46/46`;
3. source возвращён byte-for-byte к exact R2 artifact;
4. clean focused batch прошёл `18/18`, P4 `46/46`;
5. continuous full-world run снова прошёл тот же P4 overlay (`232/239`) GREEN.

Поэтому observation классифицирован как **transient process/timing event, не воспроизведённый как deterministic defect**. Дополнительное production/test изменение из-за него не внесено. Reviewer должен отдельно проверить, что такая классификация приемлема и что compact health semantics не скрывают реальный rejection.

## Residual risks

1. `m3_graphical_client_runtime.gd` затрагивает presentation/client health boundary; нужна независимая проверка того, что очистка stale code не маскирует новый same-revision rejection.
2. World-regression baseline carrier широк по test/harness поверхности, хотя blobs уже приняты donor-веткой и повторно использованы без редактирования.
3. Один P4 timing observation требует внимания Reviewer, несмотря на последующие 7 GREEN доказательств (5 isolated + focused + full-run).

## Что намеренно не сделано

- P5 не принят.
- PR не слит.
- P6 не активирован.
- mutation lease не ротирован.
- Reviewer/Verifier PASS не подделан Implementer-ом.

Следующий законный этап: freeze Evidence Map -> fresh independent READ-ONLY Reviewer -> fresh independent Verifier -> только после обоих PASS контроль checkpoint proposal/acceptance.
