- Each active Story has at most one persistent workpad.
- The workpad stable identity is the typed-tool returned `workpad.id` / `workpad_id`.
- Agents must read workpad identity through `tracker.issue_snapshot`.
- Agents must update workpad only through `tracker.upsert_workpad`.
- Agents must not identify workpads by title, Markdown shape, comment body, or provider UI text; do not search comments by title or Markdown shape yourself.
- TAPD stores the workpad as a Story comment. Keep workspace-root `.symphony-tapd-workpad.md` as its full local mirror; from `repo/`, address it as `../.symphony-tapd-workpad.md`.
- Never create, stage, or commit `repo/.symphony-tapd-workpad.md`.
- The workpad is the human-readable execution and Git handoff log. Keep it concise and update it after every meaningful milestone.

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

### Notes

- <short progress note with timestamp>

### Confusions

- <only include when something was confusing during execution>
````
