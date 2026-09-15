"""A9 conservative ecological representations; not a biological transition kernel.

Admission is a trusted native A8 service. A packet hash and an origin hash must
come from the caller's durable acknowledgement, not from the loaded packet.
Lossy modes explicitly cannot execute/reconstruct historical individuals alone.
"""
from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
import hashlib
import json
import re
from typing import Callable, Iterable
import zlib

SCHEMA = 'dws.ecology.fidelity-packet.v1'
ADMISSION = 'dws.ecology.fidelity-admission.v1'
MAX_INT = 9007199254740991
MAX_RAW = 2097152
MAX_PACKET = MAX_RAW  # Must fit unchanged A8 SnapshotStore.MAX_SNAPSHOT_BYTES.
MAX_MEMBERS = 512
MODES = ('FULL', 'REDUCED', 'PATCH', 'AGGREGATE')
RESOURCES = ('material_mg', 'water_mg', 'energy_mj')
ACCOUNTS = ('initial', 'external', 'current', 'sinks')
COUNTS = ('living', 'dead_provenance', 'corpses', 'pending_propagules')
FIELD_STOCKS = ('water_mg', 'organic_mg', 'nutrient_mg')
SITES = ('dark', 'dry', 'wet')
SHA = re.compile(r'[0-9a-f]{64}\Z')
IDENT = re.compile(r'[a-zA-Z0-9_.:/-]{1,128}\Z')
SOURCE_FIELDS = ('snapshot_sha256', 'origin_sha256', 'ecology_sha256', 'entity_id',
                 'region_id', 'owner_id', 'owner_epoch', 'revision', 'ecology_step',
                 'clock', 'ticket_state')
TICKETS = ('NONE', 'REQUESTED', 'PREPARING', 'FROZEN', 'SNAPSHOT_READY',
           'TARGET_PREPARED', 'COMMITTED', 'ABORTED', 'EXPIRED')
Admit = Callable[[bytes, str, str], dict]


class FidelityError(ValueError):
    pass


class RefinementRequired(FidelityError):
    pass


def require(ok: bool, message: str) -> None:
    if not ok:
        raise FidelityError(message)


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False, allow_nan=False).encode('utf-8')


def _pairs(items: list[tuple[str, object]]) -> dict:
    out: dict = {}
    for key, value in items:
        require(key not in out, 'DUPLICATE_JSON_KEY')
        out[key] = value
    return out


def _decode(raw: bytes, limit: int, canonical_required: bool = False) -> dict:
    require(type(raw) is bytes and 0 < len(raw) <= limit, 'BYTE_BUDGET')
    try:
        value = json.loads(raw, object_pairs_hook=_pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(FidelityError('NONFINITE_JSON')))
        require(type(value) is dict, 'OBJECT_REQUIRED')
        if canonical_required:
            require(canonical(value) == raw, 'NONCANONICAL_PACKET')
        return value
    except (UnicodeError, json.JSONDecodeError, RecursionError, OverflowError) as exc:
        raise FidelityError('INVALID_JSON') from exc


def _keys(value: object, names: Iterable[str]) -> None:
    require(type(value) is dict and set(value) == set(names), 'SCHEMA_KEYS')


def _int(value: object, low: int = 0, high: int = MAX_INT) -> None:
    require(type(value) is int and low <= value <= high, 'INTEGER_RANGE')


def _hash(value: object) -> None:
    require(type(value) is str and SHA.fullmatch(value) is not None, 'EXTERNAL_HASH_REQUIRED')


def _id(value: object) -> None:
    require(type(value) is str and IDENT.fullmatch(value) is not None, 'IDENTIFIER')


def _stock(value: object, names: Iterable[str]) -> None:
    _keys(value, names)
    for amount in value.values():
        _int(amount)


def _sum(target: dict, source: dict) -> None:
    for key in target:
        total = target[key] + source[key]
        _int(total)
        target[key] = total


def _accounts(value: object) -> None:
    _keys(value, ACCOUNTS)
    for account in value.values():
        _stock(account, RESOURCES)
    for key in RESOURCES:
        left = value['initial'][key] + value['external'][key]
        right = value['current'][key] + value['sinks'][key]
        _int(left); _int(right)
        require(left == right, 'CONSERVATION_' + key)


