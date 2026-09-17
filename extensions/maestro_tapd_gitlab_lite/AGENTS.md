# TAPD + GitLab Lite Extension

This directory owns the independently packaged `MaestroTapdGitlabLite` OTP
application. Before editing, classify every touched file as one of:

- `PLUGIN`: Lite business code or assets in this directory.
- `INTEGRATION-SEAM`: one minimal assembly/configuration change that enables or
  disables the package.
- `CORE-GENERIC`: a provider-neutral public contract with a neutral fake test.

If a file cannot be classified, stop expanding the change and reconsider the
boundary.

## Ownership and dependency rules

- GitLab HTTP APIs, tokens, project identifiers, response parsing, company TAPD
  fields and values, Lite workflow behavior, templates, scripts, tests, and docs
  belong here.
- Core must never depend on `MaestroTapdGitlabLite.*`. It discovers extension
  modules through public registries and source contracts.
- Use Core public facades or modules under `host_adapters/`; never call
  Orchestrator state internals or another Core private implementation.
- Company TAPD policy depends only on repository facades/capabilities. It must
  not branch on, alias, or call the GitLab Lite backend.
- Do not add `GitLab`, `GITLAB_API_TOKEN`, `AI特殊工作流`, `AI模型等级`, or
  `tapd_git_codex` literals to Core.
- Keep the Lite backend read-only at the HTTP layer. Git writes use Git SSH;
  MR, review, pipeline, approval, and merge remain manual.
- Configuration, tool inventory, templates, and lifecycle changes require docs
  in this directory. Update Core docs only for generic contract changes.
- Avoid unrelated Core refactors, repository-wide formatting, and commits that
  mix generic contracts with business migration.

## Validation

From `elixir/`, run the Lite tests plus the disabled-extension TAPD + GitHub
tests whenever an integration seam changes. Also run `mix specs.check`, the
architecture test, `make all`, and `make secret-scan` before publishing.

Pre-commit boundary checklist:

- [ ] Lite business code is in this extension.
- [ ] Core changes are minimal and platform-neutral.
- [ ] Core contains no new Lite strings or provider-specific branches.
- [ ] Mode C (extension disabled, TAPD + GitHub) passes.
- [ ] Mode A (company policy + GitLab Lite) passes.
- [ ] Mode B (company policy + fake upstream-compatible backend) passes.
- [ ] Docs, templates, and tool inventory are synchronized.

