# ECO P4.6 — Interest + Client Read Model — ACCEPTED WINDOWS

Статус: `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION`.

## Accepted boundary

P4.6 remains a one-way read boundary from validated P4.5 ownership into deterministic client summaries and interest projections. It does not introduce client canonical mutation, network transport, subscription ownership or runtime scheduling authority.

## Exact committed evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Unit contract: `24 assertions × 2 fresh processes`, byte-identical output.

- aggregate: `88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2`
- summary: `9b3270edcb178dcb681de63223c0d5f5c8c851d90856f94d660e76c125b4521f`
- interest: `875fce66118cc2810755549e3663d92575b4942e8a42dd00bd710c2acdc57864`

Real P4.5→P4.6 integration: `43 assertions × 2 fresh processes`, byte-identical output.

- integration: `f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf`
- source summary: `6134abede8369ed885c5e85e7ef7b127c85a51db7d5aa7b1be71990f8f0f9ab9`
- target summary: `2f8e38e132edc4302a0b2ca93c4c33abb0f0f8889b56ae2a4271068204503ef7`
- integration interest: `4a2d3b31c7542d4711864fe482eb42297b2751f583770a6854c31eccc18d1cd5`
- future summary: `b763915d5ad45a85bf8fae53212d0ae1477c125840e6a9685fab0035bc2ef83b`
- restart ownership: `c53214d530c8b711b14065d9c18a3dab30cff45e4d70eeaad40298a75eba4e34`

Accepted implementation blobs:

- kernel `5ce5aa88549c171eeda92b6d6f3202ff5c44c6b1`
- unit acceptance `9cde3960a37010a15d00c3d8c3c736943c59e7ba`
- fixture builder `dc55b886c057e2ccd8f454658b6be58d579642e1`
- real integration `1924202c9ba98ccc5e867529fda1d328b9d746ce`
- bounded runner `bd65dd9df5b964f0c930814e97c160520033adc2`

## Decision

P4.6 is accepted. P4.7 Production Integration Soak is canonically opened. P4.8 remains non-accepting until P4.7 completes its canonical committed soak gate.
