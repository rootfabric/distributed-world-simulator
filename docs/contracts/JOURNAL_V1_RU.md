# Контракт журнала `lunar.journal_event.v1`

Файл:

```text
user://worlds/<world_id>/journal/events.jsonl
```

Одна операция на строку:

```json
{"schema":"lunar.journal_event.v1","revision":1,"operation":"entity_created","data":{}}
```

Операции первой версии:

- `entity_created`;
- `entity_removed`;
- `entity_moved`;
- `entity_component_changed` — изменение постоянного компонента без перемещения сущности.

Журнал нужен для диагностики, будущего восстановления после сбоя, воспроизведения экспериментов и переноса чанка между владельцами.


В v15.5.1 identity-поля добавлены к каждой новой записи. Они не превращают
локальный JSONL в distributed event store, но исключают неявное смешение
параллельных instances и сохраняются при дальнейшей миграции в event adapter.
