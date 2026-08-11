# ECO.PH1 — Deterministic GrowthGraph Skeleton Lab — CANDIDATE

Статус: `LOCAL_FOCUSED_PASS / PH0_WINDOWS + PH1_WINDOWS + GRAPHICAL_PENDING`.

Цель — доказать, что один общий parametric developmental model даёт разные morphology skeletons из непрерывных traits, без `TreeGenerator/BushGenerator/GrassGenerator`.

Controlled probes: BASE, APICAL_LOW/HIGH, BRANCH_LOW/HIGH, ANGLE_NARROW/WIDE, INTERNODE_SHORT/LONG.

Local evidence:

- focused `128 assertions`, 0 failures;
- visual lab headless smoke `10/10`;
- restart replay `4/4`;
- base graph hash `6470722b770afee48def9ee06cc44a36640734abc9fc362a2fed6eb648779451`;
- base: 14 segments, 10 main-axis, 4 lateral, 2 branch roots, height 3.2m, radius 0.3587m.

Proven effects:

- lower apical dominance -> more branching;
- higher branch probability -> more lateral branches/segments;
- wider branch angle -> larger mean angle and crown radius;
- shorter internodes -> more axis segments at same max height;
- probability sweep is monotonic, not a hidden generator switch;
- same traits + IndividualSeed -> exact same graph hash;
- different IndividualSeed -> different realization.

Graphical lab: `res://scenes/labs/ecology/eco_ph1_growth_graph_visual_lab.tscn`; cycle Q/E through all 9 probes.

PH1 remains derived representation research only. PH2 may open only after PH0+PH1 acceptance.
