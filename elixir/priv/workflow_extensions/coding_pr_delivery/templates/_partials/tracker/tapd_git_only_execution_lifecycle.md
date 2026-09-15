Use this lifecycle only while the resolved route is dispatchable. The normal
implementation route is `developing`; `review`, `merging`, and terminal states
are human-owned or stopped states and are deliberately absent from
`tracker.lifecycle.active_states`.

1. Read the {% if issue.entity_type == "bug" %}Bug{% else %}Story{% endif %} through `tracker.issue_snapshot` with comments included. {% if issue.entity_type == "bug" %}Before any other action, inspect every existing `### Confusions` entry and verify whether each described problem still exists. Do not treat the mere presence of historical Confusions as a blocker. If any problem still exists, record the complete current Confusions evidence in the canonical workpad and stop; Maestro sets `AI特殊工作流` to `AI异常`. If every problem is gone, mark each corresponding Confusions entry resolved in the workpad (for example `- [x] ... — resolved: <evidence>`) and continue the normal workflow. Never use the deleted `AI是否遇到异常` field.{% endif %} Read or create exactly
   one canonical workpad through `tracker.upsert_workpad`. Keep its full body
   mirrored in workspace-root `.symphony-tapd-workpad.md`; never put that file
   under `repo/` or commit it. {% if issue.entity_type == "bug" %}Pass `entity_type: "bug"` whenever creating a workpad or general comment.{% endif %}
2. Reconcile the workpad plan, acceptance criteria, and validation checklist.
   Record a concrete reproduction or baseline signal before editing code.
3. Use {% if issue.branch_name %}`origin/{{ issue.branch_name }}` from the
   Story's `代码分支` field{% else %}`origin/{{ repo.base_branch }}` because the
   Story has no explicit development branch{% endif %} as the development
   base. Synchronize that ref with the repo-core helper when needed, then use
   `repo_checkout` with canonical mode `create_or_switch` and explicit base
   {% if issue.branch_name %}`origin/{{ issue.branch_name }}`{% else %}`origin/{{ repo.base_branch }}`{% endif %}
   to create a Story-specific branch without configured-base synchronization
   in that checkout call. Confirm the working branch is neither the development
   base nor final integration branch `{{ repo.base_branch }}` and follows the
   configured work prefix before any commit or push.
4. The initial clone is blobless, sparse, uses a sparse index, and borrows
   immutable Git objects from the shared per-remote cache prepared outside task
   workspaces. Before editing, call `repo_remote_search` with exact identifiers and the development ref to
   locate likely files without downloading blobs. Then call `repo_sparse_add`
   only for the smallest required target directories; never add `.` or the
   repository root. Fetch Git LFS objects only for explicitly
   required paths. Then work only under `repo/`, implement the scoped change,
   and run every repository and Story-required validation step. Record commands
   and outcomes in the workpad.
5. Use `repo_diff` with its whitespace check enabled, compare against the Story
   development base, and verify that only the intended changes are present.
6. Use `repo_commit` with canonical mode `all` or `staged`. Never commit
   directly on the Story development base or final integration branch.
7. Use `repo_push` to publish the working branch. A push is successful only
   when its `publishedHeadSha` equals `headSha`. If `repo_push` is not present
   in the inventory, use `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo push`
   and verify the remote branch SHA equals local `HEAD`.
8. After a successful push, update the canonical workpad and mirror with the
   remote repository, branch name, commit SHA, validation results, and
   reviewer-ready `suggested_mr_title` and `suggested_mr_description` text.
   These fields are handoff text only; do not create or update an MR.
9. {% if issue.entity_type == "bug" %}Only after the code change is validated, committed, pushed, and recorded in the workpad, call `tracker.complete_ai_workflow`. This must change `AI特殊工作流` from `接受/处理` to `AI已解决`. Do not change the Bug's TAPD status. Stop immediately after the field update succeeds; Maestro then removes this task workspace but retains the shared Git object cache.{% else %}Move the Story to the configured `review` raw state through the typed tracker move tool. Stop immediately after the state update succeeds because review is a human wait state and is not active for this template.{% endif %}

Push failure policy:

- For a non-fast-forward rejection, synchronize the Story development base
  through the existing repo-core flow, resolve conflicts without rewriting
  unrelated history, rerun validation, then retry the normal push.
- For authentication, permission, protected-branch, missing SSH tooling, or
  host-key failures, stop and record the exact blocker. Do not rewrite the
  remote, switch transport protocols, expose credentials, or bypass policy.
- Never use `--force`. Use `--force-with-lease` only when the Story explicitly
  requires an intentional history rewrite and the repository policy permits it.
- Never push the Story development base or final integration branch, and never
  use a work branch that does not satisfy the configured prefix policy.

If review requests changes, a human records the requirements in TAPD and moves
the Story back to `developing`. Maestro then resumes from the canonical workpad
and repeats implementation, validation, commit, push, SHA verification, and
handoff. It does not read hosting-platform review comments or pipeline state.
