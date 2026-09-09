# GitLab Git-only 基础操作落地计划

状态：In Progress（代码、Git SSH 写入验证和质量门禁已完成；TAPD 凭证健康检查及端到端灰度待完成）
版本：Lite（仅 Git 基础操作）  
创建日期：2026-09-02  
最后验证：2026-09-09
适用范围：Maestro Elixir Runtime  
目标实例：`gitlab-ee.funplus.io`  
目标仓库：`koa-client-code/koa-client-code`

## 1. Problem Statement

当前目标只要求 Maestro 在 TAPD 工作流中通过 Git SSH 完成 clone、fetch、branch、diff、commit 和 push。Merge Request 创建或更新、评审反馈、Pipeline、审批和合并全部由人工在 GitLab 中完成，因此没有必要实现完整的 GitLab Repo Provider API。

现有 Repo Core 已经提供所需基础 Git 能力，但现有 `tapd/github/codex` 模板和 `push` 技能包含强制 PR 行为。需要新增一个明确的 Git-only 工作流，使自动化在成功推送工作分支并记录交接信息后停止。

## 2. Goals

1. Maestro 能从 TAPD 工作项创建隔离 workspace，并通过 SSH 克隆目标 GitLab 仓库。
2. Codex 能在工作项专属分支完成修改、验证、提交和推送，并验证远端 SHA 与本地 HEAD 一致。
3. 自动化成功后在 TAPD 记录分支名、commit SHA 和测试结果，再进入人工评审状态。
4. 运行期间不调用 GitHub/GitLab 的 MR、评论、Pipeline、审批或合并 API。
5. 不需要 GitLab API User、API Password、Access Token 或 `glab` CLI。

## 3. Non-Goals

1. 不创建、更新、关闭或合并 GitLab Merge Request；这些操作由人工完成。
2. 不读取或回复 GitLab 评审评论；需要返工时由人工把要求写入 TAPD 并重新进入开发状态。
3. 不读取 Pipeline、Job、审批、冲突或保护分支状态。
4. 不实现 GitLab REST/GraphQL Client，不增加 `GITLAB_TOKEN` 等 API 凭证。
5. 不自动处理 TAPD 的 merging 路由；人工完成 MR 和合并后再手动结束工作项。

## 4. User Stories

### Maestro 操作者

- 作为 Maestro 操作者，我希望用一个 Git-only 模板连接私有 GitLab 仓库，以便自动完成代码修改和分支推送。
- 作为 Maestro 操作者，我希望自动化明确停在人工评审前，以免误创建或合并 MR。
- 作为 Maestro 操作者，我希望在 TAPD 中看到分支名、commit SHA 和验证结果，以便手工创建 MR。

### 开发者与评审者

- 作为开发者，我希望每个 TAPD 工作项使用独立工作分支，避免直接修改默认分支。
- 作为评审者，我希望 MR、Pipeline 检查、反馈和合并仍由人工按现有 GitLab 流程控制。
- 作为开发者，我希望评审返工通过 TAPD 重新进入开发状态，而不是依赖 Maestro 读取 GitLab 评论。

### GitLab 管理员

- 作为 GitLab 管理员，我只需要为 Maestro 提供受限的 SSH 写权限，无需开通 GitLab API 账号或 Token。

## 5. Architecture Decisions

### 5.1 使用 Repo Core，不实现 GitLab API Provider

基础操作继续由 `SymphonyElixir.Repo` 和现有 `repo_checkout`、`repo_diff`、`repo_commit`、`repo_push` typed tools 执行。这些能力只依赖 Git 和目标 remote，与代码托管平台 API 无关。

不新增以下内容：

- GitLab HTTP Client
- GitLab RuntimeEnv/Token
- MR/Note/Discussion/Approval/Pipeline 映射
- GitLab Provider smoke test
- 自动合并逻辑

### 5.2 增加零 API 能力的 `git` Provider

配置当前要求存在一个已注册的 Repo Provider kind。为避免将 GitLab 仓库错误标记为 GitHub，也避免使用会模拟 PR 成功的 Memory Provider，新增轻量 `git` Provider：

```text
kind: git
capabilities: []
```

该 Adapter 只负责通过现有 Provider 配置校验，不声明任何 change-proposal 能力，不执行外部 API 调用。

建议模块：

