# WP-ASSET1 — Evidence: SSRF_REDIRECT_AND_SIZE_GATES

- Track: `WP-ASSET1`
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Implementation HEAD: `ad7dc25f1319669342a2342eea8bdbf24286a19d`
- Milestone: `SSRF_REDIRECT_AND_SIZE_GATES`
- Дата (UTC): 2026-09-05

## Что реализовано

`tools/world_packs/asset_fetch/gates.py` (stdlib-only: `ipaddress`,
`urllib.parse`; resolver инжектится — реального DNS в тестах нет):

- `validate_target`: https-only; запрет userinfo/credentials в URL;
  запрет fragment/`@` в authority; host только из approved set;
  whitelist портов (443); отказ literal private/loopback/link-local
  IP; опциональная DNS-проверка всех resolved адресов; declared-size
  gate (`DECLARED_SIZE_ABOVE_CEILING`, `DECLARED_SIZE_INVALID`).
- `check_resolved_addresses`: DNS-rebinding защита — отказ, если хотя
  бы один ответ resolver не public (private/loopback/link-local/
  reserved/multicast/unspecified, включая ipv4-mapped `::ffff:10.x`).
  Коды: `PRIVATE_ADDRESS_TARGET`, `RESOLUTION_EMPTY`,
  `RESOLUTION_FAILED`.
- `resolve_redirect_chain`: bounded redirect chain (default 3 hops),
  каждый hop полностью ревалидируется теми же gates; стартовый URL
  тоже валиден. Коды: `TOO_MANY_REDIRECTS`, `UNAPPROVED_HOST`,
  `NON_HTTPS_TARGET`, `CREDENTIALS_IN_URL`, ...

Streaming size gates остаются в `https.py` (bounded reads),
declared-size cross-check добавлен здесь.

## Negative fixtures (offline)

`tests/world_packs/asset_fetch/test_gates.py` (29 тестов):
http/ftp scheme, credentials, fragment, no-host, unapproved host,
запрещённый порт, cloud-metadata literal IP (169.254.169.254),
DNS-rebinding на 10.x/192.168.x/172.16.x/127.0.0.1/0.0.0.0/fd00::/
fe80::/::ffff:10.x, mixed public+private answers, empty/failing
resolver, declared size over-ceiling и <=0, redirect → unapproved
host / http downgrade / private IP / credentials / бесконечный loop.

## Запущенные проверки (точный HEAD `ad7dc25f`)

```
python -m pytest tests/world_packs/asset_fetch -q
75 passed
```

Реальных DNS/сетевых запросов не выполнялось.
