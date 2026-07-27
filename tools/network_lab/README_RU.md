# Network Lab — план локального стенда

Эта директория зарезервирована для Python harness, который будет запускать несколько Godot headless-процессов.

Первая реализация должна появиться на этапе N2.

Планируемые команды:

```bash
python tools/network_lab/network_lab.py doctor
python tools/network_lab/network_lab.py run single-authority
python tools/network_lab/network_lab.py run object-handoff
python tools/network_lab/network_lab.py up --topology config/network/local-lab.example.json
python tools/network_lab/network_lab.py down --run-id latest
```

`doctor` проверяет:

- путь к double Godot;
- версию движка;
- Python;
- pytest;
- Docker при необходимости;
- доступность портов;
- возможность создать изолированный `user://`;
- чистое завершение headless process.

До появления реального кода этот файл является контрактом CLI, а не утверждением, что команды уже реализованы.
