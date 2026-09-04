Use this lifecycle only while the resolved route is dispatchable. The normal
implementation route is `developing`; `review`, `merging`, and terminal states
are human-owned or stopped states and are deliberately absent from
`tracker.lifecycle.active_states`.

1. Read the Story through `tracker.issue_snapshot` and read or create exactly
   one canonical workpad through `tracker.upsert_workpad`. Keep its full body
   mirrored in workspace-root `.symphony-tapd-workpad.md`; never put that file
   under `repo/` or commit it.
2. Reconcile the workpad plan, acceptance criteria, and validation checklist.
   Record a concrete reproduction or baseline signal before editing code.
3. Synchronize `origin/{{ repo.base_branch }}` with the repo-core helper when
   needed, then use `repo_checkout` with the canonical mode
   `create_or_switch` to create a Story-specific branch. Confirm the branch is
   not `{{ repo.base_branch }}`
   and follows the configured work prefix before any commit or push.
4. Work only under `repo/`, implement the scoped change, and run every
   repository and Story-required validation step. Record commands and outcomes
   in the workpad.
5. Use `repo_diff` with its whitespace check enabled and verify that only the
   intended changes are present.
6. Use `repo_commit` with canonical mode `all` or `staged`. Never commit
   directly on the configured base branch.
7. Use `repo_push` to publish the working branch. A push is successful only
   when its `publishedHeadSha` equals `headSha`. If `repo_push` is not present
   in the inventory, use `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo push`
   and verify the remote branch SHA equals local `HEAD`.
8. After a successful push, update the canonical workpad and mirror with the
   remote repository, branch name, commit SHA, validation results, and
   reviewer-ready `suggested_mr_title` and `suggested_mr_description` text.
   These fields are handoff text only; do not create or update an MR.
9. Move the Story to the configured `review` raw state through the typed
   tracker move tool. Stop immediately after the state update succeeds because
   review is a human wait state and is not active for this template.

Push failure policy:

- For a non-fast-forward rejection, synchronize the configured base branch
  through the existing repo-core flow, resolve conflicts without rewriting
  unrelated history, rerun validation, then retry the normal push.
- For authentication, permission, protected-branch, missing SSH tooling, or
  host-key failures, stop and record the exact blocker. Do not rewrite the
  remote, switch transport protocols, expose credentials, or bypass policy.
- Never use `--force`. Use `--force-with-lease` only when the Story explicitly
  requires an intentional history rewrite and the repository policy permits it.
- Never push the configured base branch, and never use a work branch that does
  not satisfy the configured prefix policy.

If review requests changes, a human records the requirements in TAPD and moves
the Story back to `developing`. Maestro then resumes from the canonical workpad
and repeats implementation, validation, commit, push, SHA verification, and
handoff. It does not read hosting-platform review comments or pipeline state.
