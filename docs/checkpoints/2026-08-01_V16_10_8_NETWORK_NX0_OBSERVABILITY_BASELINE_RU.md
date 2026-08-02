# Checkpoint v16.10.8 — Network NX0 Observability Baseline

## Решение

Подготовлен implementation candidate полноценного NX0 поверх принятого `v16.10.7-network-nx0-observability-preparation` (`fix1`) на базе commit `69bd7fc`.

```text
checkpoint: v16.10.8-network-nx0-observability-baseline
build_id: nx0-observability-baseline
branch: feature/nx0-observability-baseline
status: CANDIDATE
```

## Реализовано

- обязательный fingerprint handshake после ENet connect и до gameplay `JOIN`;
- deterministic mismatch codes для build, commit, protocol, world и public session binding;
- идемпотентный replay совместимого `COMPATIBILITY_HELLO`;
- protocol manifest и SHA-256 protocol hash в launch/runtime descriptor;
- bounded JSON-safe telemetry на transport boundary;
- фактические ENet packet bytes, channel/mode, RTT, RTT variance и packet loss;
- server/client runtime latency, message age, queue, handshake и persistence metrics;
- единый публичный session binding в M7 launcher scripts;
- contract, integration и настоящий ENet mismatch/acceptance process-test.

## Инварианты

- сервер остаётся единственным gameplay authority;
- handshake не изменяет `NetworkedGameplayService` state;
- несовместимый peer не может вызвать `JOIN`;
- observability sample не содержит raw credentials;
- `session_token` принимает только `session-id/<public-id>` либо `sha256/<64-lowercase-hex>`;
- M7 movement, snapshot amplification, три ENet-канала и persistence cadence 1500 ms сохранены;
- NX1, NX2, NX3 и prediction не реализуются преждевременно.

## Проверка implementation candidate

```text
Focused NX0:                         4/4 PASS
Preparation contracts:              115 assertions
NX0 baseline contracts:             150 assertions
NX0 real ENet handshake:             31 assertions, 0 failures

Network non-process regression:      48/48 PASS
ENet process regression:              4/4 PASS
  T1 multi-peer:                     20 assertions
  N1 snapshots:                      28 assertions
  N1 remote Item Graph commands:     51 assertions
  N1 reconnect/replay:               67 assertions

M3 graphical multiplayer:            56 assertions, 0 failures
M7 playable network:                 34 assertions, 0 failures
M7 restart/reconnect recovery:       36 assertions, 0 failures

git diff --check:                    PASS
JSON validation:                     PASS
Shell syntax:                        PASS
```

PowerShell focused-runner статически проверен, но не выполнялся в Linux-окружении из-за отсутствия `pwsh`. Godot-тесты выполнялись предоставленной проектом сборкой Godot `4.7.1.stable.double.custom_build.a13da4feb` через контролируемые shell-процессы; `godot_run_managed` в текущей среде отсутствует.

## Известные предупреждения test harness

Одновременные графические клиенты могут печатать неблокирующее предупреждение `breakpoint_runtime` о занятом локальном порте `9081`, а X11 — `NO GRAB`. Они существовали до NX0, не меняют результат process-tests и не являются сетевыми runtime failures.

## Следующий этап после независимой приёмки

```text
NX1 — Deterministic Network Condition Simulator
```

NX1 не должен одновременно менять traffic flow. Устранение amplification и разделение realtime-каналов остаются отдельным NX2 checkpoint.
