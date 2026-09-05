# EVO ARCH2 A0–A3 — статус исполнения и публикации

## Это не ACCEPTED и не production activation

A0 и начальные A1-контракты опубликованы в этой ветке:
- A0: `30b94658287d420b3252ae12d1a42d1249cdbd1d`.
- A1: `eab98a1986334395b4811732b64fa03acf8696cd`, tree `35eeb2b9e912df5ba2071ad498bdae5cc55977ae`.

A2 interpreter, A3 mutation/Lab и дополнительное ужесточение проверки attachment hash в A1 реализованы и проверены локально, **но не опубликованы в GitHub**. Их нельзя считать частью eab98a1. Документ фиксирует факты и препятствие, а не переносит заблокированный runtime другим способом.

## Внешний блок публикации

Два одинаковых вызова GitHub.create_tree для A2 вернули от платформы OpenAI:
«Этот вызов инструмента был заблокирован OpenAI, поскольку мы не смогли определить статус безопасности запроса.»

После ответа повторное чтение ветки подтвердило HEAD eab98a1. Это не GitHub permission denied, не запрет проекта пользоваться Git и не human merge gate. Дальнейшие попытки загрузить тот же runtime другим методом или кодированием не выполнялись. Actions не создавались и не использовались как Git transport. Normal Git ранее завершился `Could not resolve host: github.com`; GitHub connector смог записать A0/A1.

Классификация: EXTERNAL_PLATFORM_WRITE_BLOCKED / PARTIAL_REMOTE_PUBLICATION. Успешная запись этого status-only файла не доказывает, что блок публикации runtime снят.

## Завершённая локальная проверка

Executable legacy baseline: fb1a7ac21037e02033eae6d7e778ed8757514e19, tree 89551693f0cbac555a5026424d36b50cd35b8804. Проверялись новые изолированные successor-файлы, старый tracked runtime не изменён. Source SHA каждого нового проверенного файла записан в summary.

Godot: 4.7.1.stable.double.custom_build.a13da4feb.
Binary SHA-256: bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.

Локальный run: run_20260905T234245Z, RC=0.
Summary SHA-256: 6333a2be088b7d1fc51dbc4e9d1d8813f6ed0b0a85cd3178e500447a028e43cb.

- Contracts/development: 749 PASS, 0 FAIL, два fresh-process запуска с одинаковым результатом.
- JSON Schema: 18 документов PASS.
- Mutation campaign: 1000 родителей, 2000 offspring, 1000 zero-mutation controls; повреждённых состояний 0. Повторный fresh-process replay первых 250 родителей совпал.
- Small mutations: 1000/1000 valid; topology changes 0; p95 нормированного functional distance 6911 ppm. Это не гарантия viability.
- Остальные 8 операторов: 125 попыток каждого. Среди них 566 изменений topology signature; 44 крупных functional-effect proxy. Структурная безопасность не означает малый фенотипический эффект.
- Lab V2: 31 PASS, 0 FAIL; настоящий OpenGL Compatibility/Xvfb/llvmpipe viewport, 3 PNG. Application callback self-test, не независимый reviewer и не человеческое наблюдение.
- Старые VIS5.0–VIS5.5: 87/70/57/101/92/114 PASS, всего 521.

Шесть форм — authored genome programs для одного interpreter; они не объявлены естественно возникшими видами. Нормированные environmental channels и grants — research fixtures; A4+ world fields, полноценные survival/reproduction и distributed binding ещё не реализованы.

## Обязательное продолжение

1. Не начинать A4 и не объявлять A0–A3 закрытыми только по этому документу.
2. Сверить live HEAD, получить полный локальный patch/evidence A0–A3, проверить manifest и source hashes.
3. Разрешить внешний блок runtime-публикации штатным способом, без обхода safety/Actions; затем сохранить A2/A3 и финальное evidence обычными scoped commits.
4. Независимый Reviewer/Verifier на точном опубликованном subject; source/PC0 checks. Локальная проверка implementer не является independent acceptance.
5. Merge и изменение main-owned architecture/authority требуют отдельного разрешения; main и frozen VIS5 evidence здесь не изменялись.

Полный исходный отчёт R1 сохранён в передаваемом patch как исторический материал; его SHA-256: 4eb5664907ca5a55e5934b861794d77c673550a3e6d6657eb40a13bd431506e3. Сводка выводов и 22 ограничения уже находятся в `EVO_ARCH2_A0_RECONCILIATION_RU.md`.