def _totals(rows: list[dict]) -> dict:
    result = {'accounts': {a: dict.fromkeys(RESOURCES, 0) for a in ACCOUNTS},
              'counts': dict.fromkeys(COUNTS, 0), 'field_stocks': dict.fromkeys(FIELD_STOCKS, 0)}
    for row in rows:
        for a in ACCOUNTS:
            _sum(result['accounts'][a], row['accounts'][a])
        _sum(result['counts'], row['counts'])
        _sum(result['field_stocks'], row['field_stocks'])
    _accounts(result['accounts'])
    return result


def _source(value: object) -> None:
    _keys(value, SOURCE_FIELDS)
    for key in ('snapshot_sha256', 'origin_sha256', 'ecology_sha256'):
        _hash(value[key])
    for key in ('entity_id', 'region_id', 'owner_id'):
        _id(value[key])
    for key in ('owner_epoch', 'revision', 'ecology_step', 'clock'):
        _int(value[key], 1 if key == 'owner_epoch' else 0)
    require(value['ecology_step'] <= 16 and value['revision'] <= 96, 'A8_CURSOR_BUDGET')
    require(type(value['ticket_state']) is str and value['ticket_state'] in TICKETS, 'TICKET_STATE')


def binding(raw: bytes, expected_sha: str, expected_origin: str) -> dict:
    _hash(expected_sha); _hash(expected_origin)
    require(type(raw) is bytes and digest(raw) == expected_sha, 'SOURCE_HASH_MISMATCH')
    v = _decode(raw, MAX_RAW)
    _keys(v, ('schema', 'origin', 'cut', 'commands'))
    require(v['schema'] == 'dws.ecology.snapshot-seam.v1', 'A8_SCHEMA')
    o, c = v['origin'], v['cut']
    _keys(o, ('entity_id', 'region_id', 'owner_id', 'owner_epoch', 'treatment', 'experiment_hash'))
    _keys(c, ('owner_id', 'owner_epoch', 'revision', 'clock', 'ecology_step', 'ecology_payload', 'ticket'))
    require(digest(canonical(o)) == expected_origin, 'ORIGIN_MISMATCH')
    require(type(c['ecology_payload']) is str and type(c['ticket']) is dict, 'A8_PAYLOAD_TYPE')
    result = {'snapshot_sha256': expected_sha, 'origin_sha256': expected_origin,
              'ecology_sha256': digest(c['ecology_payload'].encode()),
              'entity_id': o['entity_id'], 'region_id': o['region_id'],
              **{k: c[k] for k in ('owner_id', 'owner_epoch', 'revision', 'ecology_step', 'clock')},
              'ticket_state': c['ticket'].get('state', 'NONE')}
    _source(result)
    return result


def _projection(value: object, mode: str, source: dict) -> None:
    if mode == 'AGGREGATE':
        _keys(value, ('accounts', 'counts', 'field_stocks'))
        _accounts(value['accounts']); _stock(value['counts'], COUNTS); _stock(value['field_stocks'], FIELD_STOCKS)
        require(value['counts']['corpses'] <= value['counts']['dead_provenance'], 'CORPSE_COUNT')
        require(value['accounts']['current']['material_mg'] >= value['field_stocks']['organic_mg'] + value['field_stocks']['nutrient_mg'], 'FIELD_MATERIAL')
        require(value['accounts']['current']['water_mg'] >= value['field_stocks']['water_mg'], 'FIELD_WATER')
        return
    require(type(value) is list and len(value) == 3, 'PATCH_COUNT')
    require([p.get('id') for p in value if type(p) is dict] == list(SITES), 'PATCH_IDENTITIES')
    for row in value:
        _keys(row, ('id', 'field', 'field_stocks', 'accounts', 'counts', 'cohorts'))
        _keys(row['field'], ('owner_token', 'owner_epoch', 'revision', 'tick', 'sha256'))
        _id(row['field']['owner_token']); _hash(row['field']['sha256'])
        for k in ('owner_epoch', 'revision', 'tick'):
            _int(row['field'][k], 1 if k == 'owner_epoch' else 0)
        require(row['field']['tick'] == source['ecology_step'], 'INCONSISTENT_FIELD_CUT')
        _accounts(row['accounts']); _stock(row['counts'], COUNTS); _stock(row['field_stocks'], FIELD_STOCKS)
        require(row['counts']['living'] + row['counts']['dead_provenance'] <= 32, 'POPULATION_BUDGET')
        require(row['counts']['corpses'] <= row['counts']['dead_provenance'], 'CORPSE_COUNT')
        cohorts = row['cohorts']
        require(type(cohorts) is list and len(cohorts) <= 32, 'COHORT_BUDGET')
        prior = ''; living = 0; dead = 0
        for cohort in cohorts:
            _keys(cohort, ('blueprint_hash', 'living', 'dead_provenance'))
            _hash(cohort['blueprint_hash']); _int(cohort['living']); _int(cohort['dead_provenance'])
            require(cohort['blueprint_hash'] > prior, 'COHORT_ORDER_OR_DUPLICATE')
            prior = cohort['blueprint_hash']; living += cohort['living']; dead += cohort['dead_provenance']
        require((living, dead) == (row['counts']['living'], row['counts']['dead_provenance']), 'COHORT_COUNT_MISMATCH')
    _projection(_totals(value), 'AGGREGATE', source)


