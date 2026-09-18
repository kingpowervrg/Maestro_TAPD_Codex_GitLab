# Maestro TAPD + GitLab Lite

Independent OTP extension for the company TAPD AI policy and the temporary
GitLab Lite repository backend. Git writes use SSH. The only GitLab HTTP API
capability is read-only blob search; merge requests, reviews, pipelines,
approvals, and merges remain manual.

For Bugs whose normalized `AI模型等级` is `high` or `xhigh`, the bundled
workflow creates a complete per-issue checkout using
`SOURCE_REPO_LOCAL_REFERENCE` as a fast local shared clone, then fetches only
the requested GitLab branch delta. `low` and
`medium` retain the blobless sparse-checkout path. Repository-owned agent rules
and skills below `SOURCE_REPO_PROJECT_SUBDIR` are exposed before Codex starts.

The host loads the extension through `MaestroTapdGitlabLite.RegistrySource` and
selects the Lite Git backend through the normal repo-provider registry. Remove
those two assembly registrations to run Maestro Core without the extension.

The manifest requires Core contract version 1. The TAPD policy and repository
backend are deliberately separate so a future upstream GitLab provider can
replace the backend without changing company field semantics.