```text
SymphonyElixir.RepoProvider.Git.Adapter
```

### 5.3 新增 Git-only 模板

新增模板 alias：

```text
tapd/git/codex
```

关键 profile 配置：

```yaml
workflow:
  profile:
    kind: coding_pr_delivery
    version: 1
    options:
      requirements:
        change_proposal: false
        typed_tracker_tools: true
        typed_repo_tools: false
```

说明：

- `change_proposal: false` 取消 MR/PR 作为交付前置条件。
- `typed_repo_tools: false` 在当前 profile 中表示不要求 Repo Provider 的 change-proposal typed tools；Repo Core 的 checkout/diff/commit/push 仍然是必需能力。
- 模板必须使用 `repo_push` typed tool或 `bin/repo push`，不能调用当前会继续创建 PR 的 `push` skill。

### 5.4 TAPD 人工交接边界

建议自动扫描的状态只包括规划和开发：

```yaml
tracker:
  lifecycle:
    active_states:
      - status_4
      - developing
```

规则：

- `planning/status_4`：Maestro 转入开发并开始执行。
- `developing`：修改、验证、commit、push。
- `review/status_5`：人工等待状态，Maestro 不自动执行。
- `merging`：不加入 `active_states`，Maestro 不自动执行 land/merge。
- `resolved/rejected`：终态。
- 如需返工，人工把评审要求同步到 TAPD，再将工作项移回 `developing`。

### 5.5 目标运行配置

```yaml
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
```

PowerShell 环境变量：

```powershell
$env:TAPD_API_USER="<TAPD API 用户>"
$env:TAPD_API_PASSWORD="<TAPD API 密码>"
$env:TAPD_WORKSPACE_ID="<TAPD 项目 ID>"

$env:SOURCE_REPO_URL="git@gitlab-ee.funplus.io:koa-client-code/koa-client-code.git"
$env:SOURCE_REPO_BASE_BRANCH="master" # 2026-09-08 通过 ls-remote --symref 确认
$env:SOURCE_REPO_BRANCH_WORK_PREFIX="maestro/"
```

不需要：

```text
GITLAB_TOKEN
SOURCE_REPO_PROVIDER_REPOSITORY
SYMPHONY_REPO_PROVIDER_API_BASE_URL
SYMPHONY_REPO_PROVIDER_WEB_BASE_URL
```

## 6. Requirements

### 6.1 Must-Have（P0）

#### P0-1：Git SSH 准备

工作项：

- [x] Maestro 运行环境安装可用的 `git` 和 `ssh`。
- [x] 为 Maestro 运行账号配置专用 SSH Key。
- [x] 当前 SSH 公钥已具备目标仓库读取和工作分支写入权限。
- [x] 将 `gitlab-ee.funplus.io` 的 SSH Host Key 加入可信 `known_hosts`。
- [x] SSH 凭证可供非交互 Maestro 进程使用；无需运行时输入私钥口令。
- [x] 配置提交者 `user.name` 和 `user.email`。
- [x] 确认网络、DNS、VPN、防火墙和 SSH 端口可用。

验收标准：

- [x] `ssh -T git@gitlab-ee.funplus.io` 能完成认证，不出现交互式 Host Key 或密码提示。
- [x] `git ls-remote git@gitlab-ee.funplus.io:koa-client-code/koa-client-code.git` 成功。
- [x] 在测试分支执行一次 clone、commit、push 和远端 SHA 校验成功。
- [x] Maestro 对默认分支没有直接 push 要求，`maestro/` 工作分支前缀符合项目策略。

验证记录：常规 shallow clone 在等待超过 3 分钟后人工中止；目标仓库约 146 GB，改用 Repo Core 的 blobless sparse clone（`--depth 1 --filter blob:none --sparse`，并设置 `GIT_LFS_SKIP_SMUDGE=1`）后约 13 秒完成，占用约 119 MB，检出 `master` 且 `remote.origin.promisor=true`。该 clone 验证与此前基于 `master` 的空 commit、`maestro/git-smoke-20260908-1507` 分支 push 和远端 SHA 一致性验证共同完成此项验收。

#### P0-2：零能力 `git` Provider

工作项：

