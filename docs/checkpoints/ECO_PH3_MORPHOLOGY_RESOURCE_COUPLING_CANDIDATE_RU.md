# ECO.PH3 — Morphology-to-Resource Coupling — CANDIDATE

Статус: `LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

PH3 впервые делает developmental morphology не только формой отображения, но и частью resource economics. Принятый `PlantResourceModel` P1 не изменяется: PH3 читает его exact result как parent evidence и строит отдельный research-only morphology ledger.

Цепочка:

`Environment + Genome + PH2 realized phenotype/GrowthGraph -> accepted P1 resource balance + PH3 morphology benefits/costs -> coupled research balance`.

Локальное evidence на Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- parent P1C-S4 aggregate `15/15`;
- PH0 `63/63`;
- PH1 `128/128`;
- PH2 `107/107`;
- PH3 focused `217/217`;
- visual lab smoke `17/17`;
- fresh-process restart `5/5`.

Exact hashes:

- profile: `1051df16a4718a3bc33be99b8394da400bc8bd7d1b8e1f86a8d190229b59a67a`;
- reference coupling: `58161227616f083ab29426931ce91e24f6354f5b3d96d9020af6f8b60b72a43e`;
- giant dense: `eaa6b1d6b452adb7ee8549baecc06c99cbb26cbce86cb34f364e36c0c152d704`;
- shade/high-height: `d437d45d4beea747df717703afb1e536e5712df837677956f16c24953e5c2759`;
- dry/wide-crown: `ef7a8f84bd1a6bf27ad87d0e8d2933627b755d200cae7722f31d6c83d54e4466`.

Доказанные trade-offs:

- height: light-access benefit `0.1079 -> 0.2256`, structural cost `0.0555 -> 0.4559`;
- crown spread: wide crown получает light benefit, но drought water cost растёт `0.0453 -> 0.3902` относительно narrow;
- branching: light benefit `0.0520 -> 0.1204`, construction cost `0.0244 -> 0.2250`;
- `bigger is always better` отвергнут: balanced morphology delta `-0.0194`, giant-dense `-2.7065`.

Diagnostic scene: `res://scenes/labs/ecology/eco_ph3_morphology_resource_visual_lab.tscn`. Слева показывает derived GrowthGraph, справа — morphology resource ledger. Renderer остаётся presentation-only.

После exact-Windows PASS PH3 принимается. Затем нужен отдельный **PH3C Morphology-Aware Selection / Competition Convergence**, чтобы доказать, что эти morphology costs/benefits действительно участвуют в selection, и только после него переходить к PH4 Seed Development Lifecycle.
