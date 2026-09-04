Use exact runtime tool names from the generated inventory. If a required typed
tool is missing, stop as blocked and record the blocker in the workpad when
workpad tooling is available.

{{ runtime.tool_inventory }}

For TAPD tracker actions, follow the bundled workspace skill at
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/tapd/SKILL.md`. This
workflow defines when tracker actions are allowed; the skill defines typed TAPD
capability semantics and argument shapes. Use only inventory-listed typed
tracker tools for routine Story reads, workpad updates, and state transitions.
Use inventory-listed typed tracker tools for routine actions.
Only use inventory-listed typed TAPD tools for tracker access.
Do not switch to direct TAPD REST calls or token-bearing shell commands.

For repository actions, use the inventory-listed repo-core tools
`repo_checkout`, `repo_diff`, `repo_commit`, and `repo_push`. Use
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` only for a repo-core operation
that the inventory does not expose, such as synchronizing the base branch.
Repo-provider tools are intentionally absent because this workflow has no
hosting-platform API capability.

Do not open or follow `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/push/SKILL.md`:
that skill owns a change-proposal workflow that is outside this template's
Git-only boundary. Never use `gh`, `glab`, a GitHub or GitLab API, or any
repo-provider change-proposal, review, check, approval, land, or merge action.
