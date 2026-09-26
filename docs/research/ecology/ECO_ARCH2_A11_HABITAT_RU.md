# ECO ARCH2 A11 — видимый persistent evolving habitat

Статус: implementation candidate. Exact CI, независимые Review/Verifier и финальный merge — отдельные gates; этот документ не объявляет A11 CLOSED.

Work Order: [ECO_ARCH2_A11_WORK_ORDER_RU.md](ECO_ARCH2_A11_WORK_ORDER_RU.md).
Основа: main `6b336af8faeadbd7f69c96b62dc30d25150f45a7`, принятый A10.5 R2.

## Что запускается

`res://scenes/ecology/habitat/persistent_habitat.tscn` — самостоятельная исследовательская сцена над тем же `EcologyWorkbench` и `ExperimentController`, что использует Polygon. Workbench остаётся единственным tick driver; в host нет биологии, RNG, resource solver или своей популяции. `PersistentHabitatSession` владеет ссылкой на controller и транспортом checkpoint, а не вторым состоянием экологии.

Начальный опыт — FREE, wet/dry/dark, три размещения двух canonical геномов; одинаковый founder помещается в разные условия. Рост, ресурсное потребление, размножение, mutation receipt, смерть и mineralization принадлежат A3/A4/A5/A6. Камера, цвет зон, подписи, выбор и generic morphology — только представление.

В стартовой панели: Пуск, Пауза, Шаг, Быстро, выбор организма, inspector, переключение morphology, явный новый опыт, сохранение/восстановление. Полные исходные инструменты Polygon доступны отдельным переключателем; F2 возвращает панель habitat. Новая и восстановленная сессии стартуют на паузе.

## Запуск Windows (человеком)

PowerShell 7, из отдельного checkout/worktree **этой ветки**:

```powershell
.\RUN_ECO_A11_HABITAT.ps1
```

Launcher проверяет exact SHA и версию console binary, выполняет обязательный import и запускает именно эту сцену. Основной checkout сам не переключает. Путь можно явно передать через `-GodotBin`; неверный SHA не допускается.

Тесты:

```powershell
.\RUN_ECO_A11_HABITAT.ps1 -Test
```

Восстановление после полного закрытия приложения:

```powershell
.\RUN_ECO_A11_HABITAT.ps1 -ResumePath '<путь из save receipt>' -ExpectedSha256 '<SHA из доверенного save receipt>'
```

Передавать надо SHA, сохранённый пользователем/доверенным host **при исходном save**, а не хэш, заново вычисленный из потенциально изменённого файла. Аргументы path и SHA обязательны вместе. Invalid/corrupt save не превращается в новый опыт.

## Запуск Ubuntu/Linux (человеком)

Из отдельного checkout/worktree этой ветки:

```bash
(
  godot="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
  "$godot" --headless --editor --path . --import || exit
  "$godot" --path . res://scenes/ecology/habitat/persistent_habitat.tscn
)
```

Exact suite с проверкой binary version/SHA, import и HEAD/TREE:

```bash
python3 validation/ecology/evo_arch2_a11/run_exact.py --godot "$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
```

Автономный graphical agent использует managed Godot MCP согласно `docs/MCP_GODOT.md`, когда он доступен; headless checks не заменяют фактический визуальный просмотр.

## Persistent contract и владельцы

`persistent_habitat_session_v1.gd` хранит versioned transport envelope: manifest + founder registry + **существующий** текст shared-runtime checkpoint и его checksum. Биологический формат не дублируется; принятие состояния делает `ecology_runtime_checkpoint_v1.gd` через controller.load_state.

Перед decoding проверяется caller-owned SHA всего transport. Он связывает одновременно manifest, registry, runtime checkpoint и opaque WORLD_COMPAT envelope. Самоподпись внутри файла недостаточна. При неуспешном restore живой controller не заменяется.

Default visible host работает как LAB. WORLD_COMPAT в session API требует явных A10 dependencies; для restore нужен свежий, независимо сконфигурированный world adapter, не adapter активной сессии. Freshness/ownership актуальной production Region остаётся обязанностью canonical A10 authority — save не даёт права оживить старого owner. Ни production activation, ни второй Region/Matter owner в A11 не вводятся.

