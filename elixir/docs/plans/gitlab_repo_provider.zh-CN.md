# GitLab Repo Provider 落地计划

状态：Draft  
创建日期：2026-09-02  
适用范围：Maestro Elixir Runtime  
目标实例：`https://gitlab-ee.funplus.io`  
目标仓库：`koa-client-code/koa-client-code`

## 1. Problem Statement

Maestro 当前只内置 GitHub、CNB 和 Memory Repo Provider，无法通过统一的 Repo Provider 接口操作公司自建 GitLab EE 上的 Merge Request、评论、审批和 Pipeline。虽然 Git clone、fetch、branch、commit 和 push 等基础操作与代码托管平台无关，但 TAPD + GitLab + Codex 的完整交付流程仍缺少 GitLab API 适配层。

如果不增加 GitLab Provider，Maestro 只能向 GitLab 推送分支，无法可靠地创建或更新 Merge Request、读取评审反馈、判断 Pipeline 状态或执行受控合并。

## 2. Goals

1. 支持通过 `repo.provider.kind: gitlab` 选择 GitLab Provider。
2. 跑通 TAPD 工作项到 GitLab Merge Request 的完整最小闭环：创建分支、推送、创建或更新 MR、读取和回复评论、读取 Pipeline 状态。
3. 在完整版本中支持审批检查和安全合并；当审批、Pipeline、冲突或讨论状态不满足策略时必须拒绝合并。
4. 支持自建 GitLab EE 的自定义 API/Web Base URL、私有项目、多级 namespace 和企业 CA。
5. Token 不得出现在日志、Dashboard、错误消息、测试快照或提交内容中。

## 3. Non-Goals

1. 不替换现有 Git clone/push 实现；Git 传输继续使用现有 Repo Core 和 SSH 能力。
2. 不负责管理 GitLab 用户、群组、许可证、Runner 或项目级审批规则。
3. v1 不支持 Merge Train、跨项目 Fork MR、OAuth、自动 Rebase 和多个 GitLab 实例同时路由。
4. 不自动生成完整的 `.gitlab-ci.yml`；只记录并验证目标项目能产生所需 Pipeline。
5. 不保证兼容所有历史 GitLab 版本；以联调时确认的公司 GitLab EE 版本为最低兼容基线。

## 4. User Stories

### Maestro 操作者

- 作为 Maestro 操作者，我希望通过模板选择 GitLab，使 TAPD 工作项能够在公司 GitLab 项目中创建 Merge Request。
- 作为 Maestro 操作者，我希望 Dashboard 展示 MR、Pipeline 和审批状态，以便判断自动化当前进度。
- 作为 Maestro 操作者，我希望认证或权限不足时看到可执行且不泄露凭证的错误信息。

### 开发者与评审者

- 作为开发者，我希望 Codex 能读取 MR 评论并在后续提交中响应反馈。
- 作为评审者，我希望自动化遵守保护分支、审批、未解决讨论和 Pipeline 策略。
- 作为项目维护者，我希望只有满足合并条件的当前 HEAD 提交可以被自动合并。

### GitLab 管理员

- 作为 GitLab 管理员，我希望使用项目范围的机器人 Token 和最小必要权限，而不是共享个人凭证。
- 作为安全管理员，我希望 Token 可轮换、可撤销，并且不会进入日志或仓库。

## 5. Architecture Decisions

### 5.1 Provider 形态

- 新增内置 Provider kind：`gitlab`。
- 新增 `SymphonyElixir.RepoProvider.GitLab.Adapter`，实现现有 `SymphonyElixir.RepoProvider.Adapter` behaviour。
- 复用 Repo Provider 的通用配置、调用、能力声明、错误、重试和可观测性机制。
- 参考 CNB Provider 的 HTTP 分层结构实现 GitLab，不强制依赖 `glab` CLI。
- 保留现有 `pr_*` 内部回调名称；在 GitLab Adapter 内将其映射为 Merge Request 语义。

### 5.2 认证与 Git 传输

- GitLab REST API 使用 `PRIVATE-TOKEN` 请求头。
- 建议使用 Project Access Token；若组织策略不允许，再评估 Group Access Token 或专用机器人 Personal Access Token。
- API Token 与 Git SSH Key 分开管理：
  - API Token 用于 MR、评论、审批、Pipeline 和合并 API。
  - SSH Key 用于 `git clone`、`fetch` 和 `push`。
