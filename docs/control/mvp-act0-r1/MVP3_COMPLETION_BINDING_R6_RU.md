# MVP3 R6 — каноническое подтверждение P6 completion

Уточнение R5 по независимому review `3996583920` на `963293b0...`.

P6GatewayCommandRoute принимает любой Dictionary outcome от handler и затем вызывает admission.complete. Простая проверка `outcome.success` после возвращения route не защищает ledger: отклонённая M3-команда уже могла попасть в APPLIED.

Исправление выполнено **через существующий injection port**, без правки P6 или создания нового replay owner. Test-only decorator CanonicalCompletion переадресует admit принятому P6MutationAdmission, а complete разрешает только после чтения успешного receipt у настоящего M3 Service и проверки canonical logical/entity identity. Неуспешный handler оставляет исходный fail-closed PENDING, который нельзя превращать в applied carrying operation. Его дальнейшее согласование — отдельный recovery path, не повторное исполнение handler.

Новый тест наследует весь R5 bound-route scenario и добавляет настоящий M3 rejection: новая OperationId со старым input_sequence. Проверяются отказ completion, отсутствие мутации, отсутствие операции в carried_operations и повторный отказ без исполнения.

Это устраняет дополнительный completion-стык, указанный ревьюером. Поэтому предложение изменения production scope остаётся ограничено live-player staging/activation hooks и реальной M3 network/fixed-tick привязкой. Повторно реализовывать SM1 freeze/warm/commit не требуется. Отсутствие готовой live staging операции нельзя заменять ни successful WARM projection, ни переносом целого M6 aggregate.

Результаты R4/R5/R6 — characterization и test-only assembly. Они не являются playable MVP3, не доказывают два графических клиента через сетевой шов и не дают разрешения на VERIFIED/merge. Production code в этом carrier не меняется.
