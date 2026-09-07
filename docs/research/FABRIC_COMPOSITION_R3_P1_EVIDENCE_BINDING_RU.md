# R3 P1 — exact evidence binding, без изменения subject

Frozen runtime HEAD: `fd6e83b35301d7a15e92c55939654f1f95729730`.
Frozen runtime TREE: `314330d717db059cd9b9db32c5d6150097e1f2c3`.

Основной manifest: `validation/fabric-composition-r3-p1-exact-evidence.json`.
Он относится только к указанному subject, а не к собственной evidence-ветке.
Старый `validation/fabric-composition-r3-local-evidence.json` сохранён byte-for-byte и относится к pre-repair `ddf2b2c`; его нельзя использовать как проверку нового runtime. Этот отдельный пакет закрывает provenance finding review 5132274401 / discussion_r3949966108; независимый verdict ещё требуется.

Полные raw logs всех пяти gates находятся в двух JSON envelopes, gzip+base64 с SHA256 распакованных байтов. Это сжатие, не excerpt. До публикации были выполнены decode, byte-count и SHA256 проверки. GitHub blob IDs каждого envelope совпали с локальным `git hash-object`: import `9a94d826167b277c1e3a8fc60d37a7b4c93d1997`, suites `2fc09534030b6aaba3fee0c5d22ba05692c34cb3`, manifest `f7874756a92475ab8f34e2b2c63d5d57485d0e98`.

Промежуточная публикация `36a7b0fd2e0674cf21cd0801bb477e24a5dcac31` содержала ошибочный encoded payload и НЕ является evidence для принятия. Она исправлена новым commit без rewrite истории. Ни runtime, ни фактические raw logs не менялись.

Exact локальный repository runner завершён exit 0: fresh import; R3 187/0; transient 611/0; observer; separate-process replay; pending/committed replay; R2 три suite; R1 integrity 42/0; Xvfb/Mesa render; fatal scan; clean tracked checkout. Первый orchestration attempt прерван лимитом 200 секунд контейнерного вызова: это incomplete, не PASS. Повторный полный запуск успешен и его raw logs включены здесь. Remote CI 34124264330 на subject находится в отдельной очереди и не подменяется этим локальным результатом.

## Проверка получателем

Из clean checkout evidence-ветки выполнить следующий код. Он читает actual immutable runtime source через `git show`, а не приписывает evidence-commit результат runtime-тестов:

```python
import base64
import gzip
import hashlib
import json
import subprocess
from pathlib import Path

root = Path.cwd()
manifest = json.loads((root / 'validation/fabric-composition-r3-p1-exact-evidence.json').read_text())
head = manifest['subject_head']
actual_tree = subprocess.check_output(['git', 'rev-parse', f'{head}^{{tree}}'], text=True).strip()
assert actual_tree == manifest['subject_tree']
for path, expected in manifest['source_sha256'].items():
    data = subprocess.check_output(['git', 'show', f'{head}:{path}'])
    assert hashlib.sha256(data).hexdigest() == expected, path
logs = {}
for key, path in manifest['raw_log_files'].items():
    data = (root / path).read_bytes()
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert blob == manifest['raw_log_git_blobs'][key], path
    envelope = json.loads(data)
    entries = envelope.get('raw_logs', {envelope.get('name', ''): envelope})
    for name, entry in entries.items():
        raw = gzip.decompress(base64.b64decode(entry['content'], validate=True))
        assert len(raw) == entry['size_bytes'], name
        assert hashlib.sha256(raw).hexdigest() == entry['sha256'], name
        logs[name] = raw.decode()
assert 'R3_ASSERTIONS=187 FAILURES=0' in logs['r3.log']
assert 'R3_TRANSIENT_ASSERTIONS=611 FAILURES=0' in logs['r3.log']
assert 'FABRIC-COMPOSITION-R3-PROCESS-READ: PASS' in logs['r3.log']
assert 'FABRIC-COMPOSITION-R3-RENDER: PASS' in logs['render.log']
assert all(line.split('\t')[1:] == ['0', '0'] for line in manifest['exits'].splitlines())
print('R3_EXACT_EVIDENCE_BYTES_AND_SOURCE_BINDING=PASS')
```

Это verification procedure, не независимый verdict автора. Fresh Reviewer/Verifier обязан сам оценить trust/provenance, достаточность и ограничения. Research/source closure не является canonical main acceptance, merge или production activation. До итогового независимого решения HOLDOUT-R4 не активирован.
