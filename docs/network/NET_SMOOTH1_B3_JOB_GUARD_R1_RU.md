# NET-SMOOTH1 — B3: владение процессами через Windows Job Object

## Основание и точная граница изменения

База инструментов: #816, HEAD `7dbc611e6f99328e911ea24a83df625ac537ac2c`, TREE `184706402434f94f178be8291dd96526cf48b295`. Проверенный PRODUCT_HEAD #814 остаётся `fdfbfb3b8dff911e6fd081a157652a28e1052cff`. Ни продукт, ни `run_net_smooth1.py`, ни `owned_process_cleanup.py`, ни нормативный анализатор здесь не меняются. Новая оболочка вызывается явно и не становится частью обычного запуска автоматически.

Полученный от Windows-оператора offline-отчёт: capture объясняет лишь 6.9–26% p99-хвоста, а p99 без capture 25.60–27.43 мс всё равно нарушает 25 мс. Худшие кадры часто содержат реальный server_loop (message 48.8, snapshot 27.5, persistence 25.2 мс). UNRESOLVED в top100 — 0. Единичные 93–125 мс uncovered — не доказательство OS sleep. **Не повышать FPS cap, не убирать валидацию и не считать checkpoint единственной причиной.**

Для B3 оба старых pair3 manifest сообщили `cleanup.verified=true`, хотя два процесса оставались. Creation time и команды погибших/убитых вручную процессов не сохранены. Это недостаток доказательств, а не установленная причина утечки. Текущие чужие evo_arch2/r32 процессы не принадлежат NET-SMOOTH1 и не должны завершаться.

## Реализация

`win_job_guard.py` использует один неназванный, не наследуемый Job Object на запуск. `CreateProcessW` получает `PROC_THREAD_ATTRIBUTE_JOB_LIST`, то есть членство задаётся при создании процесса, а не после гонки CreateProcess/Assign. `CREATE_SUSPENDED` позволяет записать реальный executable, creation FILETIME и PID по handle до первого пользовательского кода. Только stdin/stdout унаследованы через HANDLE_LIST; handle Job не передаётся потомкам. Никаких CPU, affinity, memory или priority ограничений не устанавливается.

Job содержит **runner и его обычных CreateProcess-потомков**, включая console-wrapper и main Godot. `KILL_ON_JOB_CLOSE` — аварийная страховка при смерти управляющего процесса. Никакого поиска чужих процессов и `taskkill /IM`. Для доказательства пустоты проверяются и `ActiveProcesses`, и полный PID list. При необходимости завершается только этот Job, но принудительная очистка делает текущую попытку `FORCED_CLEANUP_NOT_ACCEPTED`, даже если после неё Job пуст. Ошибки API, query или неподдерживаемая конфигурация не заменяются обычным незащищённым запуском.

Системные брокеры/WMI, создающие процесс не обычным наследованием CreateProcess, требуют отдельной проверки; этот механизм не доказывает причину исторической утечки. Работа с настоящей Godot-обёрткой ещё должна быть подтверждена коротким Windows smoke. Новый JSON не переписывает manifest или report старого runner и никогда не выдаёт игровой PERF_PASS.

## Проверки: сначала без Godot

```powershell
$env:R31_JOB_NATIVE_EVIDENCE = 'C:\EVIDENCE\B3-job-native-' + (Get-Date -Format yyyyMMdd-HHmmss)
python -m unittest discover -s tests/tools -p 'test_r31_job_guard_portable.py' -v
python -m unittest discover -s tests/tools -p 'test_r31_job_guard_native.py' -v
Remove-Item Env:R31_JOB_NATIVE_EVIDENCE
```

14 переносимых проверок и 7 настоящих Windows-тестов: членство до resume; wrapper завершился, ребёнок и внук живы; принудительная очистка не считается PASS; чужой процесс не затронут; смерть controller до resume и при живых потомках; неудачное создание; ненулевой exit runner остаётся FAIL. Linux `skipped` не является Windows PASS. GitHub workflow запускает native на hosted Windows без Godot. JSON, creation identities и логи сохраняются в evidence при заданной переменной.

## Затем один короткий Godot smoke, не полная perf-матрица

Сохранить существующий PRODUCT worktree #814. TOOLS worktree содержит эту ветку. В интерактивной Windows-сессии, после успешных native tests:

```powershell
$Python = (Get-Command python).Source
$Tools = '<чистый worktree новой ветки>'
$Product = '<worktree PRODUCT_HEAD fdfbfb3b8...>'
$Out = 'C:\EVIDENCE\B3-job-smoke-' + (Get-Date -Format yyyyMMdd-HHmmss)
$Godot = '<проверенный console.exe>'

python "$Tools\tools\net_smooth1\run_r31_job_guard.py" `
  --receipt "$Out\job_receipt.json" --cwd $Product --deadline 900 -- `
  $Python "$Product\tools\net_smooth1\run_net_smooth1.py" `
  --godot $Godot --output "$Out\run" `
  --mode gui --scenario r31-reconnect-roundtrip --duration 30 --warmup 10 --profile LOCAL `
  --r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased `
  --r3c3-staged-earth --r3c21-frame-paced-presentation `
  --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope `
  --r3c4r31-replay-projection --r3c4r31b-durable-attribution --r31bp1-durable-chunks
```

30-секундный запуск не является нормативной 120-секундной приёмкой и может вернуть INCONCLUSIVE по длительности. Оценивать отдельно: оригинальный runner exit/verdict и Job isolation. Проверить реальные Godot trace main PIDs, wrapper PIDs, все `measure.end.ack`, Job `after.active=0`, `after.pids=[]`, `forced_job_termination=false`, внешний read-only inventory. Если был forced — сохранить FAIL текущей попытки и `remaining_identity` (creation time + executable), не объявлять «очистилось, значит PASS». Не запускать новую полную матрицу до разбора этого результата.

## Следующий performance-шаг — не часть B3

`message_ms` в #814 начинается **до** postcommit drain, ITEM completion, movement writer completion, deferred disconnect/JOIN/LEAVE, boundary poll и dispatch. Поэтому 48.8 мс нельзя приписать исключительно входящим пакетам. Для одного целевого 30–60-с диагностического прогона потребуется сопоставить все эти интервалы и snapshot build/payload/send с одним frame_id. Начать с существующих trace-событий; добавлять только отсутствующие границы. Никаких p99 по разным популяциям вместо исходного verdict и никаких новых 3×120с до выбора конкретного причинного участка. Validation не исключается как вклад в отдельный кадр, но не объявляется единственной целью.

## Источники API (primary)

- https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
- https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute
- https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
- https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes
- https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-queryinformationjobobject

**NO_MERGE. B3_CANDIDATE, не B3_VERIFIED.** Issue #815, Project Control, P7.4, SEAM-E2E и бинарный provenance остаются открытыми. Нет изменения M6/ACK/checksum, FPS/tick и баров 25/50/100 мс + 59 Гц.
