# Maestro TAPD + GitLab Lite

Independent OTP extension for the company TAPD AI policy and the temporary
GitLab Lite repository backend. Git writes use SSH. The only GitLab HTTP API
capability is read-only blob search; merge requests, reviews, pipelines,
approvals, and merges remain manual.

The host loads the extension through `MaestroTapdGitlabLite.RegistrySource` and
selects the Lite Git backend through the normal repo-provider registry. Remove
those two assembly registrations to run Maestro Core without the extension.

The manifest requires Core contract version 1. The TAPD policy and repository
backend are deliberately separate so a future upstream GitLab provider can
replace the backend without changing company field semantics.

