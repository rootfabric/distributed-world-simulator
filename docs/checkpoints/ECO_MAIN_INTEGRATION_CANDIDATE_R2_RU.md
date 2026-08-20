# ECO: кандидат интеграции canonical main R2

## Предмет

Кандидат `04528ad2820536b512c0844083b10d9dfc4cf171` normal-merge интегрирует `main` `5ba1dcb7b7671bff519739387513a50d90e8feac` в paused ECO source `67e23224ae153a9fc43ca5feea21c50165a99f1d`.

## Доказанные инварианты

- Родители: сначала `2d8449a242df005638b7f48648c4966a82f7cda2`, затем exact `main`.
- Дерево кандидата равно дереву первого родителя; source dry merge tree равен исходному дереву ECO.
- Из ECO source добавлены только шесть R2 execution-control records.
- В fresh synthetic clone обычный PC0 — YELLOW/NON_RED, ECO — GREEN; directional PC0 — YELLOW без RED.

## Ограничение

Это только кандидат в draft PR для `feature/eco-evolutionary-ecology`. Merge запрещён до `CONTROL_DOCS_ONLY_MERGE` human approval. После фактического merge требуется повторный live PC0 и только затем можно снимать H0 blocker.
