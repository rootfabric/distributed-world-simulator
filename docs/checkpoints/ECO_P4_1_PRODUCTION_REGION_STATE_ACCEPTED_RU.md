# ECO P4.1 — Production Ecology Region State — ACCEPTED

Статус: `ACCEPTED / EXACT ATTACHED GODOT / FULL COMMITTED P3.1→P4.1 CHAIN PASS`.

Source candidate head: `2744ff5ad40bd84b90c7285fe49adc4c88035c52`.

Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

## Что принято

P4.1 фиксирует production-facing `EcologyRegionState`: canonical `region_id`, exact ecology generation, `last_simulated_world_time`, accepted P3.8 ancestry, deep-copied validated P3.8 semantic state и independent `region_state_hash`.

P4.1 не владеет scheduler/catch-up, storage, server handoff или network replication. Эти обязанности остаются последующим P4 stages.

## Exact full-chain evidence

Перед runtime запуском P3.1–P3.8 kernels, P4.1 kernel и P4.1 acceptance test были реконструированы из GitHub и каждый файл проверен byte-for-byte по Git blob SHA.

Parser/preload: `PASS`.

Fresh-process runtime: `PASS x3`, `52 assertions` в каждом процессе; логи A/B/C byte-identical.

```text
aggregate_hash=1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717
region_zero_hash=2d7fc8f595dbe5e55e29a0dca1256a9f4ccebe4176ec8d53c9bf66671ac3b7b4
region_cut_hash=fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c
other_region_hash=d4f0cd4890678747ef2f2399bcfd500282a3840af43ea37913ee78c39b17c3e5
parent_p3_8=6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
```

Fresh runtime log SHA-256: `2e7f7efaad505cc126b9ccbc614ecc6b6fe550acbb6867584faf602f807f0566`.

Fixture также воспроизвёл frozen P3.8 semantic identities:

```text
generation_0=6070494e77828f4e25a00eed9695de9e87fdf94e472f5018d660a7c20b15d7fb
generation_5=07f6ecaa00d508b87042948a23cf4e0eaa600d79a8229e16b859c461dada509d
```

## Решение

`P4.1 ACCEPTED`.

`P4.2 Deterministic Ecology Clock` открыт для реализации.
