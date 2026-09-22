- Each active Story or Bug has at most one persistent workpad, including across Bug rework rounds.
- The workpad stable identity is the typed-tool returned `workpad.id` / `workpad_id`.
- Agents must read workpad identity through `tracker.issue_snapshot`.
- Agents must update workpad only through `tracker.upsert_workpad`, except for the final Bug body: pass that body to `tracker.complete_ai_workflow` so the tool can write it after field read-back.
- Agents must not identify workpads by title, Markdown shape, comment body, or provider UI text; do not search comments by title or Markdown shape yourself.
- TAPD stores the workpad as a comment on the active Story or Bug. Keep workspace-root `.symphony-tapd-workpad.md` as its full local mirror; from `repo/`, address it as `../.symphony-tapd-workpad.md`.
- Never create, stage, or commit `repo/.symphony-tapd-workpad.md`.
- The workpad is the human-readable execution and Git handoff log. Keep it concise and update it after every meaningful milestone.
- For a reaccepted Bug, append a `Rework Round N` entry to the existing workpad. Record the exact human feedback comment ids handled by that round, so the next run can distinguish new feedback without reprocessing old comments.
- Preserve the published working branch across rework rounds. The latest completed round's `branch_name` and `published_head_sha` are the authoritative resume point.
- The final checked AI workflow item is written by `tracker.complete_ai_workflow` only after TAPD read-back confirms `AI特殊工作流=AI已解决`; do not pre-check it with a standalone workpad update.

Formatting convention for TAPD presentation:

- Keep headings and explanatory prose as normal Markdown text.
- Wrap important identifiers and values in Markdown inline code so TAPD renders
  them as the red emphasis used in the existing Workpad style: field names and
  values, repository paths, branch names, commit/published SHAs, commands,
  status values, and tool names. For example:
  `AI特殊工作流=AI已解决`, `origin/main`, `git diff --check`, and
  `published_head_sha`.
- Do not use HTML or CSS for emphasis; the typed tracker tools preserve the
  Markdown body and the TAPD client performs the platform-specific conversion.

Use this structure for the persistent workpad comment and its local mirror:

````md
## Workpad

### Plan

- [ ] 1. Parent task
  - [ ] 1.1 Child task

### Acceptance Criteria

- [ ] Criterion 1

### Validation

- [ ] targeted tests: `<command>`

### Git Handoff

- repository: pending
- branch_name: pending
- commit_sha: pending
- published_head_sha: pending
- suggested_mr_title: pending
- suggested_mr_description: pending

### Rework History

- Round 1
  - feedback_comment_ids: none (initial implementation)
  - branch_name: pending
  - published_head_sha: pending
  - status: in_progress

### Notes

- <short progress note with timestamp>

### Confusions

- <only include when something was confusing during execution>
````
