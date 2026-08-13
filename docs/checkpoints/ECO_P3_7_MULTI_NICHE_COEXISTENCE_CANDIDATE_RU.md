# ECO P3.7 — Multi-Niche / Stable Coexistence — CANDIDATE

Статус: `IMPLEMENTATION CANDIDATE / TARGETED LINUX PASS / P3.6 ACCEPTANCE + EXACT WINDOWS CANONICAL PENDING`.

P3.7 строится поверх immutable P3.6 result и добавляет environment-derived niche suitability без scripted winner. Для каждой lineage задаются continuous optima/breadths по temperature/moisture/light/nutrients. Target community shares выводятся только из этих suitability values.

Стабилизирующая отрицательная frequency feedback реализована как bounded relaxation текущей biomass composition к environment-derived target при строгом сохранении total biomass каждого patch. При `stabilization_fraction=1` target достигается точно; при `(0,1)` repeated steps монотонно сходятся к fixed point. Симметричные niche profiles дают ровно 50/50 без lexical/ID winner.

## Targeted exact-Godot evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
P3.6 source validates against final candidate kernel
P3.7 A/B/C: PASS (64 assertions each; byte-identical logs)
aggregate_hash=ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
coexistence_hash=d3a5755300e9e19f87adc2406a420ae6ea2789f0d503542453435de83e6218a9
equilibrium_hash=d47616868aff8235c74842e84a8819e3ebf8b21133aebbb7708d85d309fd2326
symmetric_hash=9c598e58df8ae385d5958281756a533286bec08554789369b1c6c368bf2ee27e
parent_p3_6=a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
source_p3_6=7c6b21d85342835f8c29aad745ed3931fce7b50284509f7eaf0a4f31e0214f10
log_sha256=aafefc1c129e5c82378a5a71ab428c53a2054c07e43996a57ca3c7641ef4437c
```

`RUN_ECO_P3_7_TESTS.ps1` fail-closed требует `P3.6 = ACCEPTED*`. Targeted Linux PASS не является canonical acceptance и не открывает P3.8.
