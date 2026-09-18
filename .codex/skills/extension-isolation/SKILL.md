---
name: extension-isolation
description: Audit and implement TAPD + GitLab Lite changes while preserving the Core/extension boundary; use when reviewing Lite code, configuration, templates, tests, or integration seams.
---

# Extension Isolation

Use this skill for any TAPD + GitLab Lite change in this repository. Its goal is
to keep Lite business behavior independently replaceable while preventing
provider-specific code or configuration from leaking into Maestro Core.

## Required context

Before editing, read:

- `AGENTS.md`
- `extensions/maestro_tapd_gitlab_lite/AGENTS.md`
- `elixir/docs/plans/tapd_gitlab_lite_extension_isolation.zh-CN.md`

Run the boundary audit from the repository root:

```bash
.codex/skills/extension-isolation/scripts/check_boundary.sh
```

Use `--strict` when the result is a release gate. The normal audit reports
production violations as failures and test-only references as warnings, so an
existing characterization test does not hide a source-boundary problem.

## Decision rules

Classify every touched file before changing it:

- `PLUGIN`: Lite business logic, GitLab HTTP/search, company TAPD fields and
  values, Lite templates/partials, automation, deployment assets, tests, and
  docs. Keep it under `extensions/maestro_tapd_gitlab_lite/`.
- `CORE-GENERIC`: a provider-neutral contract, behaviour, registry, facade, or
  hook with a neutral fake-extension test. It must not mention Lite vocabulary.
- `INTEGRATION-SEAM`: the smallest assembly/configuration change that enables or
  disables an extension. It may name a source or application boundary, but must
  not implement Lite behavior.

If a file cannot be classified, stop expanding the change and narrow the
boundary first. Never add Lite branches to Core to avoid moving an asset.

Core must not gain new references to `MaestroTapdGitlabLite.*`, GitLab API
details, `GITLAB_API_TOKEN`, `AI特殊工作流`, `AI模型等级`, `tapd_git_codex`, or
Lite-only object-cache behavior. Core defaults must work with the extension
disabled. Concrete extension registration belongs to the extension's own
application/source; Core configuration should contain only neutral defaults and
assembly contracts.

The TAPD policy must depend on repository facades/capabilities, never on the
GitLab Lite backend. The backend must remain read-only over HTTP; Git writes use
Git SSH, and MR/review/pipeline/approval/merge remain manual.

## Change and review workflow

1. Inspect `git status` and `git diff` first. Preserve unrelated user edits and
   do not overwrite a dirty worktree.
2. Run the audit and classify every changed file.
3. Put new behavior/assets/tests/docs in the extension. If Core needs a seam,
   define the smallest neutral contract and add a fake-extension test before
   wiring the Lite implementation.
4. Check disabled-extension behavior (Mode C: TAPD + GitHub), enabled Lite
   behavior (Mode A), and policy/backend substitution with a fake upstream
   backend (Mode B). Do not run live provider turns without explicit request.
5. Synchronize extension-owned configuration, templates, tool inventory,
   lifecycle docs, and tests. Update Core docs only when a neutral contract
   changed.
6. Re-run the audit, targeted tests, `mix specs.check`, the architecture test,
   and the appropriate full gates before handoff. For a documentation or skill
   change, at minimum run `git diff --check` and the audit.

## Boundary evidence to report

Summarize:

- files classified as `PLUGIN`, `CORE-GENERIC`, and `INTEGRATION-SEAM`;
- any remaining violations or justified allowlisted seams;
- Mode A/B/C validation performed and results;
- whether Core behavior is unchanged when the extension is disabled.

Do not claim isolation based only on directory placement: inspect imports,
application config, runtime registries, template roots, dependency direction,
and tests as well.
