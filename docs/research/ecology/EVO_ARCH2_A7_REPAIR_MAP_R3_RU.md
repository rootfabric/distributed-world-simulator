# A7 Repair Map R3 — complete verifier and immutable protocol

Work Order: EVO-ARCH2-A7-20260912-R1. Reviewer source: 9e6b273a7758718ea99b1d2e641c8386e6db0ea3. Findings3996388234(P1),3996388235(P2). HIGH bounded continuation. A0–A6/production unchanged.

## P1 — incomplete verification could emit PASS

Public verify.py and documented default invocation gated graphics behind --graphical. A headless-only PASS could be misread as completing the Work Order, despite a separate workflow graphic report. Canonical fix: graphics is mandatory inside verify.py for every PASS. The legacy --graphical flag remains accepted but cannot enable/disable the gate. Missing Xvfb fails before the long suite; there is no optional-skip success. The canonical workflow uses this full verifier and no longer substitutes a second optional graphic step. CLI-level default and legacy-flag negative controls prove missing graphics cannot print/record PASS. Actual32-assertion horizon16 viewport is the positive control; PNG/source-report hashes are recorded by the same full summary.

## P2 — fixed experiment ID did not bind every protocol value

manifest() range-validated endowment, donor and site values and accepted arbitrary unit/scope strings. The same R1 ID could therefore mean another scientific protocol. Pin the complete canonical JSON digest, not a subset. File loading and text decoding reject a changed digest; public founding_genome/site_genesis reject an unpinned protocol argument through valid_treatment. Original protocol bytes, seeds, endowments and biological results remain unchanged. A new protocol requires a deliberate version/code change, not editing an accepted config under the same ID.

Tests cover each inherited endowment channel, donor, all site water/light/IDs, units/scope/ID, unknown fields, type/size errors and forged public protocol arguments. An actual on-disk modified manifest is rejected by the real loader, model.start and GUI reset/startup; file restored before test exit. Failed reset preserves source hashes. GUI displays PROTOCOL REJECTED rather than dereferencing an empty manifest. A 4KiB limit bounds the local manifest before reading.

## Validation and durable state

Independent review9e6 returned findings, not PASS. Earlier CI stays historical; no old summary is relabelled. Repair source pins and exact test counters must be updated, then full exact verifier with mandatory graphics and fresh independent review on the same new HEAD/TREE. No acceptance, merge or A8 activation in this repair.

## Focused result before publication

Protocol guard:106/106 assertions×2, byte-identical; полный canonical manifest остался неизменным. CLI negative controls:2/2 unittest PASS. Эти результаты относятся к рабочим файлам до freeze, не объявляют final exact verification. Полный итоговый verifier обязательно выполняет32-assertion graphical gate и сверяет PNG/source-report bytes.
