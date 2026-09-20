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

Configure the complete local checkout used by higher-reasoning tasks in that
environment file:

```bash
SOURCE_REPO_LOCAL_REFERENCE=/home/admin2/workspace_k1/master
SOURCE_REPO_PROJECT_SUBDIR=Game
# Optional for high/xhigh; paths are repository-relative and recursive.
SOURCE_REPO_PULL_PATHS=Game/.agents\;Game/.codex\;Game/.cursor\;Game/Assets/_Script\;Game/Assets/Plugins
```

`SOURCE_REPO_LOCAL_REFERENCE` must be a non-shallow, non-sparse, non-partial Git
repository whose `origin` exactly matches `SOURCE_REPO_URL`. It remains a local
reference only: each task receives an independent checkout under its own
`workspace/repo`, and no task switches branches or writes files in the shared
reference working tree. Keep the reference repository available until all
borrowing task workspaces have been removed.

The normalized reasoning effort controls materialization:

- `high` and `xhigh` first create a local shared clone with full history, then
  point `origin` back to GitLab and fetch only the requested branch delta. If
  `SOURCE_REPO_PULL_PATHS` is set, Git sparse checkout expands only the listed
  directories and all of their descendants. If it is empty, the task receives
  the complete working tree. Both variants avoid validating the entire
  alternate object database during a remote clone. The task checks out the
  TAPD `代码分支` when present, otherwise `SOURCE_REPO_BASE_BRANCH`.
- `low` and `medium` retain the blobless, depth-1 sparse checkout backed by the
  shared object cache.

Before a high/xhigh Codex process starts, workspace bootstrap writes a generated
workspace-root `AGENTS.md` that routes the agent to the configured project
subdirectory. Skills found immediately below
`<project>/.codex/skills/` and `<project>/.agents/skills/` are copied into the
workspace automation skill directory with collision-resistant prefixes. The
source repository files are not changed.

Set `SYMPHONY_WORKSPACE_HOOK_TIMEOUT_MS` high enough to cover remote delta
fetching and population of the selected working tree. The packaged example
uses `3600000` (one hour) because multi-hundred-gigabyte repositories can exceed
the Core default even when most Git objects are borrowed locally.

Repository materialization is fixed when an issue workspace is first created.
If a retained workspace was created at a different reasoning level, the
`before_run` guard fails instead of silently mixing sparse and complete modes;
remove that stale issue workspace through the normal Maestro cleanup path and
let the next attempt recreate it.

The company Bug policy requires a configured workflow field. Only active Bugs
whose configured value is `接受/处理` are dispatched. Successful completion
writes `AI已解决`; terminal failure writes `AI异常`. Both paths read the Bug back
before reporting success and refuse to overwrite a human change.

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
