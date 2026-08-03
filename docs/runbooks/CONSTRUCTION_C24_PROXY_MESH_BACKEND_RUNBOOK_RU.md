# C24 — GPU-Ready Proxy Mesh Backend Runbook

## Инварианты

1. `ArrayMesh`, material, RID и SceneTree node никогда не становятся authoritative state.
2. Mesh cache key равен validated C22 `content_hash`; source revision отдельно закреплён manifest/packet.
3. Один controller разделяет mesh resources между client runtimes, но каждый client имеет собственные nodes и interest state.
4. Failed packet apply сохраняет предыдущую presentation целиком.
5. После restart C22 artifacts восстанавливаются из persistence, C24 GPU resources создаются лениво.

## Focused запуск

Linux:

```bash
./RUN_C24_PROXY_MESH_BACKEND_TESTS.sh /path/to/godot.linuxbsd.editor.double.x86_64
```

Windows:

```powershell
.\RUN_C24_PROXY_MESH_BACKEND_TESTS.ps1 -GodotPath C:\Godot\godot.windows.editor.double.x86_64.console.exe
```

## Диагностика

Проверять `runtime.get_mesh_cache_stats()`:

- рост `misses` без новых content hashes означает потерю общего cache scope;
- рост `entries` выше configured budget означает ошибку eviction;
- `evictions` при обычном C22 fixture не ожидаются;
- `oversized_bypasses` допустим только для одиночного mesh больше configured byte-budget;
- material library обязана сохранять `entries <= max_entries`;
- разные mesh signatures для одного content hash являются release blocker;
- BoxMesh внутри `CompiledProxyMeshes` является regression blocker.

## Rollback

Rollback C24 возвращает прежний bounds-based backend только как аварийную presentation деградацию. C22 artifacts, persistence и authority state не требуют migration назад. Нельзя откатывать путем записи proxy geometry в Item Graph или `ConstructAggregate`.
