# XFER1/LIVE — Обновление готовности со стороны экологии

Статус: `NON_AUTHORITATIVE / READINESS FACTS`. Дата: 2026-08-22. Владелец canonical foundation — product train.

## 1. Что экология уже отдаёт переносимого (пути проверены)

| Артефакт | Содержание |
|---|---|
| `config/ecology/accepted_inputs/e3_final/evo2_persisted_species_catalog.e3_final_extended_r1.v1.json` | принятые геномы (12) |
| `validation/ecology/eco-evo3-e3-final-unseen-world-program.generated.json` | планетарные программы колонизации, 12 комбинаций, chain hashes |
| `validation/ecology/evo4_b6_region_manifest.v1.json` | самодостаточная рассадка региона: 990 экземпляров + species_traits |
| `scripts/research/ecology/evo5_factor_registry_v1.py` | расширяемый реестр факторов среды для будущих генераторов поверхности |
| `validation/ecology/evo5_genes_block_initial.v1.json` | блок Genes-v1 по genome_checksum (гейтинг/цена) |
| `validation/ecology/evo5_t0/t2/t5_*.json` | sealed-вердикты трофики и трёхуровневой устойчивости |

## 2. Реестр пробелов канонических контрактов

- **G**: нет канонического маппинга «факторные объекты поверхности → site_features» (генератор должен эммитить данные формата A0);
- **ENV**: факторный реестр есть research-side; канонизация схемы фактора — за ENV-владельцем;
- **MAT/WQ**: экология не поставляет материалов/воды; пробелов не вскрывала;
- **SD**: сиды детерминированы внутри лейна; канонический seed-контракт между миром и экологией не оформлен;
- **TF**: временные ряды (сезонность) отсутствуют до E3.6-R evidence.

## 3. LIVE0-minimum proposal

Read-only проекция в чанк мира: манифест B6 как статичная рассадка + факторный реестр как локальные модификаторы условий; без population truth, без записи в мир, потребление только принятых артефактов.

## 4. Дисклеймер

Документ non-authoritative: фиксирует факты готовности research-стороны. Решения о canonical foundations — human gate / product train.
