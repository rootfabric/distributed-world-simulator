# FABRIC R4.2 — Fresh Independent Verifier R1

```text
ROLE = VERIFIER
SUBJECT_HEAD = 33b06f9658fe3373d18893ab2292471a13d61894
SUBJECT_TREE = 56ca6be7249dfdb96a4cc62f4bdc4e27e508b4e9
PREREG_HEAD = b8fa56cc1bccf1d38b9882f735309402fc5cd014
PREREG_TREE = 86b04ad3bef1e6b77a9a510ff28cf89c8f7d9aa2
STATUS = PENDING_EXACT_CI
```

This verifier branch may change only this note and its verifier workflow.

Verifier duties:

- prove exact subject and preregistration ancestry;
- prove frozen generator/oracle/acceptance/runner paths are unchanged after preregistration;
- recompute the sealed fallback beacon;
- regenerate the unseen challenge from the frozen generator;
- verify exact bundle checksum and challenge SHA-256 against the durable commitment;
- run the frozen protocol/oracle and Godot acceptance on canonical Linux-double Godot;
- require 21/21 assertions, zero failures and the exact R4.2 result hash;
- upload verifier-owned evidence.

No product/runtime mutation, no tolerance change, no new challenge generation, and no alternate expected values are allowed.
