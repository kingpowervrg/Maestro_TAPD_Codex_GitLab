# Repository Agent Guide

The Elixir runtime is governed by [`elixir/AGENTS.md`](elixir/AGENTS.md).

All TAPD + GitLab Lite work must also read
[`extensions/maestro_tapd_gitlab_lite/AGENTS.md`](extensions/maestro_tapd_gitlab_lite/AGENTS.md).
Lite business logic, customer TAPD fields, GitLab HTTP behavior, workflow assets,
deployment scripts, and tests belong to that extension. Do not add Lite-specific
branches or strings to Maestro Core. Core changes are allowed only for a small,
provider-neutral contract, registry, facade, or hook that has a non-Lite test.

