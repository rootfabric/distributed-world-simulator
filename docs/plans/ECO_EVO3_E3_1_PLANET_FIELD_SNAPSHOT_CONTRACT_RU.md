# ECO.EVO3 / E3.1 — Planet Field Snapshot Contract

Статус: `ACCEPTED / RESEARCH_ONLY / SEMANTIC ADAPTER`.

## Назначение

E3.1 создаёт первый фактический входной слой Planetary Ecology Compiler. Он переводит owner-derived planetary field semantics в детерминированный research snapshot, не копируя ownership соответствующих simulator foundations в ECO.

```text
G / ENV / MAT / WQ / SD / TF
        ↓ semantic references only
research fixture / future XFER1 adapter
        ↓
PlanetFieldSnapshot
        ↓
E3.2 Ecological Opportunity Field
```

## Что входит в snapshot

- stable planet identity;
- stable time key;
- reference frame identity;
- ordered stable spatial keys;
- opaque references на `G / ENV / MAT / WQ / SD / TF`;
- temperature;
- soil moisture;
- light availability;
- nutrient availability;
- disturbance pressure;
- source fixture hash;
- per-sample field provenance;
- aggregate field provenance;
- deterministic snapshot hash.

## Чего в snapshot нет

```text
NO biome labels
NO species identities
NO species assignment
NO population/cohort truth
NO authority route
NO production API handles
NO canonical SD identities created by ECO
```

Это принципиально: E3.1 фиксирует экологические условия, но ничего не говорит о том, какие виды должны находиться в конкретной точке. Такой вывод может появиться только позже через causal ecology.

## Numeric representation

Все continuous inputs сериализуются в integer fixed units:

```text
latitude / longitude     microdegrees
temperature              milli-degrees C
moisture                  ppm fraction
light                     ppm fraction
nutrients                 ppm fraction
disturbance               ppm fraction
```

Так одинаковый semantic input имеет однозначные bytes/hash на разных процессах и не зависит от JSON float formatting.

## Foundation boundary

Текущий adapter — research fixture:

`RESEARCH_FIXTURE_SEMANTIC_ADAPTER_NO_PRODUCTION_API_BINDING`.

Opaque references обозначают, от какого owner contract должен происходить input, но не являются уже существующим production API.

До XFER1 остаются unresolved:

```text
G
ENV
MAT
WQ
SD
TF
```

ECO не может:

- писать в owner state;
- считать fixture canonical owner truth;
- объявлять research spatial key canonical `SD`;
- владеть canonical time/environment;
- использовать snapshot как authorization world mutation.

## Provenance

Изменение foundation semantic reference должно менять `field_provenance_hash`.

Изменение environmental value должно менять sample hash, per-sample provenance и итоговый `snapshot_hash`.

Canonical order samples задаётся stable spatial key, поэтому перестановка input fixture не должна создавать альтернативную semantic ordering в output.

## Accepted fixture

Fixture `planet-alpha` содержит 12 samples от холодных/сухих до тёплых/влажных и disturbance-heavy условий. Он нужен не как планета-прототип, а как bounded deterministic carrier для проверки формата до E3.2.

Frozen identities:

```text
contract     b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170
fixture      3e22d87666b13a4bafcdd5dd3184097b53b221103fd2f9e9f2be452c8ab79978
provenance   3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3
snapshot     2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00
artifact     5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790
```

## Handoff to E3.2

E3.2 получает только accepted snapshot semantics:

```text
PlanetFieldSnapshot
        ↓
continuous causal opportunity fields
```

E3.2 запрещено напрямую читать raw fixture и тем самым обходить E3.1 provenance/validation boundary.

Opportunity Field также не должен содержать species assignment или population truth; это отдельная последующая причинная стадия.
