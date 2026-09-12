---
workflow:
  profile:
    kind: coding_pr_delivery
    version: 1
    options:
      requirements:
        change_proposal: false
        typed_tracker_tools: true
        typed_repo_tools: false
tracker:
  kind: tapd
  auth:
    api_key: $TAPD_API_USER
    api_secret: $TAPD_API_PASSWORD
  provider:
    assignee: $TAPD_ASSIGNEE
    platform:
      workspace_id: $TAPD_WORKSPACE_ID
      comment_author: $TAPD_COMMENT_AUTHOR
      bug_ai_workflow:
        field: $TAPD_BUG_AI_WORKFLOW_FIELD
        accepted_value: 接受/处理
        resolved_value: AI已解决
        active_states: [new, reopened]
  lifecycle:
    active_states:
      - status_4
      - developing
    terminal_states:
      - status_6
      - status_8
    state_phase_map:
      status_4: todo
      developing: in_progress
      status_5: human_review
      merging: merging
      rework: rework
      status_6: done
      status_8: done
    raw_state_by_route_key:
      planning: status_4
      developing: developing
      review: status_5
      merging: merging
      rework: rework
      resolved: status_6
    policy_by_route_key:
      merging:
        action: wait
      rework:
        action: wait
      rejected:
        action: disabled
    workflows_by_type:
      "1154044737001000037": {}
      "1154044737001000148":
        terminal_states: [status_6]
      "1154044737001000150":
        terminal_states: [status_6]
      "1154044737001000151":
        terminal_states: [status_6]
      "1154044737001000153":
        terminal_states: [status_6]
polling:
  interval_ms: 30000
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
repo:
  path: repo
  base_branch: $SOURCE_REPO_BASE_BRANCH
  remote:
    name: origin
    url: $SOURCE_REPO_URL
  branch:
    work_prefix: $SOURCE_REPO_BRANCH_WORK_PREFIX
  provider:
    kind: git
    options:
      remote_code_search: gitlab
      gitlab_api_base_url: $GITLAB_API_BASE_URL
      gitlab_project_id: $GITLAB_PROJECT_ID
hooks:
  after_create: |
    if [ -z "${SOURCE_REPO_URL:-}" ]; then
      echo "SOURCE_REPO_URL is required" >&2
      exit 1
    fi
    task_base_branch="${SYMPHONY_ISSUE_BRANCH_NAME:-${SOURCE_REPO_BASE_BRANCH:-}}"
    if [ -n "$task_base_branch" ]; then
      GIT_LFS_SKIP_SMUDGE=1 "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1 --filter blob:none --sparse --branch "$task_base_branch"
    else
      GIT_LFS_SKIP_SMUDGE=1 "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1 --filter blob:none --sparse
    fi
    git -C repo sparse-checkout reapply --sparse-index
  before_run: |
    task_base_branch="${SYMPHONY_ISSUE_BRANCH_NAME:-${SOURCE_REPO_BASE_BRANCH:-}}"
    if [ -n "$task_base_branch" ] && [ -d repo/.git ]; then
      GIT_LFS_SKIP_SMUDGE=1 git -C repo fetch --no-tags --depth 1 origin "$task_base_branch:refs/remotes/origin/$task_base_branch"
    fi
  before_remove: |
    # Optional target-repository cleanup belongs here.
agent:
  execution:
    max_concurrent_agents: 1
    max_turns: 20
agent_provider:
  kind: codex
  options:
    command: codex --config shell_environment_policy.inherit=all --config 'shell_environment_policy.exclude=["GITLAB_API_TOKEN"]' --config model_reasoning_effort=medium --config 'project_root_markers=[]' --model gpt-5.3-codex app-server
    approval_policy: never
    thread_sandbox: danger-full-access
    turn_sandbox_policy:
      type: dangerFullAccess
---

You are working on a TAPD {% if issue.entity_type == "bug" %}Bug{% else %}story{% endif %} `{{ issue.identifier }}` in a Git-only delivery workflow.

<!-- symphony-include: _partials/runtime/retry_continuation_context.md -->

Story context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Entity type: {% if issue.entity_type %}{{ issue.entity_type }}{% else %}story{% endif %}
Workitem type: {% if issue.workitem_type_id %}{{ issue.workitem_type_id }}{% else %}unknown{% endif %}
{% if issue.entity_type == "bug" %}AI特殊工作流: {{ issue.custom_fields.ai_special_workflow }}
{% endif %}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Current workflow contract:
- profile: `{{ workflow.profile.kind }}` v{{ workflow.profile.version }}
- current route: {% if workflow.route.key %}`{{ workflow.route.key }}`{% else %}`unresolved`{% endif %}; action `{{ workflow.route.action }}`; gate `{{ workflow.gate.status }}/{{ workflow.gate.gate }}`
- gate reason: {{ workflow.gate.reason }}
- review handoff raw state: `{{ issue.workflow.raw_state_by_route_key.review }}`
- {% if issue.entity_type == "bug" %}Bug{% else %}Story{% endif %} development base: {% if issue.branch_name %}`{{ issue.branch_name }}` (from the TAPD `代码分支` field){% else %}`{{ repo.base_branch }}` (default because the work item has no `代码分支` field){% endif %}
- final integration branch: `{{ repo.base_branch }}` (human-owned after acceptance)

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended session. Follow the resolved route policy and stop for
   a true blocker instead of asking for interactive setup.
2. The automation boundary ends after a working-branch push, remote SHA
   verification, TAPD workpad handoff, and {% if issue.entity_type == "bug" %}changing `AI特殊工作流` to `AI已解决`{% else %}transition to human review{% endif %}.
   Base the working branch on the work item development base above. Treat that
   explicit work item branch as authoritative for implementation; it is not a
   conflict with the final integration branch.
3. The only allowed hosting API action is the inventory-listed, read-only
   `repo_remote_search` tool. Do not call GitLab directly or create, update,
   review, approve, check, land, close, or merge a change proposal.
4. Work only in `repo/`. The sole normal workspace-root artifact you may update
   is `.symphony-tapd-workpad.md`.
5. Final output must report completed actions and blockers only.

## TAPD Access And Tools

<!-- symphony-include: _partials/tracker/tapd_git_only_access_and_tools.md -->

## TAPD Workpad Contract

<!-- symphony-include: _partials/tracker/tapd_git_only_workpad_contract.md -->

## Git-Only Execution Lifecycle

<!-- symphony-include: _partials/tracker/tapd_git_only_execution_lifecycle.md -->
