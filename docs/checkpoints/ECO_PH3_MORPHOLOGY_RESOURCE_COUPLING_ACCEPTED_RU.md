# ECO.PH3 — Morphology-to-Resource Coupling — ACCEPTED

Статус: `ACCEPTED`.

PH3 доказал, что developmental morphology имеет явные bounded resource benefits/costs поверх неизменяемого принятого `PlantResourceModel` P1.

Цепочка:

`Environment + Genome + PH2 realized phenotype/GrowthGraph -> accepted P1 resource balance + PH3 morphology ledger -> coupled research balance`.

Exact Windows evidence на Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- parent P1C-S4 aggregate `15/15`;
- PH0 `63/63`;
- PH1 `128/128`;
- PH2 `107/107`;
- PH3 focused `217/217`;
- visual lab smoke `17/17`;
- fresh-process restart `5/5`;
- failures `0`.

Exact hashes:

- profile: `1051df16a4718a3bc33be99b8394da400bc8bd7d1b8e1f86a8d190229b59a67a`;
- reference coupling: `58161227616f083ab29426931ce91e24f6354f5b3d96d9020af6f8b60b72a43e`;
- giant dense: `eaa6b1d6b452adb7ee8549baecc06c99cbb26cbce86cb34f364e36c0c152d704`;
- shade/high-height: `d437d45d4beea747df717703afb1e536e5712df837677956f16c24953e5c2759`;
- dry/wide-crown: `ef7a8f84bd1a6bf27ad87d0e8d2933627b755d200cae7722f31d6c83d54e4466`.

Trade-offs:

- height получает больший light-access benefit, но платит super-linear structural cost;
- crown spread повышает light capture, но резко увеличивает drought water cost;
- branching повышает light capture, но повышает construction/maintenance cost;
- `bigger is always better` отвергнут: balanced morphology delta `-0.01937785666868`, giant-dense `-2.70651869262583`.

Graphical diagnostic: `PASS_BY_USER_OBSERVATION`. В interactive lab подтверждены видимые различия morphology и согласованные benefit/cost bars, включая сильный penalty у `GIANT_DENSE`.

Truth boundary сохранён: renderer/mesh/LOD не участвуют в PH3 truth; TREE/BUSH/GRASS не вводятся как canonical types; P1 equations не переписаны.

Следующий gate: **ECO.PH3C Morphology-Aware Selection / Competition Convergence**. До его принятия нельзя утверждать, что morphology уже участвует в evolutionary selection, и нельзя переходить к PH4 Seed Development Lifecycle.
