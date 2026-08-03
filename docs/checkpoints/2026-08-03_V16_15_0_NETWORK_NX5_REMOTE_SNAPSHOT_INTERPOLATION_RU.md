# Checkpoint v16.15.0 — NX5 Remote Snapshot Interpolation

```text
checkpoint: v16.15.0-network-nx5-remote-snapshot-interpolation
build_id:   nx5-remote-snapshot-interpolation
branch:     feature/nx5-remote-snapshot-interpolation
base:       v16.14.0-network-nx4-client-prediction-reconciliation / fix1
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- bounded server-tick timeline на каждого удалённого игрока;
- 100-мс interpolation delay;
- shortest-path yaw interpolation;
- bounded 100-мс velocity extrapolation и authoritative hold;
- out-of-order insertion, duplicate suppression и same-tick conflict fence;
- teleport/implied-speed discontinuity;
- ownership, authority и transport-session fencing;
- reconnect reset без интерполяции через разные эпохи;
- интеграция в существующий `RemotePlayerPresenter`;
- presentation telemetry в graphical world report через существующий presenter report;
- focused contract и integration runners.

## Не изменено

NX4 owner prediction/reconciliation, authoritative server fixed tick, canonical replica, Item Graph, persistence и wire contracts не изменены. Protocol hash наследуется от NX4 fix1.

## Обязательная приёмка

```text
RUN_NX5_REMOTE_SNAPSHOT_INTERPOLATION_TESTS
RUN_NX4_CLIENT_PREDICTION_RECONCILIATION_TESTS
RUN_NETWORK_CONTRACT_TESTS
RUN_WORLD_REGRESSION_TESTS
```

После независимого managed-MCP прогона checkpoint может получить решение `ACCEPTED`.