- 拟新增运行时环境变量：`GITLAB_TOKEN`。
- Token 的 `api` scope 只提供 API 能力，最终权限仍由机器人在项目中的角色和保护分支规则决定。

### 5.3 目标配置

```yaml
repo:
  url: $SOURCE_REPO_URL
  base_branch: $SOURCE_REPO_BASE_BRANCH
  provider:
    kind: gitlab
    repository: $SOURCE_REPO_PROVIDER_REPOSITORY
    api_base_url: $SYMPHONY_REPO_PROVIDER_API_BASE_URL
    web_base_url: $SYMPHONY_REPO_PROVIDER_WEB_BASE_URL
```

目标环境值：

```powershell
$env:SOURCE_REPO_URL="git@gitlab-ee.funplus.io:koa-client-code/koa-client-code.git"
$env:SOURCE_REPO_BASE_BRANCH="main" # 联调前确认真实默认分支
$env:SOURCE_REPO_PROVIDER_KIND="gitlab"
$env:SOURCE_REPO_PROVIDER_REPOSITORY="koa-client-code/koa-client-code"
$env:SYMPHONY_REPO_PROVIDER_API_BASE_URL="https://gitlab-ee.funplus.io/api/v4"
$env:SYMPHONY_REPO_PROVIDER_WEB_BASE_URL="https://gitlab-ee.funplus.io"
$env:GITLAB_TOKEN="<从安全环境注入，不写入文件>"
```

### 5.4 API 映射

| Maestro 能力 | GitLab API/语义 |
|---|---|
| `auth_status` / `healthcheck` | 当前用户和目标项目读取接口 |
| `pr_view` | 查询单个 MR，或按源分支解析 MR |
| `pr_create` | 创建 Merge Request |
| `pr_edit` | 更新 MR 标题、描述、目标分支等字段 |
| `pr_issue_comments` | 读取 MR Notes |
| `pr_add_issue_comment` | 创建 MR Note |
| `pr_review_comments` | 读取 MR Discussions |
| `pr_reply_review_comment` | 回复指定 Discussion |
| `pr_reviews` | 读取 MR Approvals/Approval State |
| `pr_submit_review` | 对当前 HEAD SHA 提交 Approve/Unapprove |
| `pr_checks` | MR Pipelines、Pipeline Jobs 和状态归一化 |
| `pr_close` | 将 MR 状态更新为 closed |
| `pr_merge` | 在策略检查后接受 MR |
| `run_list` / `run_view` | 列出 Pipeline、查看 Jobs 和失败日志 |
| `close_open_pull_requests_for_branch` | 查找并关闭指定源分支的 opened MR |

项目路径必须作为完整 namespace 处理，并在 GitLab API 路径中进行 URL 编码，例如 `koa-client-code/koa-client-code` 编码后作为 `projects/:id` 使用。

## 6. Requirements

### 6.1 Must-Have（P0）

#### P0-1：注册与配置 GitLab Provider

工作项：

- [ ] 在 Repo Provider kinds 中新增 `gitlab` 和展示名称 `GitLab`。
- [ ] 在默认 Registry 中注册 GitLab Adapter。
- [ ] 校验 `api_base_url`、`web_base_url`、`repository` 和受支持 options。
- [ ] 确认 `RepositoryRef` 能解析目标 GitLab SSH URL 和多级 namespace；不足时补充实现。
- [ ] 在 Repo Provider 文档中增加 GitLab 配置和环境变量。

验收标准：

- [ ] 给定 `kind: gitlab`，运行时可以解析并加载 GitLab Adapter。
- [ ] 给定目标 SSH URL，得到 `koa-client-code/koa-client-code`。
- [ ] 缺少必要配置或 Token 时，启动或健康检查返回明确、脱敏的错误。

#### P0-2：HTTP Client、认证与错误模型

工作项：

- [ ] 新增 GitLab RuntimeEnv 和 HTTP Client。
- [ ] 使用 `PRIVATE-TOKEN` 请求头，并确保日志、Telemetry 和错误不记录值。
- [ ] 复用通用 timeout、retry 和 backoff 配置。
- [ ] 实现 GitLab 分页响应处理。
- [ ] 归一化 401、403、404、409、422、429 和 5xx。
- [ ] 支持公司内部 CA；禁止以关闭 TLS 验证作为正式解决方案。

