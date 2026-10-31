# Playtest R1: воспроизводимая визуальная проверка

База: eaf7c8bfa262bf3c933608afbdfaaf5086ab998e, принятая композиция Playtest R1
с двумя ремонтами reconnect. Основание — поручение владельца реализовать
визуальную проверку, фиксировать этапы в Git и push. Риск MEDIUM: только локальная
диагностика представления и тестовый runner; authority/wire/persistence не меняются.

## Этапы

1. Зафиксировать сценарий и критерии (этот commit).
2. Добавить read-only наблюдение анимации/проекции и repository-owned Python runner.
3. Выполнить GUI-прогон на exact implementation HEAD, осмотреть кадры, провести
   независимый разбор и отдельно закоммитить результаты с SHA/hashes.

## Сценарий и критерии

Два настоящих графических клиента и dedicated server с PLAYTEST_R1_SAFE60.
Наблюдатель отходит от траектории, направляет камеру на второго персонажа через
штатный automation movement/view API и снимает viewport во время idle, ходьбы,
бега, A→B→A и остановки. Никаких OS SendKeys, desktop capture, teleport actor или
подмены сетевых координат. При недоступном Godot MCP используется существующий
repository-owned LIVE2 automation bridge, как в предыдущих испытаниях.

Автоматически проверить: CONNECTED и сохранение identity/ownership при переходе,
реальные Quaternius без legacy capsule, персонаж перед камерой и внутри viewport,
переходы animation semantic idle/walk/run, движение времени animation player и
изменение позы целевого skeleton, фактический A→B→A. Сохранять покадровые записи,
оригинальные PNG, время захвата, exact HEAD/TREE, engine/runner hashes и логи.
Отсутствующая диагностика или недостаточные кадры не превращаются в PASS.

Проекция контрольных точек доказывает попадание в кадр, но не отсутствие окклюзии.
Поэтому отдельно осмотреть сохранённую последовательность. Sampling PNG может
вызывать паузы; это проверка видимости/анимации/перехода, не доказательство frame
p99 или плавности всех кадров. Сетевой multi-host и crash recovery вне этапа.

## Размещение и завершение

Runner/диагностика/тесты/документ — tracked paths текущей ветки; полные прогоны —
C:/distributed-world-simulator/artifacts/visual-seam-20261031. В Git сохраняются
этапы, итоговый документ и provenance/hashes; кадры, видео и машинные отчёты —
в workspace artifacts согласно правилу размещения владельца. Cleanup останавливает только собственные процессы и
отпускает movement intents. Новые runtime owners не вводятся.

Независимые review/verification по AGENTS обязательны перед заявлением результата.
Историческая SCHEMA_INVALID MVP8 остаётся отдельным control finding; acceptance
main и merge не подменяются локальным визуальным PASS.

## Реализованный запуск

Из корня checkout на Windows:

```powershell
python tools/live2/visual_seam_check.py
```

Для закреплённого source добавьте `--expected-head <полный SHA>`.
Runner требует чистый tracked checkout и установленный double Godot; путь движка
меняется через `--godot`. `--output` задаёт каталог внутри workspace artifacts.
Каждый запуск создаёт отдельный timestamp-каталог и завершает свои процессы.

Результаты: `report.json`, `samples.json`, `initial.json`, `final.json`, runtime.log,
PNG и `index.html` с покадровым просмотром/проигрыванием по времени захвата.
`character.remote.visual` — read-only runtime command: screen anchors и реальная
поза целевого skeleton, animation semantic/clip/time. Camera aiming и движение
проходят через существующий `movement.set`, без изменения сетевого протокола.

Вердикт проверяется также при Python optimization. Негативные проверки:

```powershell
python -O -m unittest discover -s tools/live2 -p test_visual_seam_check.py -v
```

Фактический результат этапа: [визуальный прогон 31 октября](PLAYTEST_R1_VISUAL_RESULT_20261031_RU.md).
