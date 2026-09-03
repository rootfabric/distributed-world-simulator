# FABRIC.SYNC3 — Authorization Evidence

## Qualification

```text
FABRIC.SYNC3
POST-B0.4 + B0.5-P0 DEVELOPMENT REVIEW
CLOSED

B0.5-A EXECUTABLE HYBRID BAKE:
AUTHORIZED

FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2 EXECUTABLE:
NOT AUTHORIZED

BRIDGE-2 DESIGN/PREFLIGHT:
ALLOWED

PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

## Two-parent integration boundary

```text
B0.4 closure parent:
1e8324407f60b4536bf9497e0a7c8a6874ae93ca

B0.5-P0 closure parent:
d280096e0b64c03ac613e586881e43c816f471f0

integration commit:
91132efab20579fa2e64dc2fb9e0dc074c66179e

integration TREE:
fd745f5e0c6d37db6b468c8695361af43d891245
```

The exact B0.5-P0 contract/test blobs are integrated with the B0.4 closure lineage.
The roadmap conflict is intentionally resolved by the newer B0.4 closure and the
SYNC-3 decision.

## Decision subject

```text
HEAD:
1b2bbe7870ac1c6d67b7a6b8d96fbfe681f8b943

TREE:
59ff93703faebae85a9949f1a0205333558140c1
```

## Control evidence

```text
Project Control:
33704262729
SUCCESS

B0.5-P0 Exact Source Carrier:
33704262846
SUCCESS

B0.4-A Exact Source Carrier:
33704262704
SUCCESS

B0.4-B Exact Source Carrier:
33704262720
SUCCESS

B0.4-C Exact Source Carrier:
33704262649
SUCCESS

B0.4-D Exact Source Carrier:
33704262736
SUCCESS
```

## Authorization

B0.5-A may begin executable research on the generic two-mode falsifier defined in
`docs/research/FABRIC_BAKE_B0_5_A_EXECUTABLE_HYBRID_AUTHORIZATION_RU.md`.

The implementation must consume the common B0.4 PhysicalBakeArtifact,
StateMapping and ReconstructionDescriptor interfaces.

## Verdict

```text
FABRIC.SYNC3
VERIFIED / CLOSED

next executable:
B0.5-A EXECUTABLE HYBRID BAKE
```
