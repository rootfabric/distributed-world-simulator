# ECO P3.8 — Deterministic Ecosystem Persistence — ACCEPTED

Статус: `ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL`.

Дата: 2026-08-13.

## Frozen identity

```text
aggregate=6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
parent_p3_7=ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
checkpoint_sha256=1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367
final_state_hash=1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9
kernel=3d752f0d0a91fbbca5303b8ac7d49a8d8065c14e
test=e0cef778f69ddd78b3f7d7aba6c3e2b8b9eef51c
Godot=4.7.1.stable.double.custom_build.a13da4feb
```

Frozen full exact-Godot evidence: P3.7 parent regression PASS (64 assertions), P3.8 A/B/C PASS (52 assertions each; byte-identical), real cross-process writer generation 5 PASS, separate resume process 5→12 PASS с exact uninterrupted final state.

Свежий current-live-kernel smoke выполнен двумя отдельными process и дал byte-identical log SHA `18a21dfbc585326d971d88fda568d77e1a54ba84cef538c532ae73babfb03318`. Он повторно проверил typed binary roundtrip, byte-identical reserialization, cut 2+4 == uninterrupted 6 и реальный FileAccess save/load.

Windows PASS не заявляется. Это Human-directed attached-Godot canonical acceptance. P3.1..P3.8 теперь lifecycle-complete как research route. Production save ownership, distributed region ownership и server handoff этим checkpoint не авторизованы.
