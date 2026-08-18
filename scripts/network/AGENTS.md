# Network Runtime — Scoped Agent Instructions

Этот файл действует для `scripts/network/**` дополнительно к root `AGENTS.md` и canonical Project Control.

## Mandatory additional read

Перед изменением network runtime обязательно прочитать:

```text
docs/control/NETWORK_FRAMEWORK_READY_DEVELOPMENT_POLICY_RU.md
```

Эта policy не открывает отдельный framework roadmap и не расширяет текущий Work Order.

## Scope priority

Порядок приоритетов:

```text
canonical Project Control / approved Work Order
        >
existing accepted network invariants
        >
framework-readiness guidance
```

Framework-readiness не является причиной задерживать текущую задачу или выполнять массовый refactor.

## Dependency direction

Для нового generic network code придерживаться направления:

```text
simulator domain -> adapters -> scripts/network
```

Не добавлять без технической необходимости обратную зависимость:

```text
scripts/network -> simulator gameplay domain
```

Если алгоритму не нужно знать о конкретном gameplay domain, он должен оставаться generic.

## Core ownership rule

Network runtime может владеть semantics identity, authority, epochs, operations, routing, handoff, replication, projection sequencing, recovery, transport abstraction, observability и fault handling.

Network runtime не должен становиться владельцем Item Graph contents, inventory, Matter, Construction, Ecology или других gameplay semantics.

Не создавать:

- второй gameplay truth;
- второй Item Graph;
- параллельную authority model;
- transport-specific fork canonical gameplay semantics.

## New code classification

Перед добавлением существенного компонента определить, является ли он:

```text
GENERIC NETWORK CORE
SIMULATOR ADAPTER
RESEARCH / EXPERIMENT HARNESS
TEST / VALIDATION INFRASTRUCTURE
```

Generic core по возможности остаётся в `scripts/network/`. Simulator-specific knowledge должно оставаться в adapter/domain layer, если текущий Work Order не требует иного.

## Generic contracts

Для новых canonical network contracts по возможности сохранять:

- explicit schema/version;
- exact validation;
- deterministic serialization/hash;
- explicit authority epoch and state revision;
- replay-safe operation identity;
- fail-closed deterministic error codes.

Topology/authority/routing data в production core предпочтительно получать через configuration/provider/registry/directory, а не hardcode конкретного мира.

## No premature extraction

Без отдельного Work Order не создавать отдельный framework repository/package, не выполнять engine-neutral rewrite и не перестраивать принятые contracts только ради будущего reusable API.

## Reporting

Для MEDIUM+ network work в итоговом отчёте желательно добавить:

```text
Framework impact:
- generic core changed: YES/NO
- simulator adapter changed: YES/NO
- research-only code changed: YES/NO
- new simulator -> network dependency: ...
- new network -> simulator dependency: ...
```
