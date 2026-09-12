# FABRIC R4 — exact qualification evidence R1

Product: 989ed83c10d861f151423b4e7dae6952c7177b68 / aefd109b76a5ebc5ee98f35e730bb07a895f59fe.
Control tools: c028efd2d11b5695f8b91d2834196927e329f3aa.
Work Order: 75d9c8ec91b0acbb9bbdcd4d5dbe3527c13c5801.

## Получение полных обязательных логов

Архив разделён на четыре бинарных Git blobs только для ограниченного connector
transport. Это один неизменяемый tar.xz, не четыре независимых evidence.
Git blob каждой части и SHA256 восстановленного архива сверены перед commit.
В клоне этой control-ветки выполните из текущей директории:

```bash
cat core.tar.xz.part000 core.tar.xz.part001 core.tar.xz.part002 core.tar.xz.part003 > core.tar.xz
printf '%s  %s\n' 9757eb49db96f4778237897a8ff76e2670128d522771071e39d399279ca8ed39 core.tar.xz | sha256sum -c -
mkdir core
# Архив содержит только проверенные относительные regular files.
tar -xJf core.tar.xz -C core
(cd core && sha256sum -c SHA256SUMS)
```

В core находятся ПОЛНЫЕ combined stdout+stderr пяти local exact gates, не excerpts;
receipts, policy, identity, qualification result, сравнительные negative controls,
scope/triage и B0.6 manifest. Все ссылки evidence в receipts разрешаются внутри core.
27 файлов. Локальная платформа Linux-6.18.35-x86_64-with-glibc2.41, exact Godot
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.
Это НЕ Ubuntu self-hosted execution и НЕ независимая Verification.

Core является подмножеством расширенного user ZIP. Копии tools, все per-suite B0.6
логи, исторические CI downloads и supplemental raw interoperability arrays не
дублируются в core: tools уже закреплены отдельным Git commit, исходные CI доступны
по IDs в manifest. `manifest.json` внутри core скопирован из полного пакета;
упоминания selected G2 CI logs в нём описывают полный пакет, не core. Авторитетный
список содержимого core — SHA256SUMS + README, а не перечень полного архива.
Все обязательные локальные логи для reducer сохранены без сокращения.

Portable evidence отдельно обозначено API observation + excerpt. Полный portable
job log прочитан через connector, но не заархивирован; binary SHA этим workflow
не записан и не придуман. Независимый Reviewer должен проверить linked job сам.

## Результаты

- G2 exact: local PASS и self-hosted run 34666972518 SUCCESS, artifact 10289717524.
- Transport 381/381; bond_id 17/17; G2 89/89; R3 transient 611/611,
  observer/process/cold replay; R2; R1 42/42 — PASS.
- B0.4-D Linux closure, Complex Labs, CX-VIS0/1 — полный local exact PASS.
- B0.6-CLOSE — полный local exact PASS, 26 runners, включая COMPLEX2-PERF и CLOSE.
- Portable B0.4-D run 34666975055 / job 103480745875 — SUCCESS, 287 assertions.
- Qualification reducer — PASS, blocking_total=0, READY_FOR_INDEPENDENT_REVIEW.
- Qualification tools — 40 adversarial/process tests PASS.
- Supplemental Python/Godot bit interoperability — 2064 patterns PASS:
  1081 допустимых сохранены bit-exact, 983 nonfinite/unsafe отклонены.
  Это НЕ independent Verifier и НЕ unseen physics holdout.

Важное ограничение: читайте PREFREEZE_AUDIT_RU.md. Отдельный server PERF вновь
FAIL как и baseline; proposed classification требует Reviewer/Director acknowledgment.
Шесть technical gates не означают, что весь GitHub CI зелёный.

## Независимая перепроверка

Берите qualification.py и policy из control tools commit c028efd2..., product
checkout — строго 989ed83c... . Сверьте main-owned Harness, а не старую policy из
research branch. Используйте --head/--tree и отдельно закреплённый
--policy-sha256 9fad301348bf9cedcb3251a317d880475fa0365541cdf958fee29a6915a1d721.
Команда и полное описание находятся в
`docs/research/FABRIC_HOLDOUT_R4_G2_QUALIFICATION_R1_RU.md`.
Существующие receipts собраны сохранённым exact-matrix driver и проверены reducer;
они не заявляются результатом запуска нового qualify.py. qualify.py отдельно
прошёл реальные process controls в 40-тестовой suite.

Положительный результат reducer — consistency self-validation, не аутентификация
автора, не независимое ревью, не freeze/acceptance. G1 остаётся FALSIFIED,
production freeze не выполнен, новый unseen corpus не раскрыт. Main не изменён.