- [x] 在 Repo Provider kinds 中增加 `git` 和显示名称 `Git`。
- [x] 新增 `SymphonyElixir.RepoProvider.Git.Adapter`。
- [x] Adapter 实现 `kind/0`、`defaults/0`、`validate_config/1` 和 `capabilities/0`。
- [x] `capabilities/0` 返回空列表，且不声明任何 MR、review、checks 或 merge 回调。
- [x] 在默认 Registry 中注册 `git` Adapter。

验收标准：

- [x] `repo.provider.kind: git` 能通过配置校验。
- [x] 选择 `git` Provider 时不会生成 Repo Provider change-proposal typed tools。
- [x] 启动和运行过程中不会检查 `gh`、`glab` 或 GitLab API Token。

#### P0-3：`tapd/git/codex` 模板

工作项：

- [x] 基于 `tapd/github/codex` 新增 Git-only 模板。
- [x] 设置 `change_proposal: false` 和 `typed_repo_tools: false`。
- [x] 设置 `repo.provider.kind: git`。
- [x] 从 `active_states` 删除 `merging` 和其他不应自动运行的人工状态。
- [x] 删除 GitHub Provider Notes 和 GitHub 专属前置条件。
- [x] 不包含 MR 创建、评论、checks、land 或 merge 指令。
- [x] 在 Template Catalog 和模板 README 中注册 `tapd/git/codex`。
- [x] 大仓库初始化默认使用 blobless sparse clone，并支持按需扩展 sparse checkout 和显式获取所需 LFS 路径。
- [x] 将 `merging` 和 `rework` 路由策略设为人工等待，避免未激活状态被默认自动派发策略拒绝。

验收标准：

- [x] `--template tapd/git/codex` 可以被发现、渲染和加载。
- [x] 生成的 tool inventory 包含 `repo_checkout`、`repo_diff`、`repo_commit`、`repo_push`。
- [x] 生成的 tool inventory 不包含 change-proposal、review、checks 和 merge 工具。
- [x] 渲染后的提示词不包含要求创建 GitHub PR 或 GitLab MR 的指令。

#### P0-4：Git-only 执行生命周期

Agent 主流程必须是：

1. 读取 TAPD 工作项和 canonical workpad。
2. 同步默认分支。
3. 创建工作项专属分支，不直接在默认分支工作。
4. 修改代码并运行目标仓库要求的测试。
5. 使用 `repo_diff` 验证预期变更。
6. 使用 `repo_commit` 提交。
7. 使用 `repo_push` 推送并验证 `published_head_sha == head_sha`。
8. 在 TAPD workpad 记录仓库、分支、commit SHA、测试结果和建议 MR 标题/说明。
9. 将工作项移动到人工评审状态后停止。

工作项：

- [x] 新增 Git-only lifecycle partial，或在模板中提供等价的独立执行说明。
- [x] 明确禁止调用 Repo Provider change-proposal 工具。
- [x] 明确禁止调用会创建 PR 的现有 `push` skill。
- [x] 优先使用 `repo_push` typed tool；仅在 inventory 不可用时使用 `bin/repo push`。
- [x] push 被拒绝时区分非 fast-forward、权限、认证和保护分支错误。
- [x] 非 fast-forward 时允许按现有 Repo Core 流程同步并重新验证；认证和权限错误必须停止并报告。

验收标准：

- [ ] 成功路径在 push 和 TAPD 人工交接后停止。
- [x] 失败路径不会为了绕过权限而重写 remote、切换协议或使用强制 push。
- [x] 默认禁止 `--force`；只有明确发生历史重写时才能使用 `--force-with-lease`。
- [x] 不会直接提交或推送到 `main` 等默认分支。

#### P0-5：测试与文档

工作项：

- [x] 增加 `git` Adapter contract/registry/config 测试。
- [x] 增加模板发现、渲染和 profile requirements 测试。
- [x] 增加 dynamic tool inventory 正向和负向断言。
- [x] 增加 Git-only 提示词中不存在 PR/MR/merge 指令的测试。
- [x] 使用本地 bare Git 仓库测试 clone、branch、commit、push 和 published SHA，不依赖 GitLab API。
- [x] 更新模板 README、Repo Provider 文档和测试文档。

验收标准：

- [x] 相关定向测试通过。
- [x] `make all` 通过。
- [x] `make secret-scan` 通过。
- [x] 只在获得显式授权后向真实业务仓库的独立工作分支执行写入 smoke。