def _unpack(doc: dict) -> bytes:
    if doc['mode'] not in ('FULL', 'REDUCED'):
        raise RefinementRequired('REFINEMENT_REQUIRED: exact historical source is not retained')
    if doc['mode'] == 'FULL':
        raw = doc['payload'].encode('utf-8')
    else:
        try:
            compressed = base64.b64decode(doc['payload'], validate=True)
            require(base64.b64encode(compressed).decode() == doc['payload'], 'BASE64_CANONICAL')
            decoder = zlib.decompressobj()
            raw = decoder.decompress(compressed, MAX_RAW + 1)
            require(len(raw) <= MAX_RAW and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
                    'DECOMPRESSION_BOUNDARY')
        except (ValueError, zlib.error, binascii.Error) as exc:
            raise FidelityError('COMPRESSED_PAYLOAD_INVALID') from exc
    require(0 < len(raw) <= MAX_RAW, 'RAW_BYTE_BUDGET')
    require(binding(raw, doc['source']['snapshot_sha256'], doc['source']['origin_sha256']) == doc['source'], 'SOURCE_BINDING')
    return raw


def _validate(doc: dict) -> None:
    _keys(doc, ('schema', 'mode', 'source', 'projection', 'encoding', 'payload'))
    require(doc['schema'] == SCHEMA and type(doc['mode']) is str and doc['mode'] in MODES, 'FIDELITY_VERSION_OR_MODE')
    _source(doc['source']); _projection(doc['projection'], doc['mode'], doc['source'])
    require(type(doc['payload']) is str, 'PAYLOAD_TYPE')
    encoding = {'FULL': 'utf8', 'REDUCED': 'zlib-base64', 'PATCH': 'none', 'AGGREGATE': 'none'}[doc['mode']]
    require(doc['encoding'] == encoding, 'ENCODING_MODE_MISMATCH')
    if doc['mode'] in ('FULL', 'REDUCED'):
        _unpack(doc)
    else:
        require(doc['payload'] == '', 'LOSSY_PAYLOAD_FORBIDDEN')


