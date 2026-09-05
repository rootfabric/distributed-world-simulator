# Независимая статическая сверка PROJECT-FOCUS

Роль: независимый Verifier, ограниченный чтением данных и Git.
Результат: **NOT_RUNTIME_VERIFIED**. Этот документ не является VERIFIED,
checkpoint acceptance, разрешением dispatch или решением о merge.

Проверенный subject: `2a502c28269ebc3e07d4570d4497af8bf2d7b628`.
Его дерево: `bde052412de0b3242e716e2ad7b6e27f02bda419`.
База сравнения: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.
Ветка кандидата: `control/project-focus-harness-reconciliation-r1`.

## Границы работы

Прочитаны root AGENTS, PROJECT_CONTROL, HARNESS_CONTROL, Development Harness,
Review and Evidence, registry, goals, catalog и паспорт control-ветки.
Проверялся diff указанного subject, а не произвольное состояние рабочего checkout.
Scoped AGENTS внутри проверяемых каталогов не обнаружены.

Пользователь запретил запуски проекта и тестов. Поэтому Godot, Harness, unittest,
PC0, CI, Drive и CloseRole/CloseMission не исполнялись. Требования AGENTS о таких
запусках остаются непроверенными gates; ограничение пользователя имеет приоритет.
Использованы чтение файлов, Git show/diff/rev-parse/ls-tree и разбор JSON как данных
стандартной библиотекой Python, без импорта или исполнения модулей проекта.

## Статически установлено

1. **Фокус MVP.** Registry объявляет `primary_lane=MVP`; его goal имеет priority 130.
   Новый composition checkpoint находится после P7 и перед P8. Его состояние
   `PLANNED_NOT_DISPATCHED`, successor eligibility выключена. Критерии включают
   общую графическую сцену, два клиента, бесшовность, изменение среды, материал
   ровно один раз и восстановление состояния.
2. **Изоляция исследований.** ECO, FABRIC и PRESENTATION имеют `blocks_mvp=false`.
   Все 11 track-записей имеют `SOURCE_REPORT_ONLY` и
   `runtime_authorized_by_registry=false`. Scheduler сохраняет исключения для
   реальных зависимостей и пересечений владения; исследовательская ошибка не
   объявлена автоматическим запретом MVP. Разрешения второго runtime worker нет.
3. **Оперативные зеркала.** Все семь обязательных полей V0 registry/passport
   совпадают: branch, program, role, current_stage, stage_status, blockers,
   health_declared. Registry generation и effective lease generation равны 81.
   Registry, MVP coordination, scheduler, train policy, current work map и P7 plan
   согласованы на `P7_MERGED_CLOSURE_RECONCILIATION`.
4. **P7 не принят этим изменением.** Текущая runtime mutation выключена;
   слот сохранён для сверки P7. В каталоге canonical acceptance базового main
   отсутствует итоговый файл P7. Это ограниченный вывод о данном каталоге и commit,
   а не утверждение об отсутствии внешних post-merge доказательств.
5. **История сохранена.** Diff не меняет simulation/runtime, scenes, architecture
   ownership, historical executions или acceptance. Blob rotation evidence P7.7
   в base и subject одинаков: `e5dba9978e01bafb03525947804ae72621108233`.
   Старые tested heads в новом паспорте явно обозначены историческими; они не
   служат проверкой control-кандидата.
6. **Данные читаются.** Все 10 изменённых JSON разобраны без дублирующихся ключей.
   Это синтаксическое чтение данных, не запуск schema validation или Harness.

## Закреплённые источники веток

Все перечисленные commits существуют; каждый совпал с соответствующим локальным
`refs/remotes/origin/...` во время сверки. Все 14 `evidence_paths` из registry
разрешились в blobs именно внутри закреплённых деревьев, а не текущего main.
Новый fetch не выполнялся: свежесть удалённого сервера этим результатом не доказана.

| Семейство / track | Закреплённый commit | Evidence paths |
| --- | --- | ---: |
| ECO / workbench | `862934ca05aba2b35ba1cab92e11f37f59e271dc` | 1 |
| ECO / simulation | `2ca88853a9ef9eb832c12796d62c47e3da5086b5` | 2 |
| ECO / visual | `a73cccb8064fdfb4df266338d3d20e24ac9f082b` | 1 |
| ECO / integration | `884b9619e1b5a588a33fd1c18c5f70cb36c8b7cd` | 1 |
| ECO / visual_repair | `0158281d43663a3bf3ea8cf533f617d802fc127b` | 1 |
| FABRIC / core | `b9f4a11cb7c31e47884d12eaad2985811e0b6563` | 1 |
| FABRIC / bake | `457a79d1d9b915b2b665be39fd66030b92d0371a` | 2 |
| FABRIC / observatory | `0964c58779156fcadb63e1a6a348a83036488b56` | 2 |
| FABRIC / bridge_history | `46f17e3c7d2cac02cc81c7dd908f82a4ec4a2ebf` | 1 |
| PRESENTATION / mechanisms | `002fde20b04e4f8379cdd053ba9b609dfe3b38ef` | 1 |
| PRESENTATION / packs | `8da220d50ec0b987c16bd5b5aa4d6d34073a24de` | 1 |

Чтение LS4.1 source report подтверждает заявленное ограничение: implementation
есть, exact runtime pending; отдельные species cores ещё не доказывают межвидовые
причинные связи. COMPLEX2 closure report сообщает research closure и последовательность
B0.6 → BRIDGE-3 → COMPLEX3, не производственную интеграцию. Наличие source report
не подтверждает повторным исполнением результаты, записанные его авторами.

## Остаточные ограничения

Новых подтверждённых блокирующих дефектов данных в указанном scope не обнаружено.
Работоспособность CLI, PowerShell wrapper, schema branches, compatibility,
regression suites и фактическое поведение запретов dispatch не проверены исполнением.
Независимое статическое чтение кода оформляется отдельным Reviewer-документом.

Перед активацией MVP по-прежнему нужны принятый P7, точная база, planner, Work Order
и действующая review/evidence/freshness/regression дисциплина. Этот planned checkpoint
не разрешает обойти общие gates проекта. Control-кандидат остаётся кандидатом до
предусмотренных проверок и отдельного решения о merge.