`make all` 记录：2026-09-09 最终完整命令通过；全量测试为 2493 tests、0 failures、19 skipped，覆盖率 72.98%，Dialyzer `Total errors: 0`。此前 EventStore 队列压力、reconciliation 异步事件顺序及 prompt builder 全局状态测试曾非确定失败；对应测试在原始 Maestro 或隔离重复运行中也可复现/通过，最终完整门禁已通过。

TAPD 只读 smoke 记录：模板配置校验通过；2026-09-09 使用更新后的 `.env.gitlab.local` 凭证重跑 `GET /quickstart/testauth`，返回 HTTP 200，TAPD API 认证通过。未执行任何工作项写操作。

### 6.2 Nice-to-Have（P1）

- [ ] 新增独立 `publish-branch` workspace skill，只负责验证、push 和远端 SHA 校验，不创建 PR。
- [ ] 在 Dashboard 展示最后推送的分支和 commit SHA，但不查询 GitLab API。
- [ ] 自动生成供人工复制的 MR 标题和描述文本，并记录在 TAPD workpad。
- [ ] 为 SSH Key、Host Key、DNS、VPN 和权限错误提供更明确的诊断提示。

### 6.3 Future Considerations（P2）

- [ ] 如果后续需要自动创建 MR，再单独启动完整 GitLab Provider 计划。
- [ ] 如果后续需要读取评审反馈、Pipeline 或审批，再按能力逐项增加 GitLab API。
- [ ] 如果后续需要自动合并，必须另行定义审批、checks、冲突和保护分支门禁。

## 7. End-to-End Acceptance Scenario

使用专用测试分支或测试仓库执行：

1. TAPD 测试工作项进入规划状态。
2. Maestro 使用 `tapd/git/codex` 创建隔离 workspace。
3. `after_create` 通过 SSH 将目标仓库克隆到 `repo/`。
4. Maestro 同步 `origin/master` 并创建带 `maestro/` 前缀的工作分支。
5. Codex 完成一项无风险测试修改并运行仓库验证。
6. Maestro commit 并 push 工作分支。
7. Maestro 验证远端分支 SHA 与本地 HEAD 一致。
8. TAPD workpad 记录分支、SHA、测试结果和人工 MR 建议文本。
9. TAPD 工作项进入人工评审状态，Maestro 停止处理。
10. 人工创建 MR、处理评论、观察 Pipeline、合并并关闭 TAPD 工作项。

整个自动化过程中不得调用 GitHub/GitLab MR、评论、Pipeline、审批或合并 API。

## 8. Success Metrics

### Leading Indicators

- Git-only 模板的发现、渲染和配置测试通过率：100%。
- 测试仓库 clone/branch/commit/push/远端 SHA 校验连续 10 次成功率：100%。
- 自动化创建 MR、调用 Provider API或尝试自动合并的次数：0。
- 直接推送默认分支的次数：0。

### Lagging Indicators

- 上线后首月 Git-only 工作流导致的错误远端写入：0。
- 上线后首月 SSH 私钥或敏感认证信息泄漏事件：0。
- 成功 push 后因缺少分支/SHA/测试信息而无法人工创建 MR 的比例：低于 5%。

## 9. Admin and External Dependencies

- [x] 确认 `koa-client-code/koa-client-code` 的真实默认分支为 `master`。
- [x] 确认允许的自动化分支前缀为 `maestro/`。
- [x] 为 Maestro 运行账号提供目标仓库读取和工作分支写入权限。
- [x] 当前 SSH 身份可非交互认证，Host Key 已可信，且已确认为 Maestro 正式专用 Key。
- [x] 确认 Maestro 运行环境能访问 GitLab SSH 服务。
- [x] 已在独立工作分支 `maestro/git-smoke-20260908-1507` 完成首次写入验收。
- [x] 确认 TAPD 中“人工评审”和“完成”对应的原始状态值分别为 `status_5` 和 `resolved`。
- [x] 确认人工评审反馈回到 TAPD 后使用 `developing` 状态重新触发开发。

正式环境配置记录：`elixir/.env.gitlab.local` 中 TAPD 凭证变量、Workspace、目标仓库、`master` 默认分支和 `maestro/` 工作分支前缀均已填写；该文件保持本地私密且不受 Git 跟踪。2026-09-09 使用更新后的凭证执行只读健康检查，`GET /quickstart/testauth` 返回 HTTP 200，TAPD 凭证已通过运行时有效性验证。

