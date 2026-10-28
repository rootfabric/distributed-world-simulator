# EVO ARCH2 A10 — R2 Matter resource semantics

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R2`, HIGH.
Parent subject: A10-R1 `cf63b8263c98847daf91d841892bd00761640754`.
Canonical main at dispatch: `471210d781e521bc7897a8fe859636a07d7a3ab3`.

## Зачем нужен R2

R1 доказал structural binding к production Matter, но намеренно не превращает point sample в ecological resource stock. Следующий риск — незаметно объявить geological material «nutrient» или «organic» и тем самым создать выдуманную физическую семантику.

Current-main Matter catalog содержит, среди прочего, `matter/water-ice`, regolith/rock/ore/waste, но не содержит canonical biological nutrient/organic material identities. Поэтому A10 не вводит default mapping.

## Контракт

R2 добавляет caller-owned, catalog-bound map:

```
Matter material_id  --explicit map-->  ECO resource
```

Допустимые ECO resources остаются A4/A5:
- `water_mg`
- `nutrient_mg`
- `organic_mg`

Правила:
- map по умолчанию пустой;
- каждый material ID обязан существовать в exact MatterMaterialCatalog;
- один material ID не может означать два ECO resource;
- map bindится к `catalog_hash`;
- неизвестные material IDs fail-closed;
- отсутствие mapping означает UNMAPPED, а не нулевую стоимость/автоматическую конверсию;
- R2 не утверждает, что `matter/water-ice` автоматически является доступной растению водой: такой mapping возможен только как явный caller contract конкретного consumer.

## Conservative MatterMaterialBatch admission

R2 принимает только валидный production `MatterMaterialBatch`, все его component IDs должны существовать в связанной версии каталога. Допуск требует caller-owned external trusted `expected_batch_checksum`; checksum внутри самого batch не является authority proof.

Перевод kg→mg разрешён только когда total mass и component masses представлены целым количеством mg в пределах строгой double tolerance. Никакого скрытого округления, создающего/теряющего массу, нет.

Выход:
- exact batch checksum;
- exact map checksum;
- total_mass_mg;
- mapped `water/nutrient/organic` mass;
- explicit unmapped material mass;
- invariant `mapped + unmapped == total`.

Это **admission/accounting**, не environment extraction и не world mutation.

## Не входит в R2

- добыча Matter из terrain;
- создание nutrient/organic material definitions;
- автоматический `water-ice → water_mg`;
- изменение A4 field stocks;
- создание Matter output из погибшего организма;
- A11 habitat.

## Acceptance

R2 должен доказать:
1. пустой map не создаёт ECO ресурсы;
2. explicit water-ice fixture может быть принят только при caller mapping и mass stays exact;
3. mixed mapped/unmapped batch сохраняет всю массу;
4. unknown/duplicate/ambiguous mapping отвергается;
5. fractional non-mg-exact batch отвергается вместо округления;
6. production Matter catalog/batch contracts и A10-R1 source остаются byte-identical.

## Найденная production-граница

Current-main `MatterMaterialReceiver` предоставляет reserve/commit/rollback/get/export/restore, но не canonical consume/transfer operation, которая могла бы атомарно передать уже committed batch в ECO и запретить его повторный расход. Поэтому R2/R5 — admission/accounting, а не физическое списание Matter в biology. Использовать `rollback_batch()` как consume запрещено семантически. До появления отдельного production consume/transfer receipt A10 не заявляет полный Matter-conservative uptake loop.
