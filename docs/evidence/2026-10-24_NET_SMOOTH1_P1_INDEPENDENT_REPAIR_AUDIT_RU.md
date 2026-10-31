# NET-SMOOTH1 P1 — независимая поправка evidence и ограничения приемки

Exact repair PR #852 from unchanged product R2.2 HEAD fb513173df4c73c607fd8cb6680ad108c76f41ac.

1. Source establishes two per-peer flush_outbound calls on old R2.2 COMPACT publication, but the fraction of slow frames coincident with COMPACT is not the pure performance savings from eliminating one traversal. Each individual packet still incurs canonical validation and transport work; checkpoint, render frame scheduling and host contention remain separate.
2. Original agent report said 86–97% of >25ms frames include a movement snapshot in EVERY run. The own AGG tuples show pair2-on = 79/124 = 63.7%, pair3-on = 399/473 = 84.4%, and the 6-run AGG interval is 63.7%–92.8%. This is coincidence, not sole root-cause proof. Original report remains retained as historical record; no retroactive modification to its raw data.
3. The old p1_report_gen.py hardcoded all six AGG values. New p1_tail_aggregates.py recomputes stats from COMPLETE immutable original server/trace.jsonl plus original manifest/report, uses strict header/run_id/clock/END/lost records checks, hashes all input files and preserves original normative FAIL. The generator now calls it and refuses to make a table when raw roots are unavailable. Python source CI tests include tampered footer and identity.
4. The six original raw Windows P0 roots are NOT in GitHub PR #852. The checked-in docs/evidence/data/*.forensics2.json are derived top20 snapshots only, insufficient to independently recompute full p99/population. For independent Windows acceptance supply raw file hashes and retained originals or equivalent independent raw reviewer. Never invent them.
5. The product dedicated SERVER already runs Godot with --headless in tools/net_smooth1/run_net_smooth1.py; merely proposing headless-server as future performance fix does not follow from the data.
6. The P1 branch now requires fail-closed partial batch receipt checks, deferred seam resync, real batch timestamp and strict P1 batch accounting. These changes were NOT included in the historical P1 Windows GUI matrix. That matrix remains PERF_FAIL. A new exact Windows/Linux native and fresh 3x120s Windows two-client test on the NEW branch tip is required; no acceptance/merge based on earlier runs.
7. #815 remains OPEN with historical checksum root cause unknown. Project Control RED and true multi-host SEAM-E2E separate.

VERDICT = SOURCE_REPAIR_CANDIDATE / ORIGINAL_PERF_FAIL / INDEPENDENT_GUI_NOT_RERUN / READY_FOR_MERGE=false.
