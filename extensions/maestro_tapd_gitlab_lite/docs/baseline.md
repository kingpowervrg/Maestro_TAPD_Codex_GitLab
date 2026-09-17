# Isolation baseline

The migration baseline is Core commit `33c970b`, with the pre-isolation Lite
implementation at `337d5b1`. The audited delta contains 126 Elixir-runtime files
and approximately 6,856 additions / 243 deletions. The characterization gate
before migration ran 94 focused tests for GitLab search, Git backend, object
cache, TAPD behavior, and templates with zero failures.

The original checkout at `/home/admin2/workspace_other/Maestro` must remain
read-only during this migration until its local
`elixir/test/symphony_elixir/repo_provider/github_test.exs` edit is explicitly
committed, stashed, or discarded by its owner. This repository does not mutate
that checkout.

Two real Bug pilot records remain in the existing private validation history;
only their behavior classes are retained here: successful verified push plus
policy completion, and guarded exceptional termination. No issue id, token,
repository URL, or credential is copied into this package.

