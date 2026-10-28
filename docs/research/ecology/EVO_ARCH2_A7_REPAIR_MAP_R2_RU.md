# A7 Repair Map R2 — full-horizon viewport

Work Order: EVO-ARCH2-A7-20260912-R1. Owner: A7 presentation only. Это bounded post-build correction, не изменение A6 ecology.

## Воспроизводимый дефект

Дополнительный actual viewport probe довёл стандартный seed20260912 до horizon16. Старый BodyView blobd4ba98fcb41af490842ed3fac8b7bab2ba8ef108 использовал фиксированные2.4px/mm и ground=56% высоты. При панели465×341 px верх реального wet phenotype вышел на y=-39.30965 px, низ на303.184. Старый UI gate снимал только tick6 и не видел обрезку позднего роста. Нельзя скрывать выросший reproductive/collector module за clip и утверждать полное представление.

## Исправление

Фиксированное физическое поле зрения200×200mm: projected X от-100 до100, Y от-130 до70. Оно НЕ подгоняется по фактическому телу, поэтому сравнимость размеров во времени не теряется. Общий px/mm вычисляется из наименьшей панели и синхронизируется при resize. Три сайта используют один масштаб, grid соответствует10mm, scale bar20mm. Полный X/Y/Z и area/reach proxies сохраняются. Runtime state/genotype/ledger не меняются.

UI oracle теперь выполняет полный horizon16, проверяет bounds всего study body включая radius/area/reach proxies во всех трёх панелях и одинаковый scale. Счётчики: headless30, graphical32. Source binding, pause/step/speed/reset/save/load и mutation-free drawing controls сохранены. Core158, A6 и все предшествующие tests не менялись.

Локальный focused graphicalR2:32/32PASS и настоящий viewport1440×960 на tick16; screenshot и source report должны войти в final exact evidence. Это не PASS будущего опубликованного HEAD. Во время prepublication исправлена обязательная GDScript Vector2 аннотация canvas. Все пять опубликованных blobs отдельно сверены с локальными Git hashes.

## Исполнение / предотвращение ложного PASS

Предыдущий local full run45076dcd был прерван verifier-ом после A6 adversarial из-за конфликта addon port9081 с отдельно запущенным нашим viewport probe. Assertions76 прошли, но ERROR marker сделал общий результат FAIL. Этот запуск не выдаётся за regression PASS. Последующие локальные Godot проверки исполняются строго последовательно; source/error gates не ослабляются. Remote runs на отдельных exact subjects не наследуют local PASS.

Final review и полный exact verifier обязательны на новом frozen HEAD/TREE. Earlier7f5e072e evidence остаётся historical после renderer update. Research acceptance/main merge не выполняются этим repair.
