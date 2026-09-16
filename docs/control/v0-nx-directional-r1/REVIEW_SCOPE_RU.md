# V0→NX — границы независимой проверки

Задача: V0-NX-MVP6-DIRECTIONAL-20260916-R1 / Repair R2.

## Что изменено

1. Новый воспроизводимый стенд сравнивает current-main + NX до и после замены только M4 facade на точные байты V0. В обоих составах одинаковые исправленный журнал предсказаний и явно объявленные type-only адаптации NX.
2. Исправлен существующий `predicted_item_interaction_journal.gd`: ветка duplicate revision/checksum пересобирает derived projection после удаления prediction. Каноническое состояние не изменяется. Предшествующий baseline-фальсификатор не удалён.
3. Отдельный стенд проверяет неизменённый clearance resolver: совпадение точной идентичности, отказ при дрейфе blob/предка/head/паспорта/набора watched paths, отсутствие self-clear из unmerged checkout.
4. Полный Harness и стандартный/directional аудит запускаются в отдельном локальном clone с явно обозначенной NON_AUTHORIZING_CANDIDATE_PROJECTION. В ней только для испытания используются SIMULATED_* evidence IDs. Они не являются ревью или верификацией и никогда не должны попасть в main.

## Что НЕ утверждается

- Raw frozen NX source не прошёл current-main compilation: исходные тесты и одна переменная OwnerService потребовали явных типов. Преобразования обратимы, входные blob и выходные SHA256 фиксируются. Это не NX.C1 acceptance.
- Native V0 проверки ограничены точным 9a4d4257; более поздние commits допустимы для этого dependency clearance только при сохранении ancestor/blob/полного hit set.
- A9 runtime не изменён. MVP6 целиком не принят, активные ветки V0/NX не изменены.
- Canonical clearance registry пока не изменён. Proposal имеет PROPOSED и пустые независимые evidence IDs. Global RED не закрыт.

## Reviewer

Проверить реальный минимальный journal diff, негативный pre-fix контроль и post-fix siblings, exact V0 M4 facade по 44841fb3719b1cf36fd5afdfc0f8a0e4d0eacb30, полноту NX-совместимости, оправданность узкого clearance несмотря на явно отделённый raw NX compilation gap, отсутствие ослабления safeguards/подмены authority. При недостаточной доказательной базе потребовать FIX_REQUIRED, не выдавать формальный PASS.

## Verifier / final gates

Проверить raw logs и manifest SHA256, pinned Linux double, все runtime стадии и отсутствие GDScript errors под PASS marker. Сверить HEAD/TREE, исходные/адаптированные bytes и единственное различие пары. Отдельно подтвердить full Harness/no skips и отрицательный self-clear контроль.

После двух подтверждений разрешено подготовить append-only запись в main-owned registry с реальными независимыми IDs; это новый control candidate, требующий проверки. Фактический merge и canonical-main post-merge PC — отдельный human gate. До него не писать CLOSED/COMPLETE_MERGED.
