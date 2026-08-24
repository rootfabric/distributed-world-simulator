# ECO — точка продолжения после сессии 2026-08-24 (EVO7 line R1 assembly)

**Назначение:** durable handoff. Любая будущая сессия обязана resume-ить из этого документа + Git, не из истории чата.
**Статус всего перечисленного:** CANDIDATE / PROPOSED — ничто не принято; приёмка только через процедуры, перечисленные в §5.

## 1. Точное состояние веток (на момент фиксации)

```text
feature/eco-evolutionary-ecology (ствол программы)
  head: 0d00ffd8 merge(eco): fold EVO7 FFF research line into program trunk
  = 836e9483 (BOM-fix evo4/5 сцен + CONV0-A docs, внешняя сессия)
  + feature/eco-evo7-fff-r1 @ 2893cf23 (134 коммита, слиты без конфликтов)

feature/eco-evo7-fff-r1 (исследовательская линия EVO7)
  head: 2893cf23 docs(eco): persist line R1 assembly verification report
  полностью содержится в стволе после merge 0d00ffd8
```

## 2. Что сделано в этой сессии (кратко, с коммитами)

1. **Санитария веток**: ствол подтянут до origin, линии сведены (`43f225e2` на evo7; финально — merge `0d00ffd8` на стволе).
2. **Ремонты R2 линии EVO7** (`30ccb97d`, `cf543e76`, `c3dd4354`, `29c62c65`):
   - NOTE-2: потолок bound-pinning `STABILITY_PINNING_CEILING := 0.25`, калибровка по seeds 20260823/24/25 (меж-seed max 0.080, запас 3.125×); fail-closed направление доказано исполнением;
   - MINOR-1 (EVO6-WATER в цепочке FFF6) верифицирован как уже закрытый `c0a70efc`;
   - канонические раннеры `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.{ps1,sh}` + Linux-твин `RUN_ECO_EVO7_FFF6_TESTS.sh`;
   - ремонт MINOR учёта стадий (`127f71f2`, агрегат 21/21).
3. **G5 visual evidence** (`7e3c0ad7`, `8692a074`): C-mode захваты succession lab
   `artifacts/evo7_fff6_lab_cmode_wide.png` (sha256 539d37ec…) и `…_close.png` (sha256 40d7c441…),
   `result_hash=52995cf4bcd03578…` инвариантен во всех прогонах; найден и исправлен await-баг гонки захвата.
4. **Сборка пакета** (`eb10f460`…`a2e0960b`, `2893cf23`): Evidence Map + proposal line-level checkpoint + персистенция отчётов ролей.

## 3. Верификация (все роли независимые, изолированные чекауты)

| Роль | Диапазон/HEAD | Вердикт | Durable отчёт |
|---|---|---|---|
| REVIEWER | c3dd4354 (43f225e2..c3dd4354) | PASS (1 MINOR — исправлен; 4 NOTE) | docs/evidence/2026-08-24_ECO_EVO7_R2_MINORS_FINAL_REVIEW_RU.md |
| VERIFIER | a2e0960b (пакет сборки) | PASS (0/0/0, 5 NOTE) | docs/evidence/2026-08-24_ECO_EVO7_LINE_R1_ASSEMBLY_VERIFICATION_RU.md |
| Центральная инспекция G5 | финальные PNG | достаточность подтверждена | docs/evidence/2026-08-24_ECO_EVO7_G5_CENTRAL_VERIFICATION_RU.md |

Сертификационные прогоны на Linux (Godot double 4.7.1-a13da4feb): FFF6-цепочка 21/21 PASS (≈583 c),
якоря `52995cf4bcd03578…` (FFF6), `7010e30707613e28…` (EVO6-WATER guard, бит-идентичен Windows-эталону),
SUCCESSION wave2 `28414a18… / 876ecd4f… / c047378f…` — побитово совпадают с Windows-evidence.

## 4. Индекс ключевых документов

- Карта доказательств линии: `docs/plans/ECO_EVO7_EVIDENCE_MAP_RU.md`
- Proposal line-level checkpoint: `docs/checkpoints/2026-08-24_ECO_EVO7_LINE_R1_PROPOSAL_RU.md`
- Спецификация линии: `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md`
- Линейный аудит G1–G15: `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md`
- G5: `docs/evidence/2026-08-24_ECO_EVO7_G5_VISUAL_EVIDENCE_RU.md` (+ central verification, см. §3)
- Ремонты R2: `docs/checkpoints/2026-08-24_ECO_EVO7_FFF6_R2_MINORS_RU.md`, `docs/evidence/2026-08-24_ECO_EVO7_LINE_MINORS_REPAIR_RU.md`
- Мульти-seed: `docs/evidence/2026-08-23_ECO_EVO7_MULTISEED_{ROBUSTNESS,WAVE2}_RU.md`

## 5. Как продолжать (упорядоченно)

1. **Свежая line-auditor роль**: формальная переклассификация строки G5 (PARTIAL→PROVEN) в
   `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md` на exact head ствола; материал закрыт
   (см. G5-доки), вердикт аудита не переписывался реализаторами намеренно.
2. **Windows-сторона**: исполнить `.ps1`-раннеры (в т.ч. NOTE-4 verifier'а про PowerShell 5.1 stderr)
   и прогнать PC0/`CONTROL_PROJECT` на каноническом контроле.
3. **Director-маршрутизация** proposal `ECO_EVO7_LINE_R1` по процедурам чекпоинта; human merge gate —
   только для merge в main (ветки уже сведены на уровне программы).
4. После acceptance линии — **FFF7 Scale/XFER Readiness** (водяной bucket-pruning, forest N≥1000,
   profiling/LOD; persistence/write-authority/network — отдельными гейтами) и хвосты E-4
   (fitness-декомпозиция §11, benefit-сторона structural_investment, water-use coupling rsr).
5. **Формальная контрольная линия ECO** (параллельно, не блокируется): паспорт ведёт к E3.2
   Ecological Opportunity Field поверх принятого E3.1; CAL1 обязательна до unconstrained morphology
   evolution; CONV0-A design-only (требования добавлены `836e9483`); CONV0-B ждёт canonical
   R3/WQ/MAT/LIFE/WB контрактов; XFER1 заблокирован.
6. **Паспорт/registry**: операционные поля паспорта программы сознательно НЕ обновлялись этой сессией
   (контрольная собственность); refresh паспорта/registry под current reality — отдельный control-коммит.

## 6. Заметки среды (Linux-машина этой сессии)

- Godot: `~/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64` (sha256 bfa7ce63…517d7);
  свежий worktree требует `--headless --editor --import` preflight.
- Живой графический десктоп (GNOME Wayland, Xwayland :0) — оконные GUI-прогоны и захваты работают
  (использовано для G5); `BREAKPOINT_RUNTIME_DISABLED=1` обязателен.
- pwsh отсутствует: `.ps1`-раннеры здесь неисполнимы (зеркальная логика покрыта `.sh`).
- Наследованный дефект BOM в eco_evo4/5 сценах закрыт на стволе (`b7b4db75`) и в линии (`5ddc0df6`);
  после merge 0d00ffd8 preflight чист.
- Временные результаты — только под `artifacts/` (gitignored).