验收标准：

- [ ] 有效 Token 能读取当前用户和目标项目。
- [ ] 无效、过期或权限不足的 Token 能被区分并生成可执行错误。
- [ ] 任何测试和运行日志中均无法搜索到完整 Token。
- [ ] 429 和可恢复 5xx 按统一策略重试，非可恢复错误不盲目重试。

#### P0-3：Merge Request 生命周期

工作项：

- [ ] 按 IID、URL、源分支或 HEAD SHA 解析 MR。
- [ ] 实现查看、创建、更新和关闭 MR。
- [ ] 实现按源分支关闭未合并 MR 的清理行为。
- [ ] 将 GitLab payload 归一化为现有 Provider 输出结构。
- [ ] 处理 MR 创建后 diff 信息异步生成的短暂状态。

验收标准：

- [ ] 同一源分支重复执行时更新已有 MR，不重复创建。
- [ ] MR 输出包含稳定的 IID、URL、state、source branch、target branch 和 HEAD SHA。
- [ ] 找不到 MR、存在多个歧义 MR 或状态不允许修改时返回确定性错误。

#### P0-4：评论、讨论与反馈循环

工作项：

- [ ] 读取和添加普通 MR Notes。
- [ ] 读取 MR Discussions 及其 resolved 状态。
- [ ] 回复指定 Discussion。
- [ ] 将系统 Note、普通 Note、Diff Note 和 Discussion Note 映射为统一结构。
- [ ] 实现分页和去重，保证重试不会重复发布同一自动化评论。

验收标准：

- [ ] Maestro 能读取人工评审意见并将其提供给下一次 Codex 运行。
- [ ] Maestro 能向正确的 MR 或 Discussion 发布回复。
- [ ] 未解决讨论能阻止配置为“需要全部解决”的合并流程。

#### P0-5：Pipeline 和 Checks

工作项：

- [ ] 查询 MR 对应的 Pipeline，并处理无 Pipeline、多个 Pipeline 和 detached MR Pipeline。
- [ ] 查询 Pipeline Jobs。
- [ ] 映射 `created`、`pending`、`running`、`success`、`failed`、`canceled`、`skipped`、`manual` 等状态。
- [ ] 在需要诊断时获取失败 Job 的 trace，并执行长度限制和敏感信息过滤。
- [ ] 目标项目负责提供能被分支或 MR 触发的 `.gitlab-ci.yml`。

验收标准：

- [ ] Dashboard/工作流能区分运行中、成功、失败和无 Pipeline。
- [ ] Pipeline 失败时不得报告为成功或可安全合并。
- [ ] Job 日志读取失败不应覆盖真实的 Pipeline 结果。

#### P0-6：`tapd/gitlab/codex` 模板

工作项：

- [ ] 基于现有 `tapd/github/codex` 新增 `tapd/gitlab/codex` 模板。
- [ ] 模板使用 `SOURCE_REPO_PROVIDER_*` 和 `SYMPHONY_REPO_PROVIDER_*` 通用配置。
- [ ] 在模板 README/索引中公开新 alias。
- [ ] 更新中文快速开始、Repo Provider 和测试文档。

验收标准：

- [ ] `--template tapd/gitlab/codex` 可以被模板解析器加载。
- [ ] 模板不调用 GitHub `gh` CLI。
- [ ] 模板启动时会检查 GitLab Token、项目读取权限和 Git SSH 准备状态。

#### P0-7：测试和安全门禁

工作项：

- [ ] 新增 GitLab Adapter contract tests。
- [ ] 新增 HTTP Mock 测试和固定 payload fixtures。
- [ ] 覆盖多级 namespace、URL 编码、分页、限流、冲突和权限错误。
- [ ] 新增 Token/Authorization header 脱敏测试。
- [ ] 更新 Registry、runtime config、RepositoryRef、动态工具和模板测试。
- [ ] 在专用测试项目执行只读 smoke 和受控写入 E2E。

验收标准：

- [ ] GitLab Adapter 通过通用 Provider 契约测试。
- [ ] 文档和模板测试通过。
- [ ] `make all` 和 `make secret-scan` 通过。
- [ ] 未经显式启用，不对真实业务仓库执行创建、关闭或合并等破坏性 smoke。

### 6.2 Nice-to-Have（P1）

#### P1-1：审批状态与提交审批

