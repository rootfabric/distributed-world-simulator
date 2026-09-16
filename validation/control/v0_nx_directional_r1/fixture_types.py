"""Type-only current-main/NX composition adapters, NOT raw NX acceptance.

R2/35088907198: two frozen tests infer results through an untyped helper.
R3/35089246815: frozen OwnerService also infers a Dictionary from the now
untyped current-main _movement dependency. Test-only adapters below add
explicit types, preserving expressions/assertions/ordering in BOTH pair roots.
The tick test's Variant loop operand is made explicitly int for the same reason.
No active NX/V0 branch or production file is modified. Original NX compilation
remains an independently tracked gap; these results must not be called exact
unmodified NX SOURCE_ACCEPTED or NX.C1 runtime PASS.
"""
from __future__ import annotations
import hashlib

RULES = {
    'tests/network/test_nx_owner_movement_authority.gd': (
        '70c9c1625cb86bcf1498b7d012862cc7c5219d8c',
        b'\tvar service = _configured_owner_service(',
        b'\tvar service: OwnerService = _configured_owner_service(', 2),
    'tests/network/test_nx_owner_item_projection_rollback.gd': (
        '58ac2dce2bc914080fa723e3e864a401ead00d45',
        b'\tvar service = _configured_owner_service(',
        b'\tvar service: OwnerService = _configured_owner_service(', 2),
    'scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd': (
        'f3231004bc32ea54028243111859966f08200d4f',
        b'\tvar validation := _movement.apply_authoritative_state(',
        b'\tvar validation: Dictionary = _movement.apply_authoritative_state(', 1),
    'tests/network/test_nx_client_tick_robustness.gd': (
        '9e519b1a20caca30042ea69e4686374b8ea1b0ee',
        b'\t\tvar candidate := reference + offset',
        b'\t\tvar candidate: int = reference + offset', 1),
}


def adapt(path: str, data: bytes) -> bytes:
    if path not in RULES:
        return data
    expected, old, new, count = RULES[path]
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if blob != expected or data.count(old) != count or new in data:
        raise RuntimeError('NX_TYPE_ADAPTER_INPUT_DRIFT:' + path)
    fixed = data.replace(old, new)
    if fixed.replace(new, old) != data:
        raise RuntimeError('NX_TYPE_ADAPTER_NOT_REVERSIBLE:' + path)
    return fixed
