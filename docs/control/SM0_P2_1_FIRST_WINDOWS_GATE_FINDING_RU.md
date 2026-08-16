# SM0-P2.1 — first Windows gate finding

Статус: HARNESS DEFECT FIXED / RUNTIME IMPLEMENTATION NOT YET VERIFIED.

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`.

Tested exact candidate: `22ec97daae0a37376a5674656b099acb8cd70138`.

Windows exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

## Наблюдение

Первый Windows запуск `RUN_V0_SM0_RECOVERY_PERFORMANCE_ACCEPTANCE.ps1` остановился на первом compile check с сообщением вида:

`compile check failed ... (exit Godot Engine ... 0)`

При этом Godot сообщил exact expected version, а фактический native process exit code был `0`.

## Root cause

Ошибка находится в PowerShell acceptance harness, а не в GDScript compile result.

`Invoke-P21Godot` напрямую вызывал native Godot, после чего выполнял `return $LASTEXITCODE`. В PowerShell stdout native process также попадает в success pipeline функции. Поэтому вызывающая сторона получала composite result: строки stdout Godot + integer `0`. Условие `$CompileExit -ne 0` становилось истинным и создавало false FAIL.

Это тот же класс trust-boundary/harness ошибки: PASS/FAIL нельзя выводить из переменной, загрязнённой native stdout.

## Correction

Commit `0d1a573e3f88431c340a4ef8b1a77e294ab72bf2` (`fix(sm0): isolate Godot exit code in P2.1 gate`) исправляет только acceptance harness.

`Invoke-P21Godot` теперь:

1. захватывает stdout/stderr Godot в локальный массив;
2. отдельно сохраняет `[int]$LASTEXITCODE`;
3. выводит захваченные строки через `Write-Host`, не возвращая их в pipeline;
4. возвращает вызывающему коду только integer exit code.

P2.1 runtime GDScript, recovery semantics и write-before-ACK этим исправлением не изменялись.

## Следующий gate

Повторить headless Windows acceptance на commit, содержащем harness fix. Только после фактического compile/regression PASS можно переходить к graphical P2.1 comparison.

Никакой production/global/V0-S1 acceptance не объявляется. Cross-server authority остаётся CRITICAL, `SERVER_HANDOFF` остаётся за `stop_before` V0-S1.
