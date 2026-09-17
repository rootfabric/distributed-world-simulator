# MVP6 clearance R2 — verifier-readable evidence repair

Evidence-only repair for PR #650 verifier findings. Frozen control candidate remains `6902a99081c1fbdf676c71dca5ea0d80fd633267` / `f4ae35216de7ed915fcb0c46b03b0f35baeccd6b`; these files do not modify PR #649 source.

The two `*-manifest-summary.json` receipts mirror the original artifact manifests and summaries and bind the critical raw-report hashes/findings. Exact unit logs and the default-NX output are published as separate files so a reviewer checkout does not need Actions API access. `producer-review-lineage-receipt.json` binds the historical review object/blob/head and current producer ancestry/blob.

Original artifacts were downloaded through the repository GitHub connector and rehashed locally before publication: artifact `10475649047` = `9c78fe60...cb32c` with 17 manifest members and zero mismatches; artifact `10474045529` = `c1bca166...44c1` with 28 members and zero mismatches.

This is evidence availability repair only. It does not mark the clearance VERIFIED, does not merge PR #649/#650, and does not claim canonical PC0 NON_RED, NX acceptance, MVP6 acceptance or epoch audit.
