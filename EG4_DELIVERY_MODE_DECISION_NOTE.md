# EG4_DELIVERY_MODE_DECISION_NOTE — маппинг UNRELIABLE_SEQUENCED на точный ENET transfer mode

Стадия: EG4 WORLD_GRAPH_DRIVEN_PROJECTION_AGGREGATION · Статус: РЕШЕНИЕ ПРИНЯТО (реализовано, пины обновлены)
Затронутые файлы: `scripts/network/transports/v2/enet_multi_peer_transport_port.gd`,
`tests/network/test_nx2_realtime_traffic_separation.gd` (строка-пин),
`config/network/nx2-realtime-traffic-separation.v1.json` (`enet_mapping` ×3).
Связанный фикс: `fix(network): map declared UNRELIABLE_SEQUENCED to exact ENET transfer mode`.

## 1. Симптом

EG4 L2 (leg B: шлюз ← Sim B, PROJECTION-источник): первый же крупный
unreliable WORLD_PROJECTION-кадр (~1.2 КБ) приводил к разрыву соединения.
В телеметрии шлюза — карантин строгого биндинга
(`STRICT_CHANNEL_AND_TRANSFER_MODE_V1`, политика `PEER_LOCAL_QUARANTINE_V1`):

```text
PHYSICAL_DELIVERY_MODE_MISMATCH: packet_mode=1, expected_mode=0,
delivery_mode=UNRELIABLE_SEQUENCED, protocol_violation=true
```

## 2. Первопричина (измерено, не предположено)

Godot ENET для ненадёжных дейтаграмм ВЫШЕ порога фрагментации выставляет флаг
`ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT`, и `ENetMultiplayerPeer.get_packet_mode()`
декодирует этот флаг как `TRANSFER_MODE_UNRELIABLE_ORDERED` (=1). Старое
выражение в `_transfer_mode()` объявляло ожидаемым `TRANSFER_MODE_UNRELIABLE`
(=0) для всех `UNRELIABLE_SEQUENCED`. Итог: маленькие кадры проходили (0==0),
крупные — карантинились (1 != 0). Замеры (сырой ENet + полный boundary-стек):

| Размер wire-кадра | Прибыл | packet_mode |
|---|---|---|
| ≤ ~950 Б (сырой зонд) | да | 0 |
| ≥ ~1000 Б (сырой зонд) | да | 1 |
| egress-envelope ≤ 1173 Б (boundary-зонд) | да | 0 |
| egress-envelope ~1218 Б (реальный кадр leg-B) | НЕТ — карантин | 1 |

Нижняя граница контрактно-валидного egress-envelope (двойная обёртка
GatewayEgressEnvelope → ClientWorldFrame → projection payload, два SHA-256
чексамма, длинные schema-строки) ≈ **1155 Б** — то есть «держать кадры маленькими»
не может быть стабильным контрактом: запас до скалы ~20 Б и зависит от длины
mint-идентификаторов сессий (любой суффикс client-session тихо возвращает дефект).

## 3. Почему НЕ «локальный фикс только в send-path EG4» (вариант B ревью)

Ожидаемый режим вычисляется ПОЛУЧАТЕЛЕМ в разделяемом `_transfer_mode()`
(`enet_multi_peer_transport_port.gd::_poll_peer`, строка `expected_mode`).
Send-side ремап внутри EG4-воркеров не меняет эту проверку:

- при откате разделяемой функции к старому выражению ЛЮБОЙ фрагментированный
  unreliable-кадр EG4 карантинится независимо от отправителя;
- при локальной отправке mode=1 при старом ожидании mode=0 карантинится КАЖДЫЙ
  EG4 unreliable-кадр — строго хуже;
- остаётся только дисциплина размеров (см. §2) — хрупкий неявный контракт.

Поэтому ремап принят глобально: он устраняет сам класс отказов
«чувствительность к размеру пакета», а не его частный случай.

## 4. Решение

`UNRELIABLE_SEQUENCED` теперь отображается на ENET sequenced-unreliable
(`TRANSFER_MODE_UNRELIABLE_ORDERED`) — режим, чья физическая семантика
СООТВЕТСТВУЕТ объявленному имени: ENet ведёт поканальную нумерацию, а
`get_packet_mode()` декодирует те же флаги обратно для целых и
фрагментированных дейтаграмм одинаково. Объявленный и физический режимы
совпадают при любом размере кадра; STRICT_CHANNEL_AND_TRANSFER_MODE_V1
перестаёт зависеть от MTU/порога фрагментации.

Старое выражение (`TRANSFER_MODE_UNRELIABLE if delivery_mode == "UNRELIABLE_SEQUENCED"`)
понижало «SEQUENCED» до plain-unreliable без всякой секвенции — что и признавала
формулировка старого пина NX2 («packet-size-sensitive sequencing»).

## 5. Что ещё держит EG4 (гигиена, но уже не корректность)

EG4-воркеры по-прежнему целься в < ~900 Б на проекционный кадр (компактные id,
одна entity на кадр, бит каждые ~120 мс) — это бюджет потерь unreliable-потока,
а не условие прохождения fence.

## 6. Обновлённые пины

1. `tests/network/test_nx2_realtime_traffic_separation.gd`: строка-пин исходника
   требует явного `return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED` под
   веткой `UNRELIABLE_SEQUENCED` и запрещает возврат старого понижения;
2. `config/network/nx2-realtime-traffic-separation.v1.json`: `enet_mapping`
   каналов INPUT/SNAPSHOT/TELEMETRY: `RAW_UNRELIABLE` →
   `ENET_TRANSFER_MODE_UNRELIABLE_ORDERED`.
Константа `ChannelPolicy.UNRELIABLE_TRANSPORT_MAPPING`
(`RAW_ENET_UNRELIABLE_APPLICATION_SEQUENCED_V1`) не менялась: она описывает
прикладную секвенцию поверх ENet-канала, а не выбор transfer mode.
