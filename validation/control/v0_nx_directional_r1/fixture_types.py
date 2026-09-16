"""NX baseline fixture repair for V0-NX dependency revalidation only.

Repair Map: exact run 35088907198 fails before treatment on frozen NX test
70c9c162...: inferred Dictionary results are called through an untyped helper
return. Add only OwnerService variable annotations at two helper call sites in
each of the two affected tests. Runtime source, test expressions, assertions,
expected errors and order remain byte-identical. Apply the same adaptation to
both paired roots, retain before/after hashes and never update the NX branch.
This does not turn the historical frozen NX suite into an exact unmodified PASS.
"""
from __future__ import annotations
import hashlib

OLD = b'\tvar service = _configured_owner_service('
NEW = b'\tvar service: OwnerService = _configured_owner_service('
PINS = {
    'tests/network/test_nx_owner_movement_authority.gd': '70c9c1625cb86bcf1498b7d012862cc7c5219d8c',
    'tests/network/test_nx_owner_item_projection_rollback.gd': '58ac2dce2bc914080fa723e3e864a401ead00d45',
}


def adapt(path: str, data: bytes) -> bytes:
    if path not in PINS:
        return data
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if blob != PINS[path] or data.count(OLD) != 2 or NEW in data:
        raise RuntimeError('NX_TYPE_FIXTURE_INPUT_DRIFT:' + path)
    fixed = data.replace(OLD, NEW)
    if fixed.replace(NEW, OLD) != data:
        raise RuntimeError('NX_TYPE_FIXTURE_NOT_REVERSIBLE:' + path)
    return fixed
