# EVO ARCH2 A0–A3 — exact-head publication / acceptance status R1

Дата: 2026-09-06.  
Ветка: `feature/eco-evo-arch2-a0-a3-r1`.  
PR: `#563`.

## Verdict

```text
A2/A3 SOURCE PUBLICATION = COMPLETE
IMPLEMENTER EXACT EVIDENCE = GREEN
INDEPENDENT REVIEWER = PENDING / EXTERNAL AGENT UNAVAILABLE
INDEPENDENT EXACT VERIFIER = PENDING / SELF-HOSTED RUNNER QUEUED
A0-A3 ACCEPTED = FALSE
A4 AUTHORIZED = FALSE
MERGE AUTHORIZED = FALSE
```

Нельзя превращать `queued` в PASS и нельзя подменять независимого Reviewer самооценкой Implementer.

## Frozen source subject

Полный A0–A3 source/runtime опубликован обычным Git object/ref путём, без GitHub Actions как transport:

```text
SOURCE HEAD 096723ec6162892b49c11839e07f8824d0d2c45d
SOURCE TREE 12ab345de2901690cc3a6350cefd94a14cd41984
BASE        a73cccb8064fdfb4df266338d3d20e24ac9f082b
```

После source HEAD до `83da390463ff1c8dfcdcb4af62ee2bacc85ee4a8` добавлены ровно два файла, оба validation-only workflows:

```text
.github/workflows/evo-arch2-a03-exact-acceptance.yml
.github/workflows/evo-arch2-a03-exact-acceptance-windows.yml
```

A0–A3 runtime/source после `096723ec...` не менялся.

## Что опубликовано

A1 successor contracts, hardened organism-state/attachment validation, A2 bounded modular interpreter, persistent growth-point state, resource-paid module/branch operations, explicit capacity blocking, шесть authored development-program fixtures, A3 typed parameter/regulatory/structural mutations, safe disabled duplication + explicit activation, typed research motif crossover, Morphology Lab V2, stable GDScript UID sidecars и compact exact acceptance test.

Три legacy `.tscn` изменены только удалением начального UTF-8 BOM, обнаруженного cold import; semantic content не изменён.

## Implementer exact evidence

Godot Linux:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Проверки опубликованной surface:

```text
ARCH2 compact exact acceptance: 68 / 68 PASS
fresh Godot processes:          2
logs byte-identical:            true
exact log SHA-256:              ec069c892a57d5057d793af330a7b0a68838ea81e279a3699ec7331e5d0f95d1
cold empty-.godot import:       PASS
cold-import log SHA-256:        520ead1e6c7c1907ba824c87e830d8d461516744fb0864d2bfc0c255fa70b539
real OpenGL Lab launch:         PASS
Lab log SHA-256:                63350791e84a33e9235129492bb460132a9b5d08e4baa2044f82beb20fd1c13a
VIS5.0–VIS5.5 regression:       521 / 521 PASS
```

Это strong implementer evidence, но не independent verdict.

## Независимый Verifier

Созданы read-only validation/evidence workflows. Они имеют `permissions: contents: read` и не author/push/reconstruct source.

Linux:

```text
run 34001793967
status QUEUED
required Godot SHA bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Windows:

```text
run 34001793982
status QUEUED
required Godot SHA 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Оба требуют exact checkout, clean tracked tree, exact Godot identity, cold import, ARCH2 68/68 в двух fresh processes, deterministic replay и сохранённый VIS5 regression. В момент этой записи self-hosted runner не назначен, поэтому verdict = PENDING.

## Независимый Reviewer

PR переведён из draft в ready-for-review. Выполнены штатные попытки:

- GitHub Copilot PR reviewer request;
- `@copilot review`;
- `@codex` read-only reviewer dispatch;
- assignment Copilot cloud agent через issue API;
- assignment Codex через issue API.

Reviewer verdict не появился. Assignment Copilot/Codex через доступный repository API возвращает HTTP 422 `cannot be assigned`. Поэтому нельзя создать фиктивный reviewer result.

Resume rule: нужен настоящий `FRESH_INDEPENDENT_REVIEWER` с `PASS|FAIL|INSUFFICIENT_EVIDENCE`; PASS допускается только при `required_fixes=[]`.

## Project Control

Exact Project Control run `34001793895` проверял branch HEAD `83da390463ff1c8dfcdcb4af62ee2bacc85ee4a8` и остаётся RED из-за ранее существующего G/ECO Matter critical dependency drift и ECO registry dependency drift. Эти findings не указывают на изолированные `scripts/research/ecology/v2/**` или Morphology Lab V2.

Нельзя переименовывать общий Project Control в GREEN. Перед официальным acceptance потребуется сохранить точную attribution и выполнить положенную freshness-проверку.

## Truth boundaries

Шесть форм — authored expressiveness fixtures одного interpreter, не естественно возникшие species. Environment/grants в A0–A3 synthetic research fixtures. A4 canonical/local environmental fields, A5 survival/paid reproduction, production promotion, distributed authority binding и main integration не реализованы и не объявлены завершёнными.

## Resume condition

```text
source remains frozen @ 096723ec...
        +
Fresh Independent Reviewer verdict
        +
>= 1 independent exact Verifier PASS
        +
review/verifier freshness + control attribution
        ↓
official A0-A3 acceptance evidence
```

До этого `A0-A3 ACCEPTED = FALSE`.
