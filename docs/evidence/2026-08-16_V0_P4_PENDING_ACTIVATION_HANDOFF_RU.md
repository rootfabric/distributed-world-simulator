# V0-P4 pending activation handoff

If a new session resumes this branch before canonical V0 activation, it must not infer permission from branch-local control files.

Recover in this order:

1. fetch canonical `main`;
2. read canonical registry/frontiers/harness contracts from that exact main;
3. inspect the status of V0 activation PR #98 or its successor;
4. run/verify required post-main Project Control evidence;
5. compare the active P4 branch against its stacked base and against the newly authorized runtime base;
6. choose CONTINUE only if dependency/ownership audit permits it; otherwise record REFRESH_REQUIRED and transplant/rebase deliberately;
7. keep PR #117 separate unless independently accepted and explicitly scheduled for integration.

Last known canonical main at initial P4 dispatch:

`09714b6f2681e3b5cf3f2f9e28416cf9a7378304` / registry generation 79.

Stacked P4 base:

`ef3ad5f0afc433802d639171d938e4720b3a46ec`.
