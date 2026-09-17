Use exact runtime tool names from the generated inventory. If a required typed
tool is missing, stop as blocked and record the blocker in the workpad when
workpad tooling is available.

{{ runtime.tool_inventory }}

For TAPD tracker actions, follow the bundled workspace skill at
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/tapd/SKILL.md`. This
workflow defines when tracker actions are allowed; the skill defines typed TAPD
capability semantics and argument shapes. Use only inventory-listed typed
tracker tools for routine Story/Bug reads, workpad updates, state transitions,
and AI workflow completion.
Use inventory-listed typed tracker tools for routine actions.
Only use inventory-listed typed TAPD tools for tracker access.
Do not switch to direct TAPD or GitLab REST calls or token-bearing shell commands.

For repository actions, use the inventory-listed tools `repo_remote_search`,
`repo_sparse_add`, `repo_checkout`, `repo_diff`, `repo_commit`, and `repo_push`. Use
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` only for a repo-core operation
that the inventory does not expose, such as synchronizing the base branch.
`repo_remote_search` is the sole repo-provider exception. Its GitLab token
remains in the Maestro service and is excluded from Codex shell environments.

Do not open or follow `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/push/SKILL.md`:
that skill owns a change-proposal workflow that is outside this template's
Git-only boundary. Never use `gh`, `glab`, a direct GitHub or GitLab API call, or any
repo-provider change-proposal, review, check, approval, land, or merge action.
