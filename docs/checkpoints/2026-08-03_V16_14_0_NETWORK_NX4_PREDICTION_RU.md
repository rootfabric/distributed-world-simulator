# Checkpoint v16.14.0 — NX4 Client Prediction and Reconciliation

```text
checkpoint: v16.14.0-network-nx4-client-prediction-reconciliation
build_id: nx4-client-prediction-reconciliation
branch: feature/nx4-client-prediction-reconciliation
base: accepted v16.13.0 NX3
status: candidate
```

NX4 добавляет owner prediction поверх server-authoritative fixed tick NX3. Клиент немедленно симулирует локального игрока общим `PlayerMovementService`, хранит bounded tick history и после authoritative snapshot выполняет baseline reset и replay неподтверждённых тиков.

Критические инварианты:

- сервер остаётся authority;
- transform от клиента не принимается;
- клиентский `delta_seconds` не используется сервером;
- prediction и authority используют один fixed movement kernel;
- local CharacterBody physics не дублирует prediction;
- correction smoothing применяется только presentation-слою;
- history, replay и sequence wrap ограничены и наблюдаемы;
- snapshot вне prediction ring вызывает безопасный authoritative reset без частичного replay;
- NX2 traffic separation и NX3 fixed tick сохраняются.

Focused gate: `RUN_NX4_CLIENT_PREDICTION_RECONCILIATION_TESTS.ps1/.sh`, 13 шагов.
