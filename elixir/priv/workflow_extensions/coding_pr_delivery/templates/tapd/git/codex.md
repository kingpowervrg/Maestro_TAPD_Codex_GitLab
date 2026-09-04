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
    platform:
      workspace_id: $TAPD_WORKSPACE_ID
      comment_author: $TAPD_COMMENT_AUTHOR
  lifecycle:
    active_states:
      - status_4
      - developing
    terminal_states:
      - resolved
      - rejected
    state_phase_map:
      status_4: todo
      developing: in_progress
      status_5: human_review
      merging: merging
      rework: rework
      resolved: done
      rejected: canceled
    raw_state_by_route_key:
      planning: status_4
      developing: developing
      review: status_5
      merging: merging
      rework: rework
      resolved: resolved
      rejected: rejected
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
hooks:
  after_create: |
    if [ -z "${SOURCE_REPO_URL:-}" ]; then
      echo "SOURCE_REPO_URL is required" >&2
      exit 1
    fi
    if [ -n "${SOURCE_REPO_BASE_BRANCH:-}" ]; then
      "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1 --branch "$SOURCE_REPO_BASE_BRANCH"
    else
      "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1
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
    command: codex --config shell_environment_policy.inherit=all --config model_reasoning_effort=medium --config 'project_root_markers=[]' --model gpt-5.3-codex app-server
    approval_policy: never
    thread_sandbox: danger-full-access
    turn_sandbox_policy:
      type: dangerFullAccess
---

You are working on a TAPD story `{{ issue.identifier }}` in a Git-only delivery workflow.

<!-- symphony-include: _partials/runtime/retry_continuation_context.md -->

Story context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Workitem type: {% if issue.workitem_type_id %}{{ issue.workitem_type_id }}{% else %}unknown{% endif %}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Current workflow contract:
- profile: `{{ workflow.profile.kind }}` v{{ workflow.profile.version }}
- current route: {% if workflow.route.key %}`{{ workflow.route.key }}`{% else %}`unresolved`{% endif %}; action `{{ workflow.route.action }}`; gate `{{ workflow.gate.status }}/{{ workflow.gate.gate }}`
- gate reason: {{ workflow.gate.reason }}
- review handoff raw state: `{{ issue.workflow.raw_state_by_route_key.review }}`
- base branch: `{{ repo.base_branch }}`

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
   verification, TAPD workpad handoff, and transition to human review.
3. The repository hosting service is only a Git SSH remote. Do not invoke any
   hosting-platform API or create, update, review, approve, check, land, close,
   or merge a change proposal.
4. Work only in `repo/`. The sole normal workspace-root artifact you may update
   is `.symphony-tapd-workpad.md`.
5. Final output must report completed actions and blockers only.

## TAPD Access And Tools

<!-- symphony-include: _partials/tracker/tapd_git_only_access_and_tools.md -->

## TAPD Workpad Contract

<!-- symphony-include: _partials/tracker/tapd_git_only_workpad_contract.md -->

## Git-Only Execution Lifecycle

<!-- symphony-include: _partials/tracker/tapd_git_only_execution_lifecycle.md -->
