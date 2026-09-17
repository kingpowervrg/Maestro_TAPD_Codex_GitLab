# Operations

Use `bin/start`, `bin/restart`, and `bin/stop` from this extension. They resolve
the sibling `elixir/` runtime, load the protected environment file, and retain
the existing `tapd/git/codex` operator alias.

The legacy host entry points `elixir/bin/start-tapd-gitlab`,
`elixir/bin/restart-tapd-gitlab`, and `elixir/bin/stop-tapd-gitlab` remain as
compatibility wrappers and forward all arguments to these extension scripts.

Copy `.env.example` to an external, mode-0600 environment file. The GitLab token
needs read-only API access. It is used only by `repo_remote_search` and excluded
from the agent shell. Git checkout, commit, and push authenticate with Git SSH.

The company Bug policy requires a configured workflow field. Only active Bugs
whose configured value is `接受/处理` are dispatched. Successful completion
writes `AI已解决`; terminal failure writes `AI异常`. Both paths read the Bug back
before reporting success and refuse to overwrite a human change.

The object cache lives under `SYMPHONY_GIT_OBJECT_CACHE_ROOT` or defaults to a
directory below the workspace root. It is an optional extension automation
overlay. Do not remove it while workspaces still borrow objects from it.

Disable Mode A by removing these four assembly registrations from runtime
configuration: workflow registry source, Git adapter override, issue policy,
and workspace automation source. Mode C then uses the built-in TAPD + GitHub
behavior and requires no GitLab credentials or object-cache configuration.
