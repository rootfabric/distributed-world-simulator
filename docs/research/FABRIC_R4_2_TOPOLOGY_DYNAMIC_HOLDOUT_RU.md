# FABRIC R4.2 — Topology + Dynamic Holdout

Статус до reveal: **PREREGISTERED / CHALLENGE_NOT_REVEALED**. Research-only, без production ownership.

## Frozen predecessor

```text
R4.1 HEAD = a5001eeafd012323548707d6b705b12301a91761
R4.1 TREE = 934ecfed15bd0f18389a64daf44caee6748cd73e
R4.1 STATUS = CLOSED_ACCEPTED
```

R4.2 не меняет R4.1 runtime после reveal. Если unseen challenge обнаружит capability defect, результат поколения остаётся FAIL, а repair требует нового поколения/freeze.

## Что preregistered до reveal

Frozen generator/oracle `scripts/research/fabric_holdout_r42/r42.py` создаёт ровно десять структурно различных семейств:

1. 2-port electrical chain;
2. 3-port branched/bridge network;
3. 4-port cyclic network;
4. variable 4-mobile-DOF axial mechanics;
5. supported finite near-singular topology;
6. coupled multi-DOF dynamic trajectory;
7. failure proposal → canonical commit → BAKE reconstruction/continuation → cold replay;
8. floating electrical component REJECT;
9. underdetermined mechanics REJECT;
10. non-collinear geometry outside the declared axial solver REJECT.

Список nodes/edges дополнительно переставляется beacon-зависимым порядком. Runtime не получает family-specific solver code.

## Независимый oracle

Python oracle не импортирует Godot/FABRIC-код и работает по raw topology:

- exact `Fraction` nodal Kirchhoff solve;
- exact rational static spring solve;
- independently computed infinity-norm condition estimates;
- high-resolution RK4 coupled trajectory from raw K/C/M/R topology;
- independent first mechanical capacity crossing for lifecycle case.

Godot acceptance является measurement adapter: строит canonical Construction/Matter, вызывает существующий generalized R3 compiler/runtime и сравнивает результаты с уже вычисленным oracle. До freeze protocol дополнительно прогоняет 10 фиксированных calibration seeds, а runtime-calibration покрывает все четыре beacon-допустимые load-bearing weak-bond позиции `life0..life3`; unseen seed в эти calibration-наборы не входит.

## Future randomness

Primary beacon: первый доступный NIST Randomness Beacon v2 pulse, timestamp которого строго новее preregistration commit. Pulse URI/time/outputValue сохраняются до запуска unseen challenge. Product/runtime bytes после reveal не меняются.

Fallback разрешён только при документированной недоступности NIST: SHA-256 от первого GitHub Actions run-id + head-sha preregistration commit.

## Acceptance

```text
positive families             = 7/7 PASS
negative fail-closed families = 3/3 PASS
2..4 independent ports        = PASS
variable mobile DOF           = PASS
near-singular finite          = PASS, oracle condition >= 1e4
coupled trajectory            = <= 1.5e-3 relative/absolute envelope
FULL/BAKE parity              = <= 1e-8
lifecycle event time          = <= 3e-3 s against independent oracle
canonical failure commit      = PASS
post-mutation BAKE            = PASS
continuation                  = PASS
cold replay                   = PASS
post-reveal runtime mutation  = FORBIDDEN
threshold relaxation          = FORBIDDEN
```

R4.2 не заявляет SCALE-R5, arbitrary 3D mechanics, unbounded topology или production authority.
