# Maestro TAPD + GitLab Lite

Independent OTP extension for the company TAPD AI policy and the temporary
GitLab Lite repository backend. Git writes use SSH. The only GitLab HTTP API
capability is read-only blob search; merge requests, reviews, pipelines,
approvals, and merges remain manual.

For TAPD Bugs and Tasks, execution is opt-in: the item must be in an active
state and have `AI特殊工作流=接受/处理`. Their normalized `AI模型等级`
controls repository materialization; `high` or `xhigh` uses the bundled
workflow uses `SOURCE_REPO_LOCAL_REFERENCE` as a fast local shared clone, then
fetches only the requested GitLab branch delta. Set `SOURCE_REPO_PULL_PATHS` to
a comma-separated list of Git sparse-checkout patterns. Positive patterns expand
selected paths recursively; patterns beginning with `!` exclude matching paths:

```bash
SOURCE_REPO_PULL_PATHS=Game/.agents,Game/.codex,Game/.cursor,Game/Assets/_Script/*.cs,Game/Assets/_Script/**/*.cs,Game/Docs,Game/AGENTS.md,Game/openspec
```

When `SOURCE_REPO_PULL_PATHS` is set, the task workspace uses sparse checkout
and only those paths are materialized. When it is empty, high/xhigh retain the
complete checkout behavior. `low` and `medium` always retain the blobless
sparse-checkout path. Repository-owned agent rules and skills below
`SOURCE_REPO_PROJECT_SUBDIR` are exposed before Codex starts.

The host loads the extension through `MaestroTapdGitlabLite.RegistrySource` and
selects the Lite Git backend through the normal repo-provider registry. Remove
those two assembly registrations to run Maestro Core without the extension.

The manifest requires Core contract version 1. The TAPD policy and repository
backend are deliberately separate so a future upstream GitLab provider can
replace the backend without changing company field semantics.

## Workpad formatting

The Lite Workpad contract keeps headings and prose in normal Markdown while
using Markdown inline code for important identifiers and values. TAPD renders
those inline-code spans as the red emphasis used by the established Workpad
style, including for paths, branches, SHAs, commands, field values, and tool
names. The formatting rule is defined in
`priv/workflow_templates/_partials/tracker/tapd_git_only_workpad_contract.md`.
