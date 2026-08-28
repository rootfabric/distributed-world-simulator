# V0 PLAYABLE SEAMLESS PLANET — progress snapshot R2

**Дата фиксации:** 2026-08-28  
**Назначение:** immutable human-readable baseline после закрытия SM1.7.12.  
**Canonical main на момент фиксации:** `e14f8b6e5b07709d18273cc7886fe660bc353ebf`.  
**Current SM1 implementation candidate:** `b270fb806038333c97fa1ed49655961adddd6a21`.

> Этот документ фиксирует наблюдаемое состояние веток и evidence. Он не заменяет machine truth в `config/control/**`, не принимает SM1 и не меняет runtime authority.

## 1. North Star

**V0 PLAYABLE SEAMLESS PLANET**

Минимальная пользовательская вертикаль остаётся:

```text
dedicated server
+ Gateway
+ Authority A
+ Authority B
+ 2 graphical clients
+ persistent shared world
+ seamless A <-> B crossing
+ bounded planetary surface
+ inventory / containers
+ equipment / tools
+ resource mining
+ real-resource Construction
+ authoritative terrain digging/material mutation
+ reconnect
+ server restart recovery
```

## 2. Accepted product foundation

- P4 Real Resource Construction — **ACCEPTED**
- P5 Equipment / Tools — **ACCEPTED**
- P6 Persistent Shared Outpost — **ACCEPTED**
- Edge Gateway Foundation — **ACCEPTED**

Mining, Item Graph, tools, Construction, persistence/reconnect/restart и Gateway не являются будущими новыми системами для North Star.

## 3. SM1 current exact candidate

Canonical runtime branch:

`feature/v0-sm1-seamless-product-integration`

Exact implementation HEAD:

`b270fb806038333c97fa1ed49655961adddd6a21`

Tree:

`45c4a684642abaeea23a7b2bd0bbc9a8f507628a`

PR #242: **OPEN / DRAFT / NOT MERGED**.

SM1.7.12 repeated crossings under impaired network закрыт:

```text
SM1.7.12                70 x 10 = 700 PASS
SM1 L0                        339/339 PASS
SM1.6 graphical                58/58 PASS
SM1.7.1-7.6                   157/157 PASS
SM1.7.7                        79/79 PASS
SM1.7.8                        71/71 PASS
SM1.7.9                        81/81 PASS
SM1.7.10                       89/89 PASS
SM1.7.11                      145/145 PASS
Project Control #1439                 SUCCESS
checkout                              CLEAN
```

Durable PR evidence: PR #242 comment `#5448550294`.

**SM1.7.12 = IMPLEMENTED / EXACT-HEAD EXECUTABLE PASS.**

Это всё ещё не равно checkpoint acceptance.

## 4. Current critical-path position

SM1 feature implementation по текущему плану закончена. Текущая точка:

```text
B1 SM1.7.12 impaired-network repeated crossings    DONE
→ B2 full world/core regression                     CURRENT
→ B3 post-build critique
→ B4 Evidence Map
→ B5 fresh exact-head Reviewer
→ B6 fresh Verifier
→ B7 checkpoint proposal
→ B8 human RUNTIME_FEATURE_MERGE
→ SM1 ACCEPTED
→ P7 BOUNDED TERRAIN MUTATION
→ North Star graphical acceptance
```

P7 runtime нельзя активировать до formal SM1 acceptance и main-owned successor activation.

## 5. Pre-P7 seamless smoke demo

Отдельный **ручной smoke/demo бесшовности без terrain mutation** технически можно собирать уже на SM1-кандидате, потому что runtime уже содержит:

- отдельные Authority A и Authority B processes;
- отдельный Gateway process;
- graphical client process;
- networked A->B->A route pivot;
- stable client Gateway endpoint;
- no reconnect / no respawn при normal crossing;
- repeated crossings и impaired-network evidence.

Текущий `sm1_6_graphical_client.gd` пока **script-driven**, а не ручной WASD-клиент: он сам отправляет ACTION/MOVE sequence. Поэтому reusable tester demo требует тонкого presentation/input wrapper, но не нового seamless protocol.

Рекомендуемая граница:

```text
SM1 exact candidate
→ full world/core regression
→ package MANUAL_SEAMLESS_SMOKE_DEMO
→ run human smoke
→ continue formal Reviewer/Verifier closure
```

Такой demo не является checkpoint acceptance и не должен менять canonical ownership.

Минимальный сценарий demo:

```text
start Authority A
start Authority B
start Gateway
start graphical client
connect only to Gateway
walk from A-owned area into B-owned area
observe authority A -> B without loading/reconnect/respawn
walk back B -> A
repeat several times
```

Terrain digging не нужен. Для demo достаточно простого bounded floor/strip с визуально отмеченной authority boundary.

## 6. Remaining gameplay capability to North Star

После SM1 основной отсутствующий capability:

**P7 bounded authoritative terrain/material mutation**

```text
equipped tool
→ dig
→ authoritative terrain mutation
→ material yield
→ canonical Item Graph
→ two-client convergence
→ persistence
→ reconnect/restart
→ mutation across A/B seam
```

## 7. Updated navigation estimate

После закрытия 7.12 функциональная оценка до V0 PLAYABLE SEAMLESS PLANET остаётся порядка **~81-82%**.

Это navigation metric, а не Harness acceptance truth. Основной оставшийся engineering risk сосредоточен в P7 terrain authority/persistence/seam integration.

## 8. Next progress review

Проверить:

1. завершён ли full world/core regression;
2. собран ли manual seamless smoke demo;
3. завершены ли critique + Evidence Map;
4. есть ли fresh Reviewer PASS;
5. есть ли fresh Verifier PASS;
6. принят ли SM1 и какой exact accepted head;
7. активирован ли P7;
8. работает ли terrain mutation/persistence/seam continuity;
9. достигнут ли V0 PLAYABLE SEAMLESS PLANET.
