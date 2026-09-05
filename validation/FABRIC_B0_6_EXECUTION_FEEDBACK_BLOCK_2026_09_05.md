# FABRIC B0.6 — прерванное продолжение: отсутствие подтверждённых результатов инструментов

## Статус

`B0.6 = NOT_CLOSED`. Этот документ не является runtime evidence, reviewer verdict, verifier verdict или research acceptance.

## Последний подтверждённый снимок до попытки продолжения

- Branch: `research/fabric-bake0-6-adaptive-physical-fidelity-r1`.
- Observed HEAD: `1e8e74d6afafad294ddf10d68cb37efacc3ef3a1`.
- Observed TREE: `ca1d349f752f1cf5a36da8a24f5edaec18b90f4d`.
- Source-package commit: `949b089ed35750abf9e237f063af21490291d187`.
- Source-package workflow run: `33959719241`, ранее подтверждённый `success`; это упаковка исходников, а не Godot validation.

Эти SHA — исторический наблюдавшийся снимок, не утверждение об актуальном HEAD на момент чтения документа.

## Факты попытки продолжения

Были направлены команды проверки attachment, распаковки и запроса Godot version/SHA256, а также Git clone/status/fetch и чтения live branch через GitHub connector. Доступные ответы инструментов не предоставили пригодных для проверки результатов этих действий. Успех команд, фактический HEAD, чистота рабочего дерева и идентичность исполняемого Godot не подтверждены.

B0.6-B/C/D/E в этой попытке не реализованы. A–E acceptance runners, predecessor regressions и двукратный closure runner в этой попытке не запускались. Новые assertion counts, runtime hashes и PASS не заявляются.

## Обязательное продолжение

Восстановить канал исполнения с доступными stdout/stderr и exit codes; получить live Git state без reset; проверить приложенный canonical double Godot; прочитать актуальные main-owned и research-local правила; выполнить A → B → C → D → E, predecessor regressions и два независимых exact closure runs. Только реальные результаты могут обосновать CLOSED.

Ожидаемый, но не подтверждённый этой попыткой runtime:

- Version: `4.7.1.stable.double.custom_build.a13da4feb`.
- SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Git write permissions не объявляются отсутствующими: прежняя успешная запись через GitHub API уже доказана. Причина остановки — отсутствие подтверждаемой обратной связи от инструментов в данной попытке, не предполагаемый запрет Git и не project human merge gate.
