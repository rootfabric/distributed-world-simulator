# Checkpoint candidate v16.10.7 — NX0 Observability Baseline Preparation

## Решение

Создан неинвазивный подготовительный checkpoint перед изменением realtime-netcode. Он фиксирует NX0–NX9, подтверждает текущие M7 traffic/timing проблемы и добавляет testable contracts для build fingerprint, telemetry и network-condition profiles.

## База

```text
base commit: 69bd7fc
base checkpoint: v16.10.6.1-testing-m7-playable-networked-playground
branch: feature/nx0-observability-baseline-preparation
build_id: nx0-observability-baseline-preparation
status: candidate
```

## Изменение поведения

```text
production M3/M7 runtime: unchanged
ENet adapter: unchanged
NetworkedGameplayService: unchanged
Item Graph: unchanged
persistence behavior: unchanged
```

## Новые элементы

- `config/network/network-experience-roadmap.v1.json`;
- `config/network/nx0-observability-baseline-preparation.v1.json`;
- `config/network/network-condition-presets.v1.json`;
- `network_build_fingerprint.gd`;
- `network_observability_sample.gd`;
- `network_telemetry_collector.gd`;
- `network_condition_profile.gd`;
- focused NX0 preparation test and runners;
- новая документация roadmap и integration map.

## Зафиксированные baseline defects

```text
packet-arrival delta drives movement step
successful PLAYER_INPUT emits result
successful PLAYER_INPUT emits delta + full snapshot
movement checkpoint interval = 1500 ms
nonblocking client accumulates async results
ENet v2 channel count = 3
```

## Следующий checkpoint

`v16.10.7-network-nx0-observability-baseline`:

- integrate fingerprint into launcher and pre-JOIN handshake;
- instrument transport, runtime and persistence;
- publish bounded samples;
- collect LOCAL baseline;
- do not change message flow until measurements are accepted.

## Review fix1

Закрыты замечания независимой проверки:

- telemetry collector сохраняет каждое наблюдение сразу после `append()`;
- `session_token` принимает только `session-id/<public-id>` либо `sha256/<64-lowercase-hex>`;
- PowerShell focused-runner больше не читает и не изменяет `$env:HOME`;
- добавлены негативные и ранние-window тесты, исключающие повторное появление дефектов.
