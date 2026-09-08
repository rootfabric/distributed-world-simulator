# Повторяемый аудит исходных CI-архивов

Это вспомогательное исполнение Implementer, не независимый Verifier. Код и результаты находятся в отдельной evidence-ветке и не изменяют frozen runtime62ae64d.

Скачать исходные ZIP через GitHub artifacts (не перепаковывать перед сравнением digest). Нужен Python3.10+ и разрешённый доступ к репозиторию. `audit_artifact.py` читает ZIP без извлечения файлов, сверяет ожидаемый SHA256, каждый member и command/result, exact HEAD/TREE/run/engine, отрицательные controls, полноценные результаты world/P7/control и не выдаёт acceptance.

```bash
python3 audit_artifact.py p7-control-62ae.zip 496676242011a3e704eac083dd1cfca54fdbe2c17bb62b0f1b9137f3f0aa672d
python3 audit_artifact.py p7-gate-62ae.zip 3c21a17ef85821e89e11a2a2de5153a9020d7bed8826dfed28500635f76a3b5b
python3 test_artifact_audit.py --control-zip p7-control-62ae.zip -v
```

Для world использовать digest из завершённого GitHub artifact, когда он появится. До этого итоговый пакет остаётся неполным. Скрипт ожидает только frozen run34189730552/attempt1; его нельзя молча использовать для другого кандидата.

Фактически выполнено локально: оба положительных аудита и15 unit-тестов fault injection. Они проверяют ZIP/member corruption, duplicate/path traversal, чужой HEAD, dirty checkout, ложный PASS, machine self-acceptance, mismatch command/result и строгое Booleanfalse для advisory PC0. Негативные архивы создаются только в TemporaryDirectory; исходные CI-архивы не меняются. Это не повтор выполнения Godot/world и не заменяет независимый анализ достаточности evidence.
