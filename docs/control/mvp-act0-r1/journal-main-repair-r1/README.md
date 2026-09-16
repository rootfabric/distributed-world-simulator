# Main integration: разрешённый same-revision journal rollback

Parent V0-MVP-R1-WO-001; checkpoint V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE.
Это выделенный main-based integration candidate, без MVP runtime composition.
Основание scope: явное «разрешаю» пользователя, resolution и one-file amendment
в feature commit `68433ec7`; HA-V0-MVP6-NX-SAME-REVISION-ROLLBACK-R1.
Reviewable repair map и patch: feature `9b8c2e03`.

При rejection с неизменившимся canonical snapshot journal удалял pending,
но сохранял optimistic presentation. Четыре строки в resolve_prediction()
перестраивают derived projection при duplicate adoption, сохраняя прочие pending.
Новых owners, inventory или ledger нет. Canonical snapshot не мутируется.

Runtime/test перенесены без изменения из frozen feature `73b88181`.
77 assertions покрывают pickup/drop/place/transfer, sibling prediction, replay,
timeout/newer authority и shipped M7 completion/stop. Новый обязательный launcher
RUN_V0_MVP_JOURNAL_ROLLBACK.ps1 проверяет также неизменённые NX6 940 и bridge66.
Fatal markers и отсутствие точного assertion count отклоняют exit0.

Это альтернатива generic duplicate-adoption repair PR #643, не второй patch
поверх него. Нельзя merge оба варианта. Exact evidence PR #643 не переносится
на этот subject. Main integration требует fresh Reviewer/Verifier и HUMAN merge.
V0→NX clearance должен быть проверен после canonical repair; этот PR не
устанавливает clearance, NON_RED или MVP6 VERIFIED.
