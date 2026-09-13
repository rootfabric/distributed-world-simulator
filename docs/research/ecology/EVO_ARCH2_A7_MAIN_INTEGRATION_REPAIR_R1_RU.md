# EVO ARCH2 A7 — Main Integration Repair R1

Дата: 2026-09-13. Work Order: `EVO-ARCH2-A7-MAIN-INTEGRATION-20260913-R1`.

## Finding

Hosted static preflight `34732668117` подтвердил addition-only transfer, exact transfer trees/blobs и current-main ancestry, но затем завершился FAIL на проверке всех `res://` ссылок:

```text
MISSING scripts/research/ecology/v2/legacy_genome_adapter_v1.gd
     -> scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd
TRANSITIVE_RES_PATH_MISSING
```

Это реальная транзитивная зависимость принятого A7 closure, не дефект current main и не основание ослабить preflight.

## Repair

Добавляется ровно один внешний accepted dependency:

```text
scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd
blob = 99e2076c959f1841f7b3211eaffbbe7ed80fa495
source = accepted A7 8eccf6304078bec3a3ccaa5860c5aab6ee311209
```

На `main@7dfc68ab...` этот path отсутствует. Файл side-effect-free/research-only и не содержит `preload/load res://` зависимостей, поэтому не расширяет closure дальше. Он переносится byte-exact через Git blob, не переписывается вручную.

Work Order, transfer manifest и integration verifier должны явно включить этот path. После repair требуется новый frozen HEAD/TREE, новый static preflight, новый full exact verifier и fresh independent review. Старые queued/running проверки на `5b460979...` после изменения source считаются stale и не могут поддержать merge-ready verdict.

Production/network/simulation/control/architecture ownership, `project.godot`, accepted research source и main не меняются. Merge остаётся human gate.
