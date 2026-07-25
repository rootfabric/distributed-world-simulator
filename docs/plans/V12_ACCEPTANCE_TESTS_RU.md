# V12 Acceptance Tests

## 1. Меню

1. Запустить проект.
2. Нажать `F1` или `Esc`.
3. Панель должна скрыться, курсор — захватиться.
4. Повторное нажатие открывает меню и освобождает курсор.

## 2. Player Entity

В меню должна быть строка:

```text
Сущности: entities=1 ...
```

При ходьбе через границу чанка счётчик `chunks` увеличивается.

## 3. Runtime mini-test

Нажать `F7` или кнопку `Тест миграции`.
Ожидаемый результат:

```text
PASS: F... C... → F... C...
```

## 4. Headless test

```powershell
.\RUN_ENTITY_INTEGRATION_TEST.ps1
```

Ожидаемый вывод:

```text
Entity registry integration tests: PASS
```

## 5. Диагностика

Нажать `F9`. В меню должен появиться путь `user://diagnostics/...json`.
Файл должен содержать схемы:

```text
lunar.diagnostic.v1
lunar.partition.v1
lunar.entity_registry.v1
```