- [ ] 读取 Approvals 和 Approval State。
- [ ] 在 GitLab 版本/Tier 支持时读取审批规则详情。
- [ ] 使用 MR 当前 HEAD SHA 提交审批，SHA 不匹配时拒绝操作。
- [ ] 等待 GitLab 完成 diff 和 approval 同步，避免新提交导致自动审批立即失效。

#### P1-2：安全合并

- [ ] 合并前检查最新 HEAD SHA、Pipeline、冲突、审批和未解决讨论。
- [ ] 遵守保护分支和项目合并策略。
- [ ] 支持配置 squash 和删除源分支。
- [ ] 记录结构化审计事件，但不得记录 Token。
- [ ] 默认 rollout 策略为“创建 MR 后人工合并”，自动合并必须显式开启。

#### P1-3：运行详情和运维体验

- [ ] 完善 Pipeline/Job 列表、详情和日志查询。
- [ ] Dashboard 展示 GitLab MR、审批和 Pipeline 链接。
- [ ] 为常见错误提供运维提示：VPN、企业 CA、Token scope、项目角色、保护分支和 Runner。

### 6.3 Future Considerations（P2）

- [ ] Merge Train 和 merge when pipeline succeeds。
- [ ] 自动 Rebase 和冲突辅助处理。
- [ ] Draft MR、Reviewer、Assignee、Label 和 Milestone 自动管理。
- [ ] 跨项目 Fork MR。
- [ ] Pipeline retry/cancel/manual job 操作。
- [ ] OAuth 或 GitLab Application 认证。
- [ ] 多 GitLab 实例按仓库路由。

## 7. End-to-End Acceptance Scenario

在专用 GitLab 测试项目执行以下验收流程：

1. 创建一个 TAPD 测试工作项。
2. Maestro 使用 `tapd/gitlab/codex` 模板拉取工作项。
3. Codex 在隔离 workspace 中修改测试仓库。
4. Maestro 通过 SSH 推送新分支。
5. Maestro 创建 GitLab MR，并在重复运行时更新同一个 MR。
6. 人工在 MR 中发布普通评论和 Discussion；Maestro 能读取并回复。
7. Pipeline 运行期间 Maestro 报告 pending/running，结束后报告 success 或 failed。
8. 在失败 Pipeline、缺少审批、存在冲突或未解决讨论时，合并请求被拒绝。
9. 条件全部满足且显式启用自动合并时，只合并预期的 HEAD SHA。
10. 全流程日志和 Dashboard 不出现完整 Token 或敏感 Header。

## 8. Success Metrics

### Leading Indicators

- GitLab Provider 契约测试通过率：100%。
- 专用测试项目中的 MR 创建/更新/评论/Pipeline 读取成功率：连续 10 次运行达到 100%。
- 错误码、分页、重试和 Token 脱敏测试覆盖率：计划内场景 100%。
- 非预期重复 MR 或重复自动化评论：0。

### Lagging Indicators

- 上线后首月由 Provider 导致的错误合并：0。
- 上线后首月凭证泄漏事件：0。
- GitLab 流程需要人工修复 Provider 状态的比例低于 5%。
- 从 TAPD 工作项进入处理到创建 MR 的中位时间不显著高于 GitHub Provider 基线。

## 9. Admin and External Dependencies

开发和联调前必须准备：

- [ ] 确认公司 GitLab EE 的准确版本和 License Tier。
- [ ] 提供与业务仓库隔离的测试项目，允许创建分支、MR、评论、Pipeline 和受控合并。
- [ ] 创建 Project Access Token，建议 `api` scope，并设置有效期和轮换责任人。
- [ ] 确认机器人项目角色：仅创建 MR 通常从 Developer 起步；合并保护分支通常需要更高权限，以实际规则为准。
- [ ] 配置具有目标项目写权限的 SSH Key。
- [ ] 确认真实默认分支名称。
- [ ] 确认 Maestro 运行机器到 GitLab 的 VPN、DNS、代理、防火墙和 API 网络访问。
- [ ] 提供企业 CA 链或操作系统信任配置。
- [ ] 确认项目 `.gitlab-ci.yml` 能为目标分支或 MR 产生 Pipeline。
- [ ] 确认自动化边界：只创建 MR、允许 Approve、或允许满足策略后自动合并。

## 10. Open Questions

### Blocking

