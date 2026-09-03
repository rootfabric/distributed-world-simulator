# SOURCE.md template

Copy this file as `SOURCE.md` into the asset directory
(`assets/third_party/<source>/<asset_name>/`) and fill every field.
`tools/world_packs/check_asset_ledger.gd` rejects directories whose `SOURCE.md`
is missing or incomplete.

```text
source_url: <exact download page or file URL>
creator: <author or vendor name>
asset: <asset/pack name and version downloaded>
download_date: <YYYY-MM-DD>
license: <SPDX id or exact license name>
license_url: <URL of the exact license text>
redistribution: <allowed | allowed-with-attribution | forbidden>
modifications: <none | describe>
checksum: sha256:<hex digest of the downloaded archive>
files_imported: <comma-separated list of files committed>
```

Notes:

- `redistribution: forbidden` or any uncertainty means the asset must not be
  committed; keep it out of git and record only a local evaluation note.
- `checksum` is computed on the original downloaded archive, before unpacking.
- `files_imported` lists exactly what entered the repository; anything not
  listed must not exist in the directory.
