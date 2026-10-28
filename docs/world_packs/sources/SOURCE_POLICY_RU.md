# WP-CONTENT1 — Source Policy R1 (SOURCE_POLICY)

Статус: milestone `SOURCE_POLICY` трека `WP-CONTENT1`.
Schema: `config/world_packs/library/candidates/schema/candidate_source.v1.json`
(`urn:dws:world_packs:candidate_source:1`).

Эта policy определяет, какие факты разрешено записывать в candidate
descriptor внешнего источника материалов до того, как реальные bytes
скачаны и проверены. Это discovery/provenance-слой, а не runtime asset
contract WP1.0: descriptor не даёт права на автозагрузку и не является
`asset/...` identity.

## 1. Главный принцип: только доказанные факты

```text
ЗАПИСАНО = НАБЛЮДЕНО НА СТРАНИЦЕ ИСТОЧНИКА / В ЛИЦЕНЗИОННОМ ТЕКСТЕ
НЕ НАБЛЮДЕНО = null / [] / "unknown"
```

Запрещено до фактической проверки bytes:

- придумывать `sha256`;
- придумывать `expected_bytes` (rounded MB сайта — не lock);
- заявлять PBR-каналы, не перечисленные на странице выбранного варианта;
- придумывать автора;
- называть artistic-материал measured/научным эталоном.

## 2. Поля descriptor-а и правила

| Поле | Правило |
|---|---|
| `candidate_id` | `candidate/<site>/<slug>`; стабилен, не переиспользуется после `rejected`. |
| `family` | один из `rock_cliff`, `sand_gravel`, `soil_ground`, `ice`, `snow`. |
| `review_status` | `discovery` → `license_verified` → `bytes_verified`; `rejected` — терминальный. |
| `upstream.author` | `null`, пока имя автора не наблюдается на странице; тогда обязателен `author_observed_on` с URL. |
| `license.expression` | только SPDX id из enum схемы или `unknown`. Никаких «наверное CC0». |
| `license.verified.method` | `page_license_statement` / `license_text` — только после реальной проверки URL; иначе `not_verified`. |
| `license.applies_to` | CC0 сайта не означает CC0 previews/логотипов: previews учитываются отдельно (`assets_and_previews` только если это явно заявлено). |
| `observed.sha256` / `expected_bytes` | обязаны быть `null`, пока `review_status != bytes_verified`. Заполняются только фактически скачанными и хешированными bytes (задача WP-ASSET1/integration, не discovery). |
| `observed.pbr_maps_observed` | только карты, перечисленные на странице выбранного варианта; пустой список допустим. |
| `provenance.measured_reference` | `true` только с `measured_evidence_url` на реальное измерение/образец; иначе `false` и класс честно `artistic`/`photogrammetry`/`procedural`. |
| `intended_use.fidelity_tier` | `reference_only` — отдельная lane: не смешивается с baseline redistributable library. |

## 3. Lanes (полосы) источников

```text
baseline redistributable   — CC0/PDDL/permissive, redistribution allowed;
reference_only             — Fab и иные download-by-user/reference-only:
                             документируются, но не входят в baseline;
rejected                   — unknown provenance или запрет redistribution.
```

Unknown provenance → reject, не warning.

## 4. Тяжёлые payloads

Git не является asset storage. Под `config/world_packs/library/candidates/**`
запрещены бинарные payload-файлы и любые файлы > 256 KiB. Descriptor —
это JSON-факт о внешнем источнике. Реальные bytes живут в content-addressable
cache (WP-ASSET1) вне Git.

## 5. Пример минимального валидного discovery-descriptor

```json
{
  "schema": "dws.world_packs.candidate_source.v1",
  "candidate_id": "candidate/ambientcg/ground037",
  "family": "soil_ground",
  "review_status": "discovery",
  "upstream": {
    "site": "ambientcg",
    "page_url": "https://ambientcg.com/view?id=Ground037",
    "asset_identity": "Ground037",
    "author": null,
    "author_observed_on": null
  },
  "license": {
    "expression": "CC0-1.0",
    "license_url": "https://docs.ambientcg.com/license/",
    "applies_to": "assets_and_previews",
    "verified": {
      "method": "page_license_statement",
      "verified_url": "https://docs.ambientcg.com/license/",
      "verified_at_utc": "2026-09-05"
    }
  },
  "observed": {
    "sha256": null,
    "expected_bytes": null,
    "resolution_variant": null,
    "pbr_maps_observed": [],
    "observation": "Site lists 1K-8K JPG/PNG PBR archives; per-archive channel list not yet inspected."
  },
  "provenance": {
    "class": "photogrammetry",
    "measured_reference": false,
    "claims": ["photogrammetry-based ground surface"]
  },
  "intended_use": {
    "surface_families": ["soil-ground"],
    "fidelity_tier": "standard",
    "notes": "Terrestrial soil look candidate; not an airless regolith claim."
  },
  "recorded_at_utc": "2026-09-05",
  "recorded_by": "WP-CONTENT1"
}
```

## 6. Проверка

Focused tests: `tests/world_packs/content_catalog/test_source_policy.py`
(валидация schema, policy-инварианты, fixtures, no-payload gate). Тесты
запускаются pytest от корня репозитория:

```bash
python -m pytest tests/world_packs/content_catalog -q
```
