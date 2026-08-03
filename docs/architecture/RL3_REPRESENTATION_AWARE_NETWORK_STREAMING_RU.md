# RL3 — Representation-aware Network Streaming

**Checkpoint:** `v17.14.0-simulation-rl3-representation-aware-network-streaming`
**Build ID:** `rl3-representation-aware-network-streaming`
**Base:** accepted `v17.13.0-simulation-rl2-matter-multiresolution-meshing` plus accepted MW9 `fix3`
**Branch:** `feature/rl3-representation-aware-network-streaming`
**Status:** candidate for independent review

## 1. Назначение

RL3 доставляет производные RL2 artifacts по сети в зависимости от observer interest, экранной ошибки и cache клиента. Сетевой слой не меняет canonical Matter state и не строит mesh.

```text
MW7 regional subscription
        ↓ adapter
RL3 stream request
        ↓ planner
coarse-to-fine immutable plan
        ↓
CACHE_HIT / TRANSFER stages
        ↓
verified client cache
        ↓
progressive presentation
```

## 2. Exact request contract

`RepresentationStreamRequest` содержит:

- RL0 `RepresentationInterestRequest`;
- точную source revision;
- ordered `scope_chain`, где каждому LOD соответствует exact `scope_id`;
- sorted cached artifact hashes;
- supported encodings;
- progressive loading flag;
- bootstrap screen-error budget;
- maximum stages;
- chunk size и in-flight byte limits;
- priority и cancellation generation.

`scope_chain` предотвращает выбор coarse artifact соседней authority-region. Все stages обязаны принадлежать одному заранее объявленному пространственному пути.

## 3. Планирование

Planner повторно использует RL0 selector для final artifact и может добавить более грубый bootstrap artifact. План детерминирован и содержит stages от coarse к fine. Каждый stage имеет ровно один delivery mode:

- `CACHE_HIT` — bytes заявлены клиентом; сервер ждёт точный ACK и не доверяет заявлению автоматически;
- `TRANSFER` — сервер доставляет content-addressed chunks.

Total transfer bytes обязаны укладываться в request bandwidth budget. Если необязательный bootstrap не помещается, он удаляется, но final stage не подменяется другим source/scope.

## 4. Server state machine

Сервер обеспечивает:

- monotonic request revision на observer;
- exact idempotent replay;
- cancellation предыдущего request при replacement;
- bounded in-flight bytes;
- последовательную выдачу chunks;
- запрет перехода к stage N до ACK stage N-1;
- monotonic received bytes/chunks;
- exact artifact/manifest binding;
- `STAGE_READY` для промежуточного stage;
- `STREAM_READY` только для final stage;
- cancellation generation fence;
- RL0 invalidation fence.

## 5. Client state machine

Клиент обеспечивает:

- memory budget до приёма plan;
- проверку advertised `CACHE_HIT`;
- точный chunk index и byte offset;
- per-chunk SHA-256;
- полный content hash artifact;
- checksum manifest;
- coarse-first activation;
- автоматическую активацию trailing cache-hit stages после завершения предыдущего stage;
- немедленное снятие presentation при invalidation;
- сохранение content-addressed cache для будущего reconnect.

## 6. Progressive loading

Типичная последовательность:

```text
LOD2 MACRO_PROXY transfer
        ↓ STAGE_READY
client показывает coarse proxy
        ↓
LOD1 SIMPLIFIED_MESH transfer/cache hit
        ↓ STREAM_READY
client атомарно заменяет presentation
```

Закэшированный final artifact нельзя активировать до готовности coarse stage, если plan требует coarse-first progression.

## 7. Reconnect

После restart клиент экспортирует cache и передаёт hashes в новом request. Если exact artifacts совпадают по content hash и manifest, новый plan состоит из `CACHE_HIT` stages и payload bytes не передаются. Сервер всё равно требует ACK каждого stage.

## 8. Multi-process acceptance

Отдельные процессы проверяют:

1. server plan и chunk stream;
2. client reconstruction и final LOD activation;
3. server restart/reconnect plan;
4. client restart с импортированным cache;
5. zero-payload cache reuse.

## 9. Границы этапа

RL3 не реализует:

- artifact generation;
- shared disk cache;
- background build scheduler;
- peer-to-peer delivery;
- CDN/object-storage transport;
- compression negotiation кроме versioned encoding contracts;
- Construction HLOD;
- production Moon integration.

Следующий этап — RL4 Construction HLOD backend.