1. **[GitLab 管理员]** 当前 GitLab EE 的准确版本和 License Tier 是什么？
2. **[项目管理员]** `koa-client-code/koa-client-code` 的默认分支和保护分支策略是什么？
3. **[安全/项目管理员]** 是否允许 Project Access Token？允许的 scope、角色和有效期是什么？
4. **[项目管理员]** Maestro 是否允许自动 Approve 或自动 Merge？若允许，需要哪些审批、Pipeline 和讨论门禁？
5. **[基础设施]** Maestro 运行环境是否信任 `gitlab-ee.funplus.io` 的证书链，并能访问 `/api/v4`？
6. **[项目管理员]** 哪个项目用于有写入和合并行为的 E2E 测试？

### Non-Blocking

1. **[产品/工程]** v1 是否需要自动设置 Reviewer、Assignee 或 Label？默认放入 P2。
2. **[工程]** 是否需要支持 Job trace 全文展示？默认只保留限长的诊断摘要。
3. **[工程]** 是否需要公开通用 GitLab API passthrough？默认不作为 P0，避免扩大敏感操作面。

## 11. Timeline Considerations

在一名熟悉 Elixir 和 GitLab API 的工程师全职投入、管理员依赖及时就绪的情况下：

| 阶段 | 范围 | 估算 |
|---|---|---:|
| Phase 0 | 版本、权限、网络、CA 和测试项目预检 | 0.5～1.5 个工作日 |
| Phase 1 | Provider 注册、HTTP Client、MR、评论、Pipeline、模板和单元测试 | 5～8 个工作日 |
| Phase 2 | 审批、安全合并、Job 详情、可观测性和兼容性完善 | 4～6 个工作日 |
| Phase 3 | 测试项目 E2E、文档、secret scan 和灰度 | 2～3 个工作日 |

最小可用版本预计 1～2 周；包含审批和安全合并的完整版本预计 2～4 周。GitLab 版本兼容、内部 CA、保护分支权限或测试项目不可用会直接影响工期。

## 12. Suggested Implementation Order

1. 完成 Phase 0，并冻结 GitLab 版本、Token、权限和自动化边界。
2. 注册 GitLab kind、Adapter 骨架、RuntimeEnv 和配置校验。
3. 完成 HTTP Client、项目解析、认证、错误和脱敏。
4. 完成 MR 查询/创建/更新/关闭及契约测试。
5. 完成 Notes、Discussions、Pipeline 和 Jobs。
6. 增加 `tapd/gitlab/codex` 模板及文档。
7. 在测试项目进行只读 smoke，再进行受控写入 E2E。
8. 首次上线只创建 MR、禁止自动合并。
9. 完成 P1 审批和合并门禁后，再灰度启用自动合并。

## 13. Rollout and Rollback

- GitLab Provider 以新 kind 和新模板增量引入，不改变 GitHub/CNB/Memory 默认行为。
- 首次灰度只在专用测试项目启用，并保持自动合并关闭。
- 业务仓库灰度时使用项目级 Token、最小角色和短有效期。
- 出现兼容性或安全问题时，停止使用 `tapd/gitlab/codex` 模板并撤销 Token；现有 Provider 不受影响。
- 回滚不删除已创建的分支、MR 或评论，需由项目管理员按审计记录决定是否保留或关闭。

## 14. References

- Maestro Repo Provider 架构：`docs/repo_provider.md`
- Maestro Repo Provider behaviour：`lib/symphony_elixir/repo_provider/adapter.ex`
- Maestro Repo Provider registry：`lib/symphony_elixir/repo_provider/registry.ex`
- 参考模板：`priv/workflow_extensions/coding_pr_delivery/templates/tapd/github/codex.md`
- GitLab REST API Authentication：<https://docs.gitlab.com/api/rest/authentication/>
- GitLab Access Token Scopes：<https://docs.gitlab.com/security/tokens/access_token_scopes/>
- GitLab Merge Requests API：<https://docs.gitlab.com/api/merge_requests/>
- GitLab Notes API：<https://docs.gitlab.com/api/notes/>
- GitLab Discussions API：<https://docs.gitlab.com/api/discussions/>
- GitLab Merge Request Approvals API：<https://docs.gitlab.com/api/merge_request_approvals/>
- GitLab Jobs API：<https://docs.gitlab.com/api/jobs/>

