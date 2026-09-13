# MVP3 R13b — публикация существующего manual raw evidence

Evidence-only ветка. НЕ MERGE в product/main.

Exact product subject:

```text
HEAD = f1d453fb2af49231c30bdc5cbe415ad199394446
TREE = f1697cc52c1abc7f1bb21922c5fab3b49a3c167d
FREEZE = freeze/v0-mvp3-r13b-f1d453fb-r1
```

Источник уже выполненного Windows run:

```text
C:\distributed-world-simulator\.mvp3-manual-91c0df9d-r1\artifacts\mvp3-manual-r13b-f1d453fb-20260913T092910Z
```

Задача — только опубликовать уже существующие bytes. Manual run НЕ повторять и raw files НЕ редактировать.

Создать каталог:

```text
evidence/mvp3-r13b-manual-f1d453fb/
```

Скопировать туда byte-for-byte:
- все 13 raw files существующего run;
- `sha256-index.json`;
- `MVP3-WINDOWS-IMPLEMENTER-R13-REPORT.json`, если он хранится вне raw-каталога;
- дополнительный `publication.json` разрешён только как новый metadata-файл и не должен менять raw.

Перед commit проверить SHA-256 каждого raw файла против существующего `sha256-index.json`. Зафиксированный Implementer manifest digest:

```text
3075debd09a3f06e352387b430015204d3e1c095525dba1d958afcc1a7b03668
```

Если любой raw hash не совпадает — STOP / EVIDENCE_BYTES_DRIFT. Не регенерировать файл и не исправлять его.

`publication.json` должен содержать exact HEAD/TREE/freeze, UTC publication time, исходный Windows path, число raw files и SHA-256 index/report. Не записывать secrets.

После публикации вернуть branch HEAD/TREE, список файлов и `git status --porcelain --untracked-files=no = CLEAN`.

Эта ветка НЕ создаёт Independent Verifier PASS, `PREDICATE_VERIFIED`, `MVP3 CLOSED` или parent acceptance.