# Checkpoint candidate: v16.10.5-persistence-m6-dedicated-recovery

## Identity

```text
checkpoint: v16.10.5-persistence-m6-dedicated-recovery
build_id: m6-dedicated-persistence-recovery
base: v16.10.4-testing-m5-graphical-multiplayer-acceptance
branch: feature/m6-dedicated-recovery
status: candidate
architecture debt: A2-D04 candidate closure
```

## Реализовано

M6 подключает R3.1 authoritative checkpoint repository к production dedicated gameplay runtime. Durable checkpoint включает player registry, ownership epochs, gameplay revision/tick, canonical M4 Item Graph, operation ledgers и committed result outbox.

Ключевой контракт: replay-durable authoritative result подтверждается клиенту только после atomic checkpoint. Предварительные malformed/transport/ownership отказы не мутируют домен и не создают checkpoint. Ошибка persistence переводит server в fail-stop и запрещает поздний final checkpoint неподтверждённого состояния.

Recovery восстанавливает стабильные player entities, координаты, inventory/hotbar/container/mount state и replay identity. Transport sessions и transient UI access не восстанавливаются. Reconnect создаёт новую session и ownership epoch, а exact replay старой committed операции возвращается без повторной мутации.

## Тесты кандидата

```text
M6 contracts:
  tests/runtime/test_m6_dedicated_recovery_contracts.gd

M6 crash/restart processes:
  tests/runtime/test_m6_dedicated_recovery_processes.gd

Focused runners:
  RUN_M6_DEDICATED_RECOVERY_TESTS.ps1
  RUN_M6_DEDICATED_RECOVERY_TESTS.sh
```

Process acceptance доказывает:

- один dedicated server и два одновременных клиента;
- durable seed state и unique Item Graph identities;
- hard kill без graceful shutdown;
- replacement server из того же ACTIVE checkpoint;
- прежние player entities и ownership epoch 1 в storage;
- disconnected transport state после recovery;
- reconnect обоих игроков с epoch 2;
- replay операции, committed до crash, с явным `replay=true`;
- отсутствие второго checkpoint, outbox record и Item Graph mutation при replay;
- продолжение movement и graceful leaves после recovery;
- отсутствие parse/compile errors, replay conflicts и resource leaks.

## Выполненная проверка кандидата

На Linux double-precision сборке `Godot 4.7.1 stable.double` (`a13da4feb`) получено:

```text
Focused M6:       10/10 PASS
M6 contracts:     118 assertions, 0 failures
M6 processes:     124 assertions, 0 failures
Network/runtime:  59/59 PASS
World regression: 104/104 PASS
Editor import:    PASS
Main scene:       PASS
```

## Решение

Checkpoint остаётся кандидатом до независимого локального прогона теми же командами:

```powershell
.\RUN_M6_DEDICATED_RECOVERY_TESTS.ps1 -GodotPath $Godot
.\RUN_NETWORK_CONTRACT_TESTS.ps1 -GodotPath $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1 -GodotPath $Godot
```

После зелёной независимой проверки:

```text
decision: ACCEPTED
A2-D04: CLOSED
next: v16.10.6-architecture-a3-single-server-multiplayer
```
