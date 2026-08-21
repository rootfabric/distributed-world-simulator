# ECO EVO3 E3.5 — Multi-scale Population Workset Compiler — candidate checkpoint

State: **IMPLEMENTED_CANDIDATE / NOT ACCEPTED**

Base / accepted E3.4 control head: `872f2d993cc002b72529ea7f2a3274d0d71245b0`  
Executable freeze: `4625c950946f7a1b3cea67b9a1411fb993c20957`  
Current main policy head audited: `19c1268599b52cbc1099d6009eabd3099e20b64a`

## Exact machine result

E3.5 closure run `32380793912` / job `96463219073`: **SUCCESS**.

- semantic tests: `27/27`;
- authority regression tests: `20/20`;
- total: `47/47`;
- exact published closure: `8/8`;
- Draft 2020-12 schema: PASS;
- fresh processes: `2/2`, byte-identical;
- order independence: PASS;
- `NO_COLONIZATION`: PASS;
- RNG surface: ABSENT;
- individual entity truth: ABSENT;
- canonical SD authority: ABSENT;
- network/persistence/transaction authority: ABSENT.

Generated candidate:
- Git blob `212cbc08675d706233c13c15146f864981a9b5a8`;
- SHA-256 `0ea5351b7692564161804a3aea5fe5044f3321ded3dcb4d0c7343e93d52c4975`;
- workset hash `b8f30e129c0f714ebc937cdac6869e63223d8d72172cecb68dd049f604557ff5`;
- provenance hash `ec9c734882ef4a97eec2ed071f3c06ec2a29df52f13a45c7054a4641cbd42738`;
- active basis `22`, species `2`, patches `11`, scheduling regions `1`, work units `24`, individual entities `0`.

Evidence aggregate: `6db8c59276e6ac59c34fe43c04a10e179894d5698adbad18a434e43f6e3908d7`.

## Authority boundary

The accepted predecessor is exact E3.4 artifact blob `db725ef37912547527dff5fffe39ca63e5f8c22e`. Parsed dictionary aliases do not receive accepted-input attestation.

All four scale projections cover the same active basis exactly once. REGION and work-unit identities are research scheduling identities only; no canonical population registry or SD domain is created.

## Project Control

Project Control workflow `32380793808` / job `96463218395`: **SUCCESS**.

The generated PC0 and directional reports themselves are **RED** globally. This is preserved as evidence. Current main `19c1268599b52cbc1099d6009eabd3099e20b64a` declares ECO as explicit research non-blocker; no critical ECO directional/ownership/dependency intersection was observed. Therefore unrelated global RED does not by itself halt the research-review path, but it is not reinterpreted as project GREEN.

## Freeze boundary

Post-build evidence must not mutate the executable E3.5 closure. Reviewer must compare final evidence HEAD against `4625c950946f7a1b3cea67b9a1411fb993c20957` and confirm no compiler/test/schema/contract/runner/workflow drift.

## Remaining gates

1. evidence-only final HEAD + exact-head closure/Project Control refresh;
2. durable Evidence Map bound to exact final HEAD;
3. fresh independent Reviewer;
4. fresh independent Verifier after Reviewer PASS;
5. Director checkpoint proposal;
6. human merge/acceptance gate.

Until those gates complete: **E3.5 NOT ACCEPTED; E3.6 NOT AUTHORIZED; XFER1 BLOCKED; production ECO authority INACTIVE.**