@dataclass(frozen=True)
class FidelityRecord:
    """Immutable representation of one admitted A8 coupled partition cut."""
    data: bytes

    def __post_init__(self) -> None:
        _validate(_decode(self.data, MAX_PACKET, True))

    @classmethod
    def from_snapshot(cls, raw: bytes, expected_sha: str, expected_origin: str, admit: Admit) -> 'FidelityRecord':
        source = binding(raw, expected_sha, expected_origin)
        require(callable(admit), 'NATIVE_ADMISSION_REQUIRED')
        admission = admit(raw, expected_sha, expected_origin)
        _keys(admission, ('schema', 'success', 'source', 'patches'))
        require(admission['schema'] == ADMISSION and admission['success'] is True and admission['source'] == source,
                'NATIVE_ADMISSION_MISMATCH')
        _projection(admission['patches'], 'FULL', source)
        return cls(canonical({'schema': SCHEMA, 'mode': 'FULL', 'source': source,
                              'projection': admission['patches'], 'encoding': 'utf8', 'payload': raw.decode('utf-8')}))

    @classmethod
    def restore(cls, packet: bytes, expected_packet_sha: str, expected_origin: str) -> 'FidelityRecord':
        _hash(expected_packet_sha); _hash(expected_origin)
        require(type(packet) is bytes and digest(packet) == expected_packet_sha, 'PACKET_ANCHOR_MISMATCH')
        result = cls(packet)
        require(result.source()['origin_sha256'] == expected_origin, 'ORIGIN_MISMATCH')
        return result

    def document(self) -> dict:
        return _decode(self.data, MAX_PACKET, True)

    def source(self) -> dict:
        return self.document()['source']

    @property
    def sha256(self) -> str:
        return digest(self.data)

    @property
    def mode(self) -> str:
        return self.document()['mode']

    def execution_snapshot(self) -> bytes:
        """Caller must still submit commands to the native A8 owner fence."""
        return _unpack(self.document())

    def totals(self) -> dict:
        doc = self.document()
        return doc['projection'] if doc['mode'] == 'AGGREGATE' else _totals(doc['projection'])

    def convert(self, target: str) -> 'FidelityRecord':
        require(type(target) is str and target in MODES, 'FIDELITY_MODE')
        doc = self.document(); old = doc['mode']
        if target == old:
            return self
        if (old == 'AGGREGATE' and target != 'AGGREGATE') or (old == 'PATCH' and target in ('FULL', 'REDUCED')):
            raise RefinementRequired('EXTERNAL_EXACT_SNAPSHOT_REQUIRED')
        if target in ('FULL', 'REDUCED'):
            raw = _unpack(doc)
            doc['payload'] = raw.decode('utf-8') if target == 'FULL' else base64.b64encode(zlib.compress(raw, 9)).decode('ascii')
            doc['encoding'] = 'utf8' if target == 'FULL' else 'zlib-base64'
        else:
            if target == 'AGGREGATE':
                doc['projection'] = _totals(doc['projection'])
            doc['payload'] = ''; doc['encoding'] = 'none'
        doc['mode'] = target
        return FidelityRecord(canonical(doc))

    def refine(self, exact_snapshot: bytes, admit: Admit) -> 'FidelityRecord':
        source = self.source()
        full = FidelityRecord.from_snapshot(exact_snapshot, source['snapshot_sha256'], source['origin_sha256'], admit)
        require(full.convert(self.mode).document()['projection'] == self.document()['projection'], 'REFINEMENT_PROJECTION_MISMATCH')
        require(full.source() == source, 'REFINEMENT_CURSOR_MISMATCH')
        return full

    def render_view(self, lod: str) -> dict:
        require(lod in ('DETAIL', 'SUMMARY', 'HIDDEN') and type(lod) is str, 'RENDER_LOD')
        return {'render_lod': lod, 'packet_sha256': self.sha256, 'source': self.source(),
                'fidelity': self.mode, 'exact_history_retained': self.mode in ('FULL', 'REDUCED'),
                'visible_summary': None if lod == 'HIDDEN' else self.totals()}


def aggregate(records: Iterable[FidelityRecord]) -> bytes:
    """Non-authoritative report, never a reconstructable or spendable world cut."""
    sources: dict[tuple[str, str], dict] = {}; rows: list[dict] = []
    for record in records:
        require(len(sources) < MAX_MEMBERS, 'AGGREGATION_BUDGET')
        require(type(record) is FidelityRecord, 'RECORD_REQUIRED')
        source = record.source(); key = (source['region_id'], source['entity_id'])
        require(key not in sources, 'DUPLICATE_PARTITION_OR_MIXED_EPOCH')
        sources[key] = source; rows.append(record.totals())
    require(bool(sources), 'EMPTY_AGGREGATION')
    packet = canonical({'schema': 'dws.ecology.fidelity-batch-report.v1',
                        'authority': 'REPORT_ONLY_NOT_SPENDABLE',
                        'historical_reconstruction': False,
                        'sources': [sources[k] for k in sorted(sources)], 'totals': _totals(rows)})
    require(len(packet) <= MAX_PACKET, 'AGGREGATE_BYTE_BUDGET')
    return packet
