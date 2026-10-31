# Визуальная проверка Playtest R1 — 31 октября 2026

**Ограниченный результат: PASS.** Наблюдатель держит второго персонажа в кадре;
idle, ходьба, бег, переход A→B→A и остановка подтверждены диагностикой и осмотром
сохранённых кадров. Полная визуальная приёмка мира этим не объявляется.

## Зафиксированные этапы

| Этап | Commit | Результат |
| --- | --- | --- |
| Сценарий, критерии и границы | 783d80114 | План сохранён и отправлен |
| Диагностика скелета/viewport и GUI runner | 5a183a39c | Первый прогон PASS, 46 кадров |
| Исправление замечания independent review | 1b40813ca | Проверки больше не отключаются через python -O |
| Негативные тесты и более близкая камера | dc2912711 | Итоговый exact-source GUI прогон PASS, 47 кадров |

Первый прогон не переписан. В нём reviewer нашёл риск false PASS под Python
optimization: `assert` мог отключиться. Guards заменены явным `require`, добавлены
проверки пустой фазы, замороженной позы и отсутствующего roundtrip. Итоговый прогон
специально выполнен через **python -O**.

## Точное происхождение

- Source HEAD: `dc2912711565d6260f445982c99d80870322244b`.
- TREE: `375fa842db2d7e35d09b7ba37d66a2230d6b8932`.
- Профиль: PLAYTEST_R1_SAFE60; Godot 4.7.1 double a13da4feb.
- Engine SHA256: `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`.
- Runner SHA256: `28ae6b9db6acafee66cdd43b927e45aacea39bc2575d9153d09e1857a0a54e2b`.
- Команда: `python -O tools/live2/visual_seam_check.py --expected-head dc2912711565d6260f445982c99d80870322244b`, exit 0.
- Полный run: `C:/distributed-world-simulator/artifacts/visual-seam-20261031/20261031-143742`.

47 оригинальных PNG: idle 8, walk 15, secondary-idle 8, run 8, stopped 8.
Все анатомические контрольные точки находятся перед камерой внутри viewport.
Target skeleton содержит 65 костей; animation clock и pose hashes меняются.
У actor сохраняются player identity и ownership; seam authority epoch проходит
1→2→3. Скриптовых/parse/checksum ошибок не найдено. Клиенты завершаются с exit 0;
server exit 1 — штатная для runner принудительная уборка своего сервера после теста.

Godot-проверки на итоговом source: observation 20/20, network avatar 28/28,
camera toggle 16/16. Python negative tests под -O: 4/4. Все exit 0.
Независимый участник подтвердил code review и evidence PASS: hashes всех 47 PNG,
runner, анимационные фазы, переходы; отдельно повторил negative tests4/4.
Независимый observation20/20 выполнен на предыдущем implementation source;
reuse по неизменным GDScript inputs явно записан в review, не выдан за новый запуск.

## Визуальный осмотр и ограничения

На выбранных idle/walk/run/stopped и приграничных кадрах виден настоящий humanoid,
а не legacy capsule. Положения ног/рук меняются, камера удерживает модель;
модель не исчезает на сохранённых кадрах до и после перехода.

Фон/поверхность не позволяют подтвердить контакт стоп с terrain. Sampling PNG
показывает отдельные кадры и влияет на render timing; это не доказательство
плавности 60 FPS, отсутствия всех промежуточных рывков или occlusion correctness.
Authority здесь локальный product seam, multi-host/N3–N5 не принимаются.

Просмотр всех кадров: `<run>/index.html`. Видео выборки:
`<run>/sampled-visual-seam.mp4` — интервалы исходного захвата, без синтеза кадров;
для H264 добавлена одна нижняя строка до чётной высоты. Оригинальные PNG неизменны.
Компактная подборка и hashes: `../published-preview/result.json` относительно run.
Independent review: `../review.md`, manifest: `../reviewer/evidence-manifest.json`.

Control Drive/CloseRole возвращают прежнюю SCHEMA_INVALID MVP8; эта ошибка
не исправлялась и формальная checkpoint acceptance/merge не заявляется.
Данный итоговый commit меняет только документацию, не протестированные inputs.
