# INT0 — текущий статус интеграции

**Обновлено:** 2026-08-03 21:00 UTC+10  
**Основной план:** `docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md`  
**Machine-readable manifest:** `validation/int0-three-domain-frozen-heads.json`

## Где мы сейчас

```text
NX6 candidate in integration: YES
RL3/MW10 composed candidate in integration: YES
C24 staged candidate: YES
C24 merged into integration: NO
Active stage: INT0 COMBINED RUNTIME GATE
Status: THREE-DOMAIN COMPOSED CANDIDATE, NOT ACCEPTED
Main changed: NO
```

## Сохранённые точки

```text
backup/main-before-int0-20260803
→ 69bd7fc7fde2bc0824b0d608451ecd310397b8d2

backup/int0-before-rl3-integration-20260803
→ 218e44fcdb5b0574a7931003dbc1952bed7aadff

checkpoint/int0-rl3-mw10-composed-candidate
→ fcf1a1d121e90afc05f6fd810656a5f8d32868c4

checkpoint/int0-nx6-rl3-composed-candidate
→ 64770c62574de58fa522dbdf2b4be891fe00442c

checkpoint/int0-c24-staged-candidate
→ 989cd87a53d10b307f1cd9a3a22bae207995637e

checkpoint/int0-three-domain-composed-candidate
→ 374f79168749278c51814bccded81eb70787d767
```

## Доменная история

### NX6

```text
frozen head:       144adf35cd2151ce5f8572dbbb8ed1b58ccd9778
staging PR:        #4
integration PR:    #5
integration merge: 312a0b12e5ddb78a2e67ada0b36385c84ed10854
status:            DONE CANDIDATE
```

### RL3/MW10

```text
frozen head:       89ff51b3ee5f66f6548f8b97e271062daf09b5cf
resolution PR:     #7
staging merge:     515b179d276c59df1624fe640eb04464410bf974
composition:       ba1127ab24c4af0493d7445539387b9e9fee219a
integration PR:    #8
integration merge: 60feb1cbc07a6617e498d65efcc9f747f68eaff7
status:            COMPOSED CANDIDATE, NOT ACCEPTED
```

### C24

```text
frozen head:       c18b3afaf0f2f078899be20d0529fa94d53adf90
source PR:         #9
staging merge:     00ae523ac85c575424d84a49b48fa4be37bcbf3a
composition docs:  007dcc70645519a85ba0f12e4c7073584b7b4907
validation plan:   374f79168749278c51814bccded81eb70787d767
integration PR:    #10 — OPEN / DRAFT / MERGEABLE
status:            STAGED CANDIDATE
```

## C24 merge-аудит

C24 добавляет 863 пути относительно NX6+RL3 integration-базы:

```text
new paths:      862
modified paths: 1
removed paths:  0
text conflicts: 0
```

Единственный изменённый существующий файл:

```text
RUN_WORLD_REGRESSION_TESTS.ps1
```

В него аддитивно добавлены 57 C1–C24 тестов. Существующие Network, Matter, Representation, World и runtime entries не удалены.

C24 не изменяет:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/items/presentation/item_gameplay_controller.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
scripts/app/simulator_app.gd
scripts/world/testing/playground_runtime.gd
AGENTS.md
PROJECT_MANIFEST.txt
README_RU.md
```

Следовательно, C24 не перезаписывает NX6/RL3 runtime-композицию. Construction proxy meshes остаются derived presentation artifacts.

## Единый INT0 runner

В `merge/int0-c24` добавлены:

```text
RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.ps1
RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.sh
```

Профили:

```text
focused:
editor import
INT0 RL3 composition
NX6
MW10
RL3
C24
static checks

full:
focused + M7 + MW8 + MW9 recovery/race + RL2 +
C2B + C9 + C22 + C23 + Network full + World full
```

Итоговый machine-readable отчёт:

```text
artifacts/test-results/int0-three-domain-integration-summary.json
```

Runner также выполняет:

- `git diff --check`;
- conflict-marker scan;
- проверку отсутствия оставшихся Godot процессов.

## Что уже доказано

```text
all frozen heads unchanged: PASS
NX6 merge chain: PASS
RL3 conflict resolution: PASS
RL3 isolated Godot syntax fixture: PASS
C24 GitHub merge: PASS
C24 text conflicts: 0
C24 shared runtime changes: 0
unified runner files created: PASS
```

## Что ещё не запускалось на полном composed tree

```text
unified focused profile
unified full profile
Godot editor import
NX0–NX6 + M7
MW0–MW10 + RL0–RL3
C1–C24
World regression with 57 construction tests
main scene CLI
combined two-client Matter + construction proxy scenario
```

Поэтому текущий checkpoint — только `COMPOSED CANDIDATE`, не `ACCEPTED`.

## Следующая операция

На полном checkout ветки:

```text
merge/int0-c24
```

запустить:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.ps1 -Profile focused
.\RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.ps1 -Profile full
```

или Linux:

```bash
./RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.sh /path/to/godot.linuxbsd.editor.double.x86_64 focused
./RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.sh /path/to/godot.linuxbsd.editor.double.x86_64 full
```

После полного PASS:

```text
1. записать фактические результаты в validation;
2. перевести PR #10 из draft;
3. merge PR #10 методом merge commit;
4. выполнить финальный combined smoke на integration head;
5. оформить v18.0.0 INT0 candidate checkpoint;
6. провести независимую приёмку;
7. только после ACCEPTED открыть integration → main.
```

## Запрещено

- не менять `main` до независимого INT0 acceptance;
- не сливать PR №10 без полного общего gate;
- не утверждать ACCEPTED по исходным доменным тестам;
- не выполнять squash/rebase/force-push;
- не превращать construction или representation artifacts в canonical state;
- не скрывать отсутствующие runtime-прогоны.
