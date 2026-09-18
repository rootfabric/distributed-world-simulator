# MVP6 Exact R6 — watchdog syntax repair

Validation-only trigger after fixing the R5 infrastructure SyntaxError.

- MVP6 product/runtime code is unchanged from the R4 product subject;
- world/core wrapper has a 3600-second fail-closed watchdog;
- outer CI budget is 70 minutes;
- raw partial world/core evidence is mirrored even on timeout;
- validator Python sources are compiled before the long gate;
- no predicate verification, acceptance, or merge authorization is claimed.
