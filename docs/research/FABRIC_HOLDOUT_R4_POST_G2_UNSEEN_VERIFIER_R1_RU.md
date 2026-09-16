# FABRIC HOLDOUT-R4 POST-G2 — FRESH INDEPENDENT UNSEEN VERIFIER R1

```text
ROLE           = VERIFIER
PRODUCT_HEAD   = e6228a39b6b3006a3d14ad0884c09266570fcd00
PRODUCT_TREE   = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
FREEZE_COMMIT  = 649af4ef16de00c797b4d63be70426abb3c75d68
PREREG_HEAD    = 8c28ff9ea4ab1446cd067ca4b8cb5674997a621d
REVEAL_R2_HEAD = 022fa6730031d529cfaecc40a76fc70315d355d1
CASES_SHA256   = 3e14d528a33f4ecb95c4d7fd1f3f55394fcb4b3e624e0bf728698acef99f576d
STATUS         = PENDING_EXACT_CI
R4_ACCEPTED    = false
```

Этот verifier не является Implementer/Reveal-run. Primary oracle реализован отдельно на Python и не импортирует production-код или prereg generator. Он заново выводит case bytes из зафиксированного NIST pulse, независимо решает rational graph/mechanics, проверяет IEEE754 transport и event polynomial/root invariants, после чего требует byte-identical совпадения с exact cases из reveal artifact.

Secondary check использует frozen prereg generator только как cross-check и затем запускает frozen GDScript acceptance runner на canonical Godot double. До exact self-hosted PASS этот документ не является R4 acceptance.
