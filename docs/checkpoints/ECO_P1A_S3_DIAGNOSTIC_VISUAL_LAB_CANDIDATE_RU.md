# ECO.P1A-S3 — Diagnostic Visual Lab + Controlled Trait Probes — FIX1 CANDIDATE

## Статус

`FIX1_GRAPHICAL_PASS / WINDOWS_AUTOMATED_CONFIRMATION_PENDING`.

Автоматический baseline S3 ранее прошёл exact Windows: S1 `109/109`, S2 `235/235`, S3 `114/114`. Первый ручной graphical review показал, что **экологический результат выглядит правдоподобно, но presentation недостаточно читаем**: диагностический текст визуально заходил на heatmap и не хватало явного объяснения, что изменил probe и почему конкретный patch успешен или неуспешен.

Это было классифицировано как `FIX_REQUIRED_PRESENTATION_ONLY`, а не как failure ecology truth.

## Что исправлено в Fix1

- Heatmap и diagnostics физически разделены: справа отдельный `PanelContainer`.
- Панель anchored к правому краю и имеет vertical scroll.
- Для текущего view добавлены объяснение и legend.
- Для текущего probe показываются traits и delta относительно `BASE`.
- Добавлен глобальный `PROBE EFFECT VS BASE`.
- Для выбранного patch показываются `ENV`, `RESP`, `LIMIT`, `ENERGY`, `BIO`, `RESULT`, `WHY`, `LOCAL VS BASE`.
- Полные hashes сокращены только визуально; canonical hashes в truth/test evidence не изменены.

## Fix1 automated evidence

Godot `4.7.1.stable.double.custom_build.a13da4feb` local focused run:

- S1: `109 assertions, 0 failures`;
- S2: `235 assertions, 0 failures`;
- S3 Fix1: `208 assertions, 0 failures`;
- focused dataset hash остаётся `dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690`;
- scene headless smoke остаётся PASS, `33x33`, BASE hash `9713cd410b54731fb151893ea78bec056672e6ad344c47a10046ab34d5dd2a7c`.

То есть Fix1 добавляет derived diagnostics/presentation и не меняет accepted S1/S2 truth или S3 dataset identity.

## Повторный graphical review — PASS

На Windows graphical rerun пользователь подтвердил, что revised отображение читается хорошо и views переключаются.

По предоставленным screenshots зафиксировано:

- heatmap и правая diagnostic panel больше не пересекаются;
- `View 1/8 temperature_c` имеет плавную непрерывную пространственную структуру и правильно помечен как probe-independent accepted S1 environment field;
- `View 8/8 dominant_limiting_factor` визуально разделяет WATER / NUTRIENT / LIGHT / FLOOD regions;
- выбранный patch показывает полный causal breakdown через `ENV`, `RESP`, `LIMIT`, `ENERGY`, `BIO`, `RESULT`, `WHY`, `LOCAL VS BASE`;
- numerical totals и selected-patch explanation читаются без наложения на карту;
- view switching работает графически.

Решение graphical gate:

`PASS_BY_USER_OBSERVATION`.

## Остался один gate

После Fix1 ещё нужен exact-Windows automated runner уже на версии с `208 assertions`:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology
git pull
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P1A_S3_TESTS.ps1 -GodotPath $Godot
```

Требуется:

- S1 `109/109`;
- S2 `235/235`;
- S3 Fix1 `208/208`;
- focused dataset hash `dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690`;
- scene dataset hash `9713cd410b54731fb151893ea78bec056672e6ad344c47a10046ab34d5dd2a7c`.

После этого S3 переводится в `ACCEPTED` и открывается `P1A-S4 Determinism, Sensitivity and Failure Classification`.
