# A11 R1 — post-build critique / execution handoff

Work Order: `ECO-ARCH2-A11-R1-WO-001`.
Branch: `feature/eco-arch2-a11-persistent-habitat-r1`; PR #693, DRAFT.
Base: `6b336af8faeadbd7f69c96b62dc30d25150f45a7` / `70ef1302b6e0fab6b4569778b18daf9757f6b493`.

**Это отчёт исполнителя, не independent review и не A11 acceptance.**

## Реализованный срез

| Predicate | Реализация | Состояние доказательства |
|---|---|---|
| P0 | bounded Work Order, official A11 scope reconciliation, owner boundaries | запись в ветке |
| P1 | WORLD_COMPAT direct field patch gate, включая side-effect-free отказ для ACTIVE no-op; LAB delta preserved | новые adversarial tests написаны; exact не получен |
| P2 | self-contained FREE wet/dry/dark preset из canonical founder genomes | validation/evolution tests написаны |
| P3 | transport существующего shared checkpoint; external SHA; immutable bounded disk writes; atomic failed restore | tests на rehash/truncation/registry/manifest/path/quota написаны |
| P4 | существующий Workbench + persistent habitat scene + time/selection/inspector/save/resume UI | headless scene tests написаны; визуальный просмотр не выполнен |
| P5 | отдельные baseline/checkpoint/resume/reject процессы; WORLD_COMPAT envelope и current-owner admission | worker/runner и composition tests написаны; execution pending |
| P6 | реальные mutation/growth/death tests; отдельный 256-tick non-reproductive continuation case | runtime result pending; масштабирование не заявлено |
| P7 | pinned exact Windows/Linux workflow, A10.5 regression route, auxiliary syntax, Project Control | closure pending |

Последний runtime/test delta до этой записи: `4072f959190a68c18564f58f94d845624dac02ca`.
Последний exact-workflow delta: `1d6332e6c34a29b5d1789d315832556da6cf4b2e`.
Guide alignment: `14ded5a6f82c0c884d9c6062d2a6803161f11e27`.
Финальный subject — актуальный HEAD этой ветки, его необходимо независимо получить из Git и записать вместе с TREE перед каждым exact run. Нельзя приписывать ему machine PASS другого HEAD.

## Принятые архитектурные решения

1. Одна live trajectory принадлежит существующему `ExperimentController`/`EcologyRuntimeV1`. Host не тикает биологию; единственный tick driver — Workbench. Session хранит ссылку и transport, не собственную population/field.
2. Checkpoint runtime-format не дублируется. Transport связывает immutable experiment inputs и штатный checkpoint внешним SHA; full rehash без доверенного caller anchor недостаточен.
3. Restore staged: live controller заменяется только после принятия полного checkpoint. WORLD restore дополнительно проверяет сохранённый cursor против текущего Region и не может оживить старого owner/epoch или заменить WARM historical ACTIVE состоянием.
4. Generic Realizer, inspector, time controls и advanced Polygon UI переиспользованы. Нового дерева классов биологии или species/archetype truth нет.
5. Canonical A3/A4/A5/A6 implementations не переписаны. В существующем controller изменена только admission-грань live environment patch; локальная переменная `set` переименована в `signals_result` без изменения вызова/ветвлений, чтобы grammar tooling не путал её с contextual keyword.

## Исправления, найденные исполнителем при собственной проверке

- При первом варианте world patch guard вызывал `admit_execution()`: даже no-op мог продвинуть world cursor. Исправлено на fail-closed live WORLD patch boundary без такого вызова; добавлены ACTIVE/WARM unchanged-state checks.
- Trusted historical checkpoint сам по себе не доказывает текущие world права. Добавлена pure A10 admission до import и проверки current context; negative controls включают successor owner/epoch и WARM.
- Возврат F2 не должен зависеть от автоматически сгенерированного имени PanelContainer. Панель теперь именована, переключение явное, состояние checkbox синхронизируется; добавлены scene tests.
- Сохранение в source tree через absolute/traversal path запрещено; fixtures изолированы в `artifacts/`.
- Дублирование push/PR exact jobs устранено: PR/manual dispatch используют одну branch-concurrency group.

## Наблюдавшиеся machine результаты

- Project Control на промежуточном `0ba8f2566b93e5a8438a3290688855579d3efe1d`: run `36204135748`, job `108296908274`, SUCCESS.
- Auxiliary Syntax на `1b86e341e2fc88435a8ead1cd6adcc47f023d72f`: run `36205328052`, SUCCESS. Проверены GDScript grammar, Python compilation и PowerShell parser. **Это не Godot type check и не runtime acceptance.**
- На момент составления записи A11 self-hosted exact jobs и A10.5 runtime regressions оставались queued/pending; ни один результат A11 runtime PASS не получен.
- Причина ожидания runner из доступных read-данных не установлена; нельзя объявлять runner offline или продукт faulty только по queued.
- В текущем container Git/PyPI DNS route недоступен. Повторных попыток Git clone или замены exact Godot на другой build для acceptance не делалось. Использован доступный GitHub connector и repository-owned CI.

## Не закрыто / обязательные проверки перед приёмкой

- Canonical Godot parsing/type resolution, все четыре A11 tests, четыре restart-worker процесса, реальные per-test counts/exit codes и hash-сверка continuation.
- Полные 15 A10.5 regression tests на новом subject, без изменения их assertions.
- Final exact-head Project Control и base/main drift check.
- Ручной/managed graphical просмотр: текст, расположение органов/mesh, панель, F2, pause/step и реальное save→закрытие→resume. Headless equality не доказывает визуальную читаемость.
- Fresh independent whole-diff Reviewer и fresh Verifier. Исполнитель их не заменяет.

## Честные ограничения

Default visible host — LAB research habitat, не promotion production ecology. WORLD_COMPAT session API требует caller-supplied текущих A10 dependencies. Данные старого save не являются источником актуальной Region authority.

256-tick case намеренно неразмножающийся; отдельно проверяются реальные наследование и размножение. Бесконечная многопоколенная эволюция, population-scale performance и автоматическое culling не реализованы и не заявлены.

Сохранены canonical population/corpse caps 128. Transport bound 2 MiB, storage quota 64 файлов: превышение явно останавливает работу, не стирает lineage/историю. Power-loss fsync-гарантия и враждебная файловая система вне этого среза.

Две doc-неточности A10.5 отражены как явные errata в A11 guide; исходные P0 документы не выдаются за актуальный API. Пересмотр population/corpse limits остаётся отдельным canonical-contract work order.

## Следующее точное действие

На доступном Windows или Linux host сделать чистый detached worktree актуального HEAD, проверить TREE и canonical Godot, затем выполнить `RUN_ECO_A11_HABITAT.ps1 -Test` либо `python3 validation/ecology/evo_arch2_a11/run_exact.py --godot <exact binary>`. Сохранить `artifacts/runtime/eco-a11/**`, выполнить A10.5 regression, обновить machine evidence. При реальном failure фиксировать первый error и делать минимальный repair с новым exact subject, не переименовывать pending в PASS.

Outcome: **IMPLEMENTATION_CANDIDATE / EXACT_EVIDENCE_PENDING**. PR остаётся draft, main не изменяется.
