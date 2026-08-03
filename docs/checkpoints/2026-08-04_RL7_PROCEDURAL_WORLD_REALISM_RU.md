# RL7 Procedural World Realism — документационный checkpoint

```text
checkpoint: documentation/rl7-procedural-world-realism
branch: feature/rl7-procedural-world-realism
base: feature/rl3-representation-aware-network-streaming
status: DOCUMENTED / IMPLEMENTATION NOT STARTED
scope: architecture and roadmap only
```

## Что зафиксировано

Создан общий контур правдоподобной процедурной генерации планет, биомов и растительности.

Основной документ:

- `docs/architecture/PROCEDURAL_WORLD_REALISM_FABRIC_RU.md`.

Roadmap:

- `docs/plans/PROCEDURAL_WORLD_REALISM_ROADMAP_RU.md`.

## Ключевое решение

Реализм среды рассматривается не как качество отдельных ассетов, а как согласованность причинных полей и пространственных структур на трёх уровнях:

```text
макро: планета, климат, геология, гидрология и биомные массивы
мезо: сообщества, кластеры, поляны, возраст и вертикальные ярусы
микро: отдельные объекты, контакт с поверхностью и материалы
```

Генерация должна идти сверху вниз:

```text
планета
→ климат и геология
→ рельеф и гидрология
→ почвы и биомы
→ сообщества
→ группы объектов
→ отдельные объекты
→ контактные детали
→ LOD artifacts
```

## Зафиксированные требования

- стабильная иерархия seed;
- независимость результата от порядка загрузки регионов;
- границы регионов без разрывов;
- экологическая и геологическая причинность;
- неоднородная пространственная структура;
- возрастные распределения;
- вертикальные ярусы;
- контакт объектов с поверхностью;
- сохранение идентичности биома между LOD;
- отсутствие заметного тайлинга и массовых повторов;
- пространственный ветер и многослойный звук;
- явный `gameplay_bias` вместо скрытого искажения природной модели;
- graybox gate до подключения production-ассетов;
- измеримые статистические и перцептивные критерии.

## Предлагаемые этапы

```text
RL7.0 contracts and reference fixtures
RL7.1 planet and biome macrostructure
RL7.2 ecological community generation
RL7.3 surface contact and environmental presentation
RL7.4 representation and distributed generation
RL7.5 planet realism acceptance
```

## Границы

Этот checkpoint не изменяет runtime-код, canonical Matter, сетевые протоколы, production Moon или текущие acceptance-критерии RL3–RL6.

Meshes, foliage instances, impostors и audio presentation не объявляются authoritative world state. Каноническими являются versioned причинные поля, seeds, source revisions и dependency hashes.

## Следующий допустимый шаг

После завершения текущего RL-контура можно начинать RL7.0 с контрактов, фиксированных graybox fixtures и offline metrics runner. Реализацию генератора отдельных деревьев до фиксации макроструктуры начинать не следует.