本地一键启动命令：`./elixir/bin/start-tapd-gitlab`。该脚本自动加载上述私密环境文件，默认仅监听 `127.0.0.1:4000`。

无需管理员提供 GitLab API User、API Password、Access Token、GitLab 版本或 License Tier。

## 10. Open Questions

### Blocking

1. **[已解决]** 默认分支为 `master`（2026-09-08 通过 Git SSH `ls-remote --symref` 确认）。
2. **[已解决]** 允许 Maestro 创建 `maestro/` 前缀的工作分支。
3. **[已解决]** 当前 SSH Key 已确认为 Maestro 正式专用 Key，并具备目标仓库工作分支写权限。
4. **[已解决]** 人工评审为 `status_5`，完成为 `resolved`，评审返工后使用 `developing` 重新触发开发。
5. **[已解决]** 首次真实 push 验收使用 `koa-client-code/koa-client-code` 的 `maestro/git-smoke-20260908-1507` 分支。
6. **[已解决]** 已更新 `.env.gitlab.local` 中匹配的 TAPD API 用户和 API Token；2026-09-09 只读 `testauth` 返回 HTTP 200。

### Non-Blocking

1. **[工程]** 是否在 P0 同时新增 `publish-branch` skill？默认先直接使用 `repo_push` typed tool。
2. **[产品/项目管理员]** 是否需要在 TAPD workpad 中生成固定格式的 MR 标题和描述？

## 11. Timeline Considerations

在 SSH 和 TAPD 状态信息及时就绪的情况下：

| 阶段 | 范围 | 估算 |
|---|---|---:|
| Phase 0 | SSH、网络、默认分支和 TAPD 状态预检 | 0.5 个工作日 |
| Phase 1 | `git` Adapter、Registry 和配置测试 | 0.5 个工作日 |
| Phase 2 | `tapd/git/codex` 模板、Git-only 生命周期和模板测试 | 0.5～1 个工作日 |
| Phase 3 | 本地 Git E2E、测试分支 smoke、文档和门禁 | 0.5～1 个工作日 |

总预计：1～3 个工作日。该范围不依赖 GitLab API 开通流程。

## 12. Suggested Implementation Order

1. 确认默认分支、分支前缀、TAPD 状态和测试仓库。
2. 完成 SSH 认证、Host Key、提交身份和 `git ls-remote` 预检。
3. 新增零能力 `git` Provider 并完成 Registry/config 测试。
4. 新增 `tapd/git/codex` 模板和 Git-only lifecycle。
5. 增加模板和 dynamic tool inventory 测试。
6. 使用本地 bare 仓库完成无外部依赖的 Git E2E。
7. 在测试分支执行一次真实 GitLab push smoke。
8. 通过质量门禁后，先以单并发在目标项目灰度。

## 13. Rollout and Rollback

- 新增 `git` kind 和 `tapd/git/codex` alias，不改变 GitHub、CNB、Memory 的现有行为。
- 首次灰度保持 `max_concurrent_agents: 1`，只处理明确标记的 TAPD 测试工作项。
- 回滚时停止使用 `tapd/git/codex` 并移除/禁用 Maestro 的 SSH Key。
- 回滚不会自动删除已经推送的远端分支；由项目管理员决定保留或删除。
- 因为没有 GitLab API 操作，回滚不涉及 MR、评论、审批、Pipeline 或合并状态修复。

## 14. References

- Repo Core facade：`lib/symphony_elixir/repo.ex`
- Repo Core typed tools：`lib/symphony_elixir/repo/tool_executor.ex`
- Coding PR Delivery profile options：`lib/symphony_elixir/workflow/extensions/coding_pr_delivery/profile/options.ex`
- Coding PR Delivery required capabilities：`lib/symphony_elixir/workflow/extensions/coding_pr_delivery/profile/capabilities.ex`
- Repo Provider registry：`lib/symphony_elixir/repo_provider/registry.ex`
- 现有 TAPD/GitHub 参考模板：`priv/workflow_extensions/coding_pr_delivery/templates/tapd/github/codex.md`
- 现有 push skill：`priv/workspace_automation/skills/repo/push/SKILL.md`
