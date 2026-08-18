# Harness Snapshot R2

Этот branch фиксирует второй исторический snapshot системы разработки Distributed World Simulator.

```text
snapshot_id      HARNESS-SNAPSHOT-R2
snapshot_series  Distributed World Simulator Development Harness
source_branch    main
source_head      d9a1a3ca03016d6851a258ff93d5c260a86c5b4c
previous         HARNESS-SNAPSHOT-R1
previous_branch  control/harness-development-protocol-r1
previous_head    4b9e6c2c9428f59860368ccad6cf1a561f28206e
snapshot_branch  control/harness-development-snapshot-r2
captured_at      2026-08-18T12:16:00+10:00
```

R1 был первым protocol snapshot: он зафиксировал Project Epoch, Work Order, append-only events, scheduler, Git-only recovery и разделение ролей.

R2 является следующим snapshot той же линии. Он фиксирует уже зрелую систему: executable `CONTROL_DEVELOPMENT.ps1`, `scripts/harness/**`, event reducer/state builder, risk/review/evidence/repair layer, exact-head freshness, Human Attention, расширенный Project Control и реальные durable execution ledgers.

Snapshot branch не является новой продуктовой линией и не должен использоваться для дальнейшей разработки DWS. Exact продуктовый источник R2 — `main@d9a1a3ca03016d6851a258ff93d5c260a86c5b4c`; поверх него snapshot branch добавляет только metadata, описывающую происхождение и извлечение универсального Harness.

Подробная история и инструкция по выделению заготовки проекта:

`docs/control/HARNESS_SNAPSHOT_R2_RU.md`

Machine-readable manifest:

`config/control/harness/snapshot-manifest.v1.json`
