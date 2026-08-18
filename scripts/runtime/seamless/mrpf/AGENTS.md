# MRPF research runtime — scoped agent instructions

Действует для `scripts/runtime/seamless/mrpf/**` дополнительно к root `AGENTS.md`, Project Control и конкретному H Design Brief.

## Mandatory reads for H1+

Перед изменением H1+ читать:

```text
docs/plans/MRPF_HIERARCHICAL_PROJECTION_STANDS_RU.md
docs/plans/MRPF_HIERARCHICAL_PROJECTION_STANDS_EXECUTION_RULES_RU.md
```

Для network/process work дополнительно использовать prospective framework-readiness donor:

```text
feature/sm0-two-authority-seamless-handoff-lab
@ 9acf8efb47895dff785265bcee55d51b1b33da0a

docs/control/NETWORK_FRAMEWORK_READY_DEVELOPMENT_POLICY_RU.md
scripts/network/AGENTS.md
```

Пока эта policy не интегрирована в canonical main, она является дополнительным H-line design constraint и не может переопределять main-owned Project Control.

## Casual-scale research rule

Earth/Moon/Space graphical fixtures не обязаны использовать реальные физические масштабы.

Допускается compact/casual geometry, если сохраняются проверяемые semantics:

```text
source isolation
route lifecycle
representation ancestry
coarse/fine replacement
revision fencing
fallback/reconnect
presentation != canonical truth
```

Нельзя выдавать casual fixture scale за изменение canonical world/spatial constants.

## Framework-readiness rule

H-line сейчас является research/evidence environment, а не framework extraction project.

Не выполнять массовый refactor только ради будущей библиотеки.

При выборе дизайна сохранять направление:

```text
scenario/domain fixture
        ↓
adapter
        ↓
generic-shaped route/transport/projection primitive
```

Generic-looking primitive не должен без необходимости зависеть от Earth/Moon, Item Graph, Construction, Matter, Ecology, inventory, resources или UI semantics.

Если алгоритму не нужно знать, что это Distributed World Simulator, по возможности не зашивать simulator-specific semantics в его boundary.

## Production boundary

Не переносить research helper в `scripts/network/` автоматически.

Promotion в generic network incubation boundary требует текущей capability/correctness причины или отдельного Work Order. Accepted H research является semantic/contract/evidence donor, а не автоматическим production merge source.

## Authority rule

Projection publisher не становится canonical authority из-за наличия route или более точного LOD.

```text
projection publisher != authority owner
presentation != canonical truth
```

Нельзя создавать второй canonical writer, второй authority model или второй gameplay truth.

## Transport rule

H1 допускает loopback UDP для process-isolation proof. Representation/composition semantics должны оставаться отделены от UDP-specific code настолько, насколько это можно сделать без увеличения scope.

## Reporting

Для H1+ всегда включать:

```text
Framework impact:
- generic core changed: YES/NO
- simulator adapter changed: YES/NO
- research-only code changed: YES/NO
- new simulator -> network dependency: ...
- new network -> simulator dependency: ...
```
