# Operations

Use `bin/start`, `bin/restart`, and `bin/stop` from this extension. They resolve
the sibling `elixir/` runtime, load the protected environment file, and retain
the existing `tapd/git/codex` operator alias.

The legacy host entry points `elixir/bin/start-tapd-gitlab`,
`elixir/bin/restart-tapd-gitlab`, and `elixir/bin/stop-tapd-gitlab` remain as
compatibility wrappers and forward all arguments to these extension scripts.

The bundled Codex workflow uses a 30-second app-server response timeout. This
allows session initialization to complete for large repository workspaces
without changing Core's provider-neutral default.

Copy `.env.example` to an external, mode-0600 environment file. The GitLab token
needs read-only API access. It is used only by `repo_remote_search` and excluded
from the agent shell. Git checkout, commit, and push authenticate with Git SSH.

Configure the complete local checkout used by `xhigh` tasks in that
environment file:

```bash
SOURCE_REPO_LOCAL_REFERENCE=/home/admin2/workspace_k1/master
SOURCE_REPO_PROJECT_SUBDIR=Game
# Optional for xhigh; use comma-separated sparse-checkout patterns.
SOURCE_REPO_PULL_PATHS=Game/.agents,Game/.codex,Game/.cursor,Game/Assets/_Script/*.cs,Game/Assets/_Script/**/*.cs,Game/Docs,Game/AGENTS.md,Game/openspec
```

`SOURCE_REPO_LOCAL_REFERENCE` must be a non-shallow, non-sparse, non-partial Git
repository whose `origin` exactly matches `SOURCE_REPO_URL`. It remains a local
reference only: each task receives an independent checkout under its own
`workspace/repo`, and no task switches branches or writes files in the shared
reference working tree. Keep the reference repository available until all
borrowing task workspaces have been removed.

The normalized reasoning effort controls materialization:

- `xhigh` creates an independent shared clone from
  `SOURCE_REPO_LOCAL_REFERENCE` and checks out the TAPD `代码分支` when
  present, otherwise `SOURCE_REPO_BASE_BRANCH`. The reference normally contains
  that branch as `refs/remotes/origin/<branch>`. Preparation compares it with
  `git ls-remote` and automatically fetches a missing or stale branch into the
  reference repository. It never fetches objects from GitLab inside the task
  workspace or switches the reference worktree. The equivalent manual command
  is:

  ```bash
  git -C "$SOURCE_REPO_LOCAL_REFERENCE" fetch origin \
    "+refs/heads/<branch>:refs/remotes/origin/<branch>"
  ```

  Concurrent checks share a lock in the reference Git common directory, with
  a 300-second lock wait limit. After acquiring the lock, preparation compares
  SHAs again; a current reference skips fetch. Fetch updates only the requested
  remote-tracking ref and preserves the reference worktree, local branches, and
  `FETCH_HEAD`. A failed fetch or a SHA mismatch after fetching blocks the turn.

  If `SOURCE_REPO_PULL_PATHS` is set, Git sparse checkout expands only the
  listed directories and all of their descendants. If it is empty, the task
  receives the complete working tree. `low`, `medium`, and `high` retain the
  blobless, depth-1 sparse checkout backed by the shared object cache.

Before an `xhigh` Codex process starts, workspace bootstrap writes a generated
workspace-root `AGENTS.md` that routes the agent to the configured project
subdirectory. Skills found immediately below
`<project>/.codex/skills/` and `<project>/.agents/skills/` are copied into the
workspace automation skill directory with collision-resistant prefixes. The
source repository files are not changed.

Set `SYMPHONY_WORKSPACE_HOOK_TIMEOUT_MS` high enough to cover population of the
selected working tree. The packaged example uses `3600000` (one hour) because
multi-hundred-gigabyte repositories can exceed the Core default. An `xhigh`
task no longer spends that window fetching a branch from GitLab; refresh the
local reference before dispatch when its SHA is behind.

Repository materialization is fixed when an issue workspace is first created.
If a retained workspace was created at a different reasoning level,
`before_run` migrates a clean sparse workspace to the required xhigh mode. A
missing or stale reference branch is automatically fetched into
`SOURCE_REPO_LOCAL_REFERENCE` before materialization. Other incompatible modes,
dirty workspaces, and incomplete materializations remain blocked and must be
removed through the normal Maestro cleanup path.

A retained workspace whose `.symphony-tapd-workpad.md` records a 40-digit `published_head_sha` and a nonempty, non-`pending` `suggested_mr_title` is completion recovery. Placeholder fields with `pending` values do not qualify. Its `before_run` hook does not refresh `SOURCE_REPO_LOCAL_REFERENCE` or fetch the development baseline. New and incomplete checkouts still compare the reference with the remote.

If an incomplete workspace was created in sparse mode and the task later switches to `xhigh`, `before_run` rematerializes it from the complete local reference when the sparse checkout is clean and has no local commits absent from its origin refs. `SOURCE_REPO_PULL_PATHS` selects partial checkout; otherwise it creates a full checkout. The old repository, including ignored files, is retained at `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/repo-sparse-before-xhigh`. Target guidance and skills are installed before the agent starts. Dirty or invalid workspaces and workspaces with local commits remain blocked to protect work; published completion recovery preserves the existing checkout. Failed reference synchronization or materialization also blocks the turn without falling back to blob search.

The company policy requires a configured workflow field. Bugs use the Bug field;
Stories use the task field. Only active work items whose configured value is
`接受/处理` are dispatched. Successful completion writes `AI已解决`; terminal
failure writes `AI异常`. Both paths write and read back the field selected for
that work item, and refuse to overwrite a human change.

Stopping a running session from the Dashboard follows the same exception
policy: the TAPD `AI特殊工作流` field is read back, changed to `AI异常`, and
verified. The session stop itself does not create a separate dispatch blocker.
Changing the field back to `接受/处理` makes the Bug eligible for a later poll
cycle and starts it again.

For an initial delivery, the workflow passes only the TAPD identifier to
`repo_checkout`; repo-core derives the working branch from
`SOURCE_REPO_BRANCH_WORK_PREFIX`. Rework rounds pass only the exact branch
recorded in the completed workpad. Repo-core rejects ambiguous checkout input
and blocks checkout or push when an explicit branch does not match the
configured prefix.

The object cache lives under `SYMPHONY_GIT_OBJECT_CACHE_ROOT` or defaults to a
directory below the workspace root. It is an optional extension automation
overlay. Do not remove it while workspaces still borrow objects from it.

Disable Mode A by removing these four assembly registrations from runtime
configuration: workflow registry source, Git adapter override, issue policy,
and workspace automation source. Mode C then uses the built-in TAPD + GitHub
behavior and requires no GitLab credentials or object-cache configuration.
