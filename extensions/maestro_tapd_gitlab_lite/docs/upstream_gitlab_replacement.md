# Upstream GitLab replacement

Use this matrix before replacing the temporary backend:

| Capability | Lite backend | Required upstream result |
| --- | --- | --- |
| clone/fetch/checkout | Core Git SSH | equivalent or better |
| blob search | read-only HTTP API | equivalent, token-safe search |
| commit/push | Core Git SSH | preserve verified published SHA |
| merge request/review/pipeline/merge | intentionally absent | optional; remain human-owned until separately approved |
| object cache | extension overlay | public bootstrap hook or equivalent native support |

Migration procedure:

1. Register the upstream-compatible backend without changing the company TAPD
   policy or field configuration.
2. Run the shared Mode A/B policy suite and the Git contract tests.
3. Compare template inventory and token-redaction snapshots.
4. Delete each Lite capability only after the upstream implementation covers
   it. Disable the object-cache overlay if upstream provides an equivalent.
5. Keep a one-rollout compatibility switch, then remove the old backend and
   its GitLab-specific configuration.

Never combine backend replacement with TAPD field semantics, object-cache
policy, or tracker state-flow changes.