Прямой `apply_field_patch()` для WORLD_COMPAT проверяет тот же exact configured manifest, что initialize, и authority до owner-write. Новый zone stock или signal не может неявно перенастроить world adapter. LAB experimental patches остаются доступны.

## Disk contract / границы гарантии

Save создаёт immutable content-addressed `<sha256>.eco.json`, возвращает receipt с path/SHA/tick/state hash. По умолчанию каталог `user://eco-a11/checkpoints`; диагностические логи — только `artifacts/`. Повторный save идентичного состояния идемпотентен. Проверяются полная запись и hash временного файла до rename. Truncated/temp файлы не выбираются для restore. Ранее созданный checkpoint не перезаписывается и не удаляется при ошибке.

Ограничения явные: canonical transport до 2 MiB, не более 64 сохранений в каталоге, preset horizon 1–4096 (default 256). Quota/size failure останавливает автосохранение/проигрывание с ошибкой; нет скрытого удаления истории. Rename/flush дают защиту от неполного application-write, но не являются обещанием fsync-гарантии при физической потере питания или защитой от враждебной файловой системы.

## Доказательства, которые должен получить gate

| Тест | Проверяемое поведение |
|---|---|
| `test_persistent_session.gd` | deterministic export; wrong/missing SHA; fully rehashed substitution; invalid manifest/registry/state; failed restore atomic; immutable disk collision; truncated/missing file; resumed continuation |
| `test_world_admission.gd` | direct stock/signal bypass rejected; WARM cannot execute; runtime/manifest/cursor unchanged after rejection; full WORLD envelope; Matter replay after restore idempotent |
| `test_habitat_scene.gd` | реальный Workbench instance; один controller; UI step == canonical step; morphology/LOD noncausal; scene save/restore; CLI restore fail-closed; autosave |
| `test_habitat_lifecycle.gd` | реальное наследование мутации, расход ресурсов, рост, starvation→corpse→mineralization; checkpoint этих состояний; bounded 256 ticks + midpoint restore |
| `habitat_restart_worker.gd` + `run_exact.py` | четыре отдельных процесса: uninterrupted baseline, checkpoint, resume, negative anchor; state/field/population/presentation/metrics equality |

256-tick fixture использует явно неразмножающийся canonical genotype для изолированной проверки длительности и persistence. Это **не** доказательство свободного многопоколенного масштабирования до 256 тактов. Mutation-enabled FREE доказательство отдельное и ограниченное. `MAX_POPULATION=128`, `MAX_CORPSES=128` и parent-proof bounds сохранены; они не повышены и не обходятся скрытым culling. Следующая масштабная задача должна менять версионированные canonical contracts с собственными доказательствами.

Runner хранит собственные HEAD/TREE до/после, version/SHA реально запущенного Godot, command/PID/exit/timing, per-test counts и SHA логов, cross-process result и `evidence.json` + checksum. Ни `queued`, ни `running`, ни одно только exit=0 не является PASS: обязательны completion markers и ноль assertion failures. Автоматических повторов «до зелёного» нет.

## A10.5 documentation errata, действующие для A11

P0-описания в старых owner/architecture документах являются историческими. Для текущего composed runtime:

- `Field bounds`: stocks/capacities controller привязаны к явному `ExperimentManifest.CELL_CAPACITY_MG = 1_000_000`, а не к широкому `A4.MAX_CELL_STOCK = 1_000_000_000`. Нельзя менять normalization воды через этот широкий type limit.
- Реальный `EcologyWorkbench.setup(deps)` принимает `{controller, founder_registry, zone_color_provider?}`. Старый skeleton `{world_adapter, environment_source, snapshot_sink, clock}` не является реализованным контрактом.
- A5/A6 trajectory принадлежит `ecology_runtime_v1.gd`; persistence — `ecology_runtime_checkpoint_v1.gd`. Старый A8 observatory seam не заменяется и не используется как второй state owner.

## Acceptance boundary

Implementer evidence проверяет выполнение конкретного frozen subject. Independent whole-diff Reviewer и fresh Windows/Linux Verifier, post-build critique, Project Control и разрешение merge остаются отдельными требованиями. Визуальная читабельность, ручное использование и production integration не объявляются проверенными только потому, что headless suite зелёная.
