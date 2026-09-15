# GitLab Git-only（SSH 写入 + 只读搜索）落地计划

> 更新（2026-09-15）：本文已按 Maestro 当前实现重新校准。Lite 边界不再是“零 GitLab API”，而是“Git SSH 写入 + 唯一只读 GitLab blob 搜索 API”。MR、评论、Pipeline、审批和合并仍由人工处理。

- 状态：In Progress（代码路径、模板、定向测试、Git SSH 写入 smoke 和历史质量门禁已完成；真实任务的 Maestro typed-tool 端到端灰度仍待完成）
- 版本：Lite
- 创建日期：2026-09-02
- 代码对齐日期：2026-09-15
- 最近完整质量门禁记录：2026-09-09
- 适用范围：Maestro Elixir Runtime
- 目标实例：`gitlab-ee.funplus.io`
- 目标仓库：`koa-client-code/koa-client-code`

## 1. Problem Statement

Maestro 需要在 TAPD 工作流中处理大型私有 GitLab 仓库：先远程定位代码，再仅展开必要目录，最后通过 Git SSH 完成 checkout、diff、commit、push 和远端 SHA 校验。创建或更新 Merge Request、读取评审意见、查询 Pipeline、审批及合并仍由人工在 GitLab 中完成，因此无需实现完整 GitLab Repo Provider。

目标仓库体积约 146 GB。普通 shallow clone 仍然过慢，因此当前模板使用共享 Git object cache、blobless sparse clone、sparse index 和按需目录展开。为避免在定位文件前下载大量 blob，`git` Adapter 仅增加一个受控的 GitLab 只读代码搜索能力。

TAPD Bug 还要求独立的 AI 工作流闭环：只有 Bug 的 `AI特殊工作流` 为 `接受/处理` 且状态处于 `new`/`reopened` 时才允许派发；执行前检查评论中已有的 `### Confusions`；成功后写为 `AI已解决`，确认阻塞或相关不可恢复异常时写为 `AI异常`。已废弃的 `AI是否遇到异常` 字段不得再读写。

## 2. Goals

1. 从 TAPD Story 或 Bug 创建隔离 workspace，并通过 SSH 初始化目标仓库。
2. 在下载 blob 前使用 `repo_remote_search` 定位文件，再用 `repo_sparse_add` 仅展开最小必要目录。
3. 从工作项 `代码分支` 指定的开发基线创建专属工作分支；字段缺失时回退到 `repo.base_branch`。
4. 完成修改、验证、diff、commit、push，并校验 `publishedHeadSha == headSha`。
5. 在 canonical workpad 记录仓库、分支、commit SHA、验证结果以及供人工使用的 MR 标题和说明。
6. Story 成功后进入人工评审状态；Bug 成功后保持 Bug 状态不变，仅将 `AI特殊工作流` 更新为 `AI已解决`。
7. Bug 执行前复核历史 `Confusions`。只有问题当前仍存在才视为阻塞，并由 Maestro 将 `AI特殊工作流` 更新为 `AI异常`。
8. 除 `repo_remote_search` 外，不调用 GitLab 的 MR、评论、Pipeline、审批或合并 API。

## 3. Non-Goals

1. 不创建、更新、关闭或合并 GitLab Merge Request。
2. 不读取或回复 GitLab 评审评论；返工要求由人工同步到 TAPD。
3. 不读取 Pipeline、Job、审批、冲突或保护分支状态。
4. 不实现完整 GitLab REST/GraphQL Provider；只保留 blob search 所需的只读 `GET /projects/:id/search?scope=blobs`。
5. 不把 `GITLAB_API_TOKEN` 暴露给 Codex shell，也不允许 Agent 直接请求 GitLab API。
6. 不自动处理 Story 的 merging 路由，也不改变 Bug 的 TAPD 状态。
7. 不再使用已废弃的 `AI是否遇到异常` 字段。

## 4. User Stories

### Maestro 操作者

- 使用 `tapd/git/codex` 连接私有 GitLab，在单并发下自动完成代码修改和工作分支推送。
- 启动时校验远程搜索、稀疏展开和 Bug AI 完成工具，缺少必需能力时立即失败，而不是运行到一半才阻塞。
- 在 TAPD workpad 中看到分支、SHA、验证结果和建议 MR 文本，以便人工接管。
- 对 Bug 明确区分成功与异常，不依赖废弃字段。

### 开发者与评审者

- 每个 TAPD 工作项使用独立工作分支，不直接修改开发基线或最终集成分支。
- MR、Pipeline、评审、审批和合并继续由人工控制。
- 评审返工通过 TAPD 回到 `developing`，Maestro 从 canonical workpad 继续执行。

### GitLab 管理员

- 为 Git 写操作提供受限 SSH 权限。
- 为只读代码搜索提供最小权限的 `read_api` Token；Token 仅存在于 Maestro 服务环境，不进入 Agent shell。

## 5. Current Architecture Decisions

### 5.1 Repo Core 负责 Git 写入

以下工具由 `SymphonyElixir.Repo` 提供，不依赖托管平台 change-proposal API：

- `repo_sparse_add`
- `repo_checkout`
- `repo_diff`
- `repo_commit`
- `repo_push`

`repo_push` 是交付边界。成功必须同时满足工作分支已发布且 `publishedHeadSha` 与本地 `headSha` 一致。模板禁止直接向开发基线或最终集成分支提交或推送，也禁止普通 `--force`。

### 5.2 `git` Adapter 只增加 GitLab 只读搜索

当前 Provider 配置仍是：

```text
kind: git
capabilities: [:code_search]
```

`SymphonyElixir.RepoProvider.Git.Adapter` 不提供 change proposal、review、checks、pipeline、approval 或 merge 能力。仅当 `repo.provider.options.remote_code_search: gitlab` 时，Maestro 暴露 `repo_remote_search`。

搜索实现位于 `SymphonyElixir.RepoProvider.GitLab.CodeSearch`，行为如下：

- 使用 GitLab `GET /projects/:id/search`，固定 `scope=blobs`。
- 支持 `query`、`ref`、可选安全相对路径 `path` 和 `max_results`。
- 默认最多 20 条，最大 100 条；返回规范化的 path、filename、startline、snippet 和 ref。
- API base URL 和 project id 可从标准 Git remote 推导，也允许显式覆盖。
- `GITLAB_API_TOKEN` 由 Maestro 服务端注入 `Private-Token` header；工具 schema、结果和错误诊断不得泄漏 Token。

### 5.3 `tapd/git/codex` 模板

Profile 保持 Git-only 交付：

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

这里的 `typed_repo_tools: false` 只表示不要求 Repo Provider 的 change-proposal 工具；Repo Core 工具仍是工作流必需能力。

模板启动时通过 `TapdGitCodexCapabilities` 强制解析三项能力：

- `repo.remote_search`
- `repo.sparse_add`
- `tracker.complete_ai_workflow`

任一能力不可用时，配置加载返回 `tapd_git_codex_required_tool_unavailable`，不启动任务。

最终 Repo inventory 应精确包含：

```text
repo_remote_search
repo_sparse_add
repo_checkout
repo_diff
repo_commit
repo_push
```

不得包含 change-proposal、review、checks 或 merge 工具。

### 5.4 大仓库 workspace 策略

`after_create` 为每个 remote 准备共享 bare object cache，默认位于：

```text
$SYMPHONY_WORKSPACE_ROOT/.git-object-cache
```

也可通过 `SYMPHONY_GIT_OBJECT_CACHE_ROOT` 指向其他持久目录。cache 准备使用 `flock` 串行化；任务 clone 使用：

```text
--depth 1 --filter blob:none --sparse --reference-if-able <cache>
```

同时设置 `GIT_LFS_SKIP_SMUDGE=1` 并启用 sparse index。任务 workspace 删除时保留共享 object cache；只为明确需要的路径获取 LFS 对象。

### 5.5 TAPD Story 与 Bug 的不同交接边界

Story：

- 自动路由只覆盖 `status_4` 和 `developing`。
- 成功 push、SHA 校验和 workpad 交接后，通过 typed tracker tool 移动到 `status_5` 人工评审。
- `merging`、`rework` 为人工等待，完成态为 `status_6`；需求主任务还支持 `status_8`。

Bug：

- 仅当负责人匹配、状态位于 `new`/`reopened` 且 `AI特殊工作流=接受/处理` 时参与派发。
- 执行前读取包含评论的 snapshot，逐项复核所有 `### Confusions`；历史记录的存在本身不构成阻塞。
- 仍存在的 Confusion 要通过 `tracker.upsert_workpad` 的 `outcome: blocked_confusions` 把完整当前证据写入 canonical workpad；该结构化信号会在当前 turn 结束时立即停止 worker，由 Maestro 将 `AI特殊工作流` 更新为 `AI异常` 并抑制重试，不再等待 `max_turns` 耗尽。
- Confusion 已消失时，在 workpad 中标记 resolved 并继续。
- 成功交付后调用 `tracker.complete_ai_workflow`，在状态仍有效且值仍为 `接受/处理`（或已幂等为 `AI已解决`）时写入 `AI已解决`，随后回读 Bug；只有回读确认后才以调用方提供的最终 body 更新原 canonical workpad。
- 人工新增修改意见并把字段重置为 `接受/处理` 后，Bug 可重新派发。新一轮按未处理的人类评论 ID 建立 `Rework Round N`，继续原 workpad 和原已发布工作分支。
- Bug 状态不改变。typed-tool blocker 等异常退出路径由 Orchestrator 尝试写入 `AI异常`；写入成功或失败均产生事件。

### 5.6 目标运行配置

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
    options:
      remote_code_search: gitlab
      gitlab_api_base_url: $GITLAB_API_BASE_URL
      gitlab_project_id: $GITLAB_PROJECT_ID

tracker:
  provider:
    platform:
      bug_ai_workflow:
        field: $TAPD_BUG_AI_WORKFLOW_FIELD
        accepted_value: 接受/处理
        resolved_value: AI已解决
        exception_value: AI异常
        active_states: [new, reopened]
```

关键环境变量：

```powershell
$env:TAPD_API_USER="<TAPD API 用户>"
$env:TAPD_API_PASSWORD="<TAPD API 密码>"
$env:TAPD_WORKSPACE_ID="<TAPD 项目 ID>"
$env:TAPD_ASSIGNEE="<允许派发的 TAPD 用户显示名>"
$env:TAPD_BUG_AI_WORKFLOW_FIELD="custom_field_<实际字段>"
$env:TAPD_BUG_AI_MODEL_LEVEL_FIELD="custom_field_7"
$env:SYMPHONY_AGENT_MODEL="gpt-5.6-luna"

$env:SOURCE_REPO_URL="git@gitlab-ee.funplus.io:koa-client-code/koa-client-code.git"
$env:SOURCE_REPO_BASE_BRANCH="master"
$env:SOURCE_REPO_BRANCH_WORK_PREFIX="maestro/"

$env:GITLAB_API_TOKEN="<仅需 read_api 权限>"
# 标准 SSH remote 可自动推导，非标准部署或需要覆盖时再设置：
$env:GITLAB_API_BASE_URL="https://gitlab-ee.funplus.io/api/v4"
$env:GITLAB_PROJECT_ID="koa-client-code/koa-client-code"
```

`GITLAB_API_TOKEN` 必须保存在 Maestro 服务环境。`tapd/git/codex` 的 Codex 命令显式通过 `shell_environment_policy.exclude` 排除该变量。

## 6. Requirements and Current Status

### 6.1 Must-Have（P0）

#### P0-1：Git SSH 与大仓库准备

- [x] `git`、`ssh`、Host Key、非交互 SSH Key、提交者身份和网络预检完成。
- [x] `ssh -T` 与 `git ls-remote` 验证通过。
- [x] 在 `maestro/git-smoke-20260908-1507` 完成 clone、commit、push 和远端 SHA 校验。
- [x] blobless sparse clone 验证通过；历史记录约 13 秒、约 119 MB，替代超过 3 分钟仍未完成的普通 shallow clone。
- [x] 使用共享 object cache、sparse index 和按需 LFS 策略。

#### P0-2：Git Provider 与只读远程搜索

- [x] 注册 `git` kind 和 `SymphonyElixir.RepoProvider.Git.Adapter`。
- [x] Adapter 只声明 `:code_search`，不声明 MR/review/checks/merge 能力。
- [x] 实现 GitLab blob search、路径过滤、结果上限、错误规范化和 Token 脱敏。
- [x] `repo_remote_search` 只在 `remote_code_search: gitlab` 配置下出现。
- [x] Agent shell 不包含 `GITLAB_API_TOKEN`。

#### P0-3：稀疏展开与必需工具门禁

- [x] 提供 `repo_sparse_add`，拒绝仓库根目录、绝对路径、路径穿越和 ref 中不存在的目录。
- [x] 模板要求先远程搜索、后最小化 sparse add，再读取或编辑代码。
- [x] 启动时 fail-fast 校验 remote search、sparse add 和 Bug AI completion 能力。
- [x] inventory 不包含任何 change-proposal/review/checks/merge 工具。

#### P0-4：Git-only 执行生命周期

标准流程：

1. 读取 TAPD snapshot、评论和 canonical workpad。
2. Bug 先复核所有 `### Confusions`；当前阻塞存在则记录证据并停止，由 Maestro 写 `AI异常`。
3. 记录复现或基线，校准计划、验收标准和验证清单。
4. 从 `代码分支` 或 fallback base 创建符合前缀规则的专属工作分支。
5. `repo_remote_search` 定位，`repo_sparse_add` 展开最小目录。
6. 修改并运行目标仓库要求的验证。
7. `repo_diff` 开启 whitespace check 并确认只包含预期变更。
8. `repo_commit` 后通过 `repo_push` 发布并校验 SHA。
9. workpad 记录 repo、branch、SHA、验证结果、`suggested_mr_title` 和 `suggested_mr_description`；返工轮次额外记录已处理的人类评论 ID。
10. Story 移动到人工评审；Bug 调用 `tracker.complete_ai_workflow` 写 `AI已解决`、回读确认并更新最终 Workpad，随后立即停止。

状态：

- [x] 生命周期、分支保护、push 错误策略和人工 MR 边界已写入模板 partial。
- [x] canonical workpad 在 workspace root 镜像为 `.symphony-tapd-workpad.md`，不得进入 `repo/` 或提交。
- [x] workpad 已要求生成供人工使用的 MR 标题和说明。
- [x] Bug success/exception 字段闭环及废弃字段禁用规则已实现。
- [x] Bug 完成工具要求 canonical `workpad_id` 和最终 `body`，字段回读成功后才勾选最终 Workpad。
- [x] Bug 重新接受后按新增评论 ID 建立返工轮次，并复用原发布分支。
- [ ] 使用真实候选任务完成一次完全由 Maestro typed tools 驱动的成功路径灰度。

#### P0-5：测试与文档

- [x] Git Adapter contract/registry/config 测试。
- [x] GitLab code search 请求、响应、错误和 Token 脱敏测试。
- [x] `repo_sparse_add` 和 Repo inventory 正反向测试。
- [x] 模板发现、渲染、配置、必需能力和不含 MR 工具的测试。
- [x] TAPD Bug `接受/处理`、`AI已解决`、`AI异常`、候选过滤和完成工具测试。
- [x] 本地 bare Git clone/branch/commit/push/published SHA 测试。
- [x] Repo Provider、operations、testing 和模板文档已同步。
- [ ] 2026-09-15 当前工作树变更完成定向测试和完整质量门禁复验。

历史验证记录：2026-09-09 `make all` 通过，2493 tests、0 failures、19 skipped，覆盖率 72.98%，Dialyzer `Total errors: 0`；`make secret-scan` 通过。该记录早于 2026-09-15 的 Bug AI 异常闭环调整，不能替代当前复验。

### 6.2 Nice-to-Have（P1）

- [ ] 新增独立 `publish-branch` workspace skill，仅负责验证、push 和 SHA 校验。
- [ ] Dashboard 展示最近发布的工作分支和 commit SHA，且不额外查询 GitLab API。
- [ ] 为 SSH Key、Host Key、DNS、VPN、GitLab search 5xx 和权限错误提供更明确诊断。
- [ ] 为 object cache 增加容量、最近更新时间和安全清理可观测性。

### 6.3 Future Considerations（P2）

- [ ] 如需自动创建 MR，单独启动完整 GitLab Provider 计划。
- [ ] 如需评审反馈、Pipeline 或审批，按最小权限逐项增加能力。
- [ ] 如需自动合并，另行定义审批、checks、冲突和保护分支门禁。

## 7. End-to-End Acceptance Scenarios

### 7.1 共用 Git 路径

1. Maestro 以 `tapd/git/codex` 创建隔离 workspace，并确认三项必需能力可用。
2. `after_create` 准备共享 object cache，通过 SSH 对工作项开发基线执行 blobless sparse clone。
3. Agent 使用 `repo_remote_search` 和明确的 development ref 定位文件。
4. Agent 通过 `repo_sparse_add` 只展开需要的目录。
5. Agent 在 `maestro/` 工作分支完成修改和验证。
6. Agent 依次执行 `repo_diff`、`repo_commit`、`repo_push`，并确认 published SHA 等于 HEAD。
7. canonical workpad 记录完整交接信息。

### 7.2 Story 成功路径

1. Story 处于可派发规划/开发状态并匹配负责人。
2. 完成共用 Git 路径。
3. Maestro 将 Story 移到 `status_5` 人工评审并停止。
4. 人工创建 MR、处理评论、观察 Pipeline、审批和合并。

### 7.3 Bug 成功路径

1. Bug 处于 `new`/`reopened`，匹配负责人，且 `AI特殊工作流=接受/处理`。
2. 评论中的历史 `Confusions` 均已复核；不存在当前阻塞，或已在 workpad 标记为 resolved。
3. 完成共用 Git 路径。
4. `tracker.complete_ai_workflow` 将 `AI特殊工作流` 写为 `AI已解决`，回读 Bug 确认该值，再更新原 canonical workpad 的最终勾选。
5. Bug 原状态不变；任务 workspace 删除，共享 object cache 保留。

### 7.4 Bug 返工路径

1. 人工在上次完成后新增修改意见，并把 `AI特殊工作流` 重置为 `接受/处理`。
2. Maestro 重新派发该 Bug；Agent 读取最多 100 条评论，用未记录的人类评论 ID 建立新的 `Rework Round N`。
3. Agent 从原 workpad 读取 `branch_name` 和 `published_head_sha`，fetch 并恢复原工作分支，确认其历史包含上次发布 SHA。
4. Agent 在同一分支完成修改、验证、commit 和 push，并把本轮评论 ID、验证和新 SHA 写入同一 workpad。
5. 完成工具再次执行字段写入、回读和最终 Workpad 更新。

### 7.5 Bug Confusion/异常路径

1. 执行前发现某条 `Confusions` 描述的问题当前仍存在。
2. canonical workpad 记录完整当前证据，Agent 停止继续修改。
3. Maestro 将 `AI特殊工作流` 写为 `AI异常`、抑制重试并结束该次处理。
4. 全流程不读取或写入已废弃的 `AI是否遇到异常` 字段。

所有场景中，唯一允许的 GitLab HTTP API 是 `repo_remote_search` 的只读 blob search；不得调用 MR、评论、Pipeline、审批或合并 API。

## 8. Success Metrics

### Leading Indicators

- 模板发现、渲染、配置和必需能力测试通过率：100%。
- Repo inventory 与预期六个工具完全一致。
- GitLab Token 出现在 Agent shell、tool schema、结果或错误日志中的次数：0。
- 直接推送开发基线/最终集成分支或普通 force push 的次数：0。
- Bug 成功后错误改变状态的次数：0；应只更新 `AI特殊工作流`。
- 当前仍存在的 Confusion 未进入 `AI异常` 的次数：0。

### Lagging Indicators

- 上线后首月错误远端写入：0。
- SSH 私钥、TAPD 凭证或 GitLab Token 泄漏事件：0。
- 成功 push 后因缺少分支、SHA、验证或 MR 建议文本而无法人工接管的比例低于 5%。
- 被 `AI已解决`/`AI异常` 过滤的 Bug 被重复派发次数：0。

## 9. Admin and External Dependencies

- [x] 目标仓库默认分支为 `master`，允许 `maestro/` 工作分支。
- [x] Maestro 专用 SSH 身份具备读取和工作分支写权限，Host Key 已可信。
- [x] TAPD API 认证健康检查已通过，且通过 `TAPD_ASSIGNEE` 限制派发范围。
- [x] Story 人工评审状态为 `status_5`，完成状态为 `status_6`；需求主任务还支持 `status_8`。
- [x] `TAPD_BUG_AI_WORKFLOW_FIELD=custom_field_6`，字段选项已确认包含 `接受/处理`、`AI已解决`、`AI异常`。
- [x] `TAPD_BUG_AI_MODEL_LEVEL_FIELD=custom_field_7`，字段选项已确认为 `low`、`medium`、`high`、`xhigh`。
- [ ] 配置最小权限 `GITLAB_API_TOKEN`（`read_api`），并验证目标 GitLab 实例的 blob search 可用。
- [ ] 正式重启前再次确认启用的工作项类型和历史候选范围，避免批量误触发。

凭证应保存在外部 `0600` 环境文件中，默认路径为 `/home/admin2/workspace_other/Env/symphony/tapd-gitlab.env`；可通过 `SYMPHONY_TAPD_GITLAB_ENV_FILE` 覆盖。`.env.gitlab.local` 只保存外部文件指针或非敏感本地配置，不应承载长期凭证。重试运行上限也在该外部文件中通过 `SYMPHONY_MAX_RETRY_ATTEMPTS` 配置，默认值为 `3`；仅因执行槽已满而等待不会增加该计数，也不会启动模型会话。大型浅克隆仓库可通过 `SYMPHONY_WORKSPACE_HOOK_TIMEOUT_MS` 配置工作区钩子超时（建议 `300000`）；`before_run` 先比较远端与本地基线 SHA，相同则跳过 fetch。写入 `AI异常` 前后均回读 Bug，且只有字段仍为 `接受/处理`、状态仍允许 AI 执行时才写入，禁止覆盖 `AI已解决` 或其他人工值。Codex 模型通过 `SYMPHONY_AGENT_MODEL` 传给原生 `thread/start.model`；`AI模型等级` 通过 `TAPD_BUG_AI_MODEL_LEVEL_FIELD` 读取，按 Bug 分别把 `low`、`medium`、`high`、`xhigh` 传给原生 `turn/start.effort`。字段为空或非法时 effort 使用 `medium`，两项均无需修改核心 workflow 命令。

本地启动命令：`./elixir/bin/start-tapd-gitlab`。
本地重启命令：`./elixir/bin/restart-tapd-gitlab`。

## 10. Remaining Decisions

### Blocking

1. **[待验证]** 真实 GitLab 实例的 `scope=blobs` 搜索是否对目标项目、目标 ref 和当前 `read_api` Token 稳定返回；需要纳入灰度前预检。
2. **[待执行]** 选择一个明确授权的 Story 和一个 Bug，分别完成 typed-tool E2E；Bug 场景还需覆盖 Confusion 存在/不存在分支。

### Non-Blocking

1. **[工程]** 是否增加独立 `publish-branch` skill；当前 `repo_push` 已满足 P0。
2. **[运维]** object cache 的保留期和清理策略。

## 11. Remaining Rollout Order

1. 运行当前工作树的定向测试、架构测试、`make all` 和 secret scan。
2. 验证外部环境文件权限、GitLab `read_api` Token、API endpoint/project 推导和搜索结果。
3. 在授权测试 Bug 上验证 candidate 过滤和 Confusions 前置检查，不存在阻塞时完成成功路径。
4. 在单独授权 Bug 上验证当前 Confusion 或 typed-tool blocker 会写入 `AI异常` 且不重试。
5. 在授权 Story 上验证 push 后进入人工评审。
6. 保持 `max_concurrent_agents: 1` 灰度，观察事件、workspace 清理和 object cache。
7. 稳定后再扩大 TAPD 工作项类型或候选范围。

## 12. Rollback

- 停止 `tapd/git/codex` 实例即可阻止新任务派发。
- 撤销 GitLab API Token 只会关闭远程搜索能力；启动门禁会阻止缺少必需工具的工作流继续运行。
- 撤销 SSH Key 可阻止后续 clone/fetch/push。
- 回滚不会自动删除已推送的远端分支，也不会修改人工创建的 MR、Pipeline、审批或合并状态。
- 已写入的 `AI已解决` 或 `AI异常` 不自动回滚；如属误写，由 TAPD 管理员按审计记录人工恢复。
- 删除任务 workspace 时不得同时删除仍被其他 clone 引用的共享 object cache。

## 13. References

- Repo Core facade：`lib/symphony_elixir/repo.ex`
- Repo Core typed tools：`lib/symphony_elixir/repo/tool_executor.ex`
- Git Adapter：`lib/symphony_elixir/repo_provider/git/adapter.ex`
- GitLab read-only search：`lib/symphony_elixir/repo_provider/gitlab/code_search.ex`
- Repo Provider typed tools：`lib/symphony_elixir/repo_provider/tool_executor.ex`
- 必需能力启动门禁：`lib/symphony_elixir/config/tapd_git_codex_capabilities.ex`
- TAPD Bug AI workflow：`lib/symphony_elixir/tracker/tapd/bug_ai_workflow.ex`
- TAPD Bug AI model level：`lib/symphony_elixir/tracker/tapd/bug_ai_model_level.ex`
- TAPD typed tools：`lib/symphony_elixir/tracker/tapd/tool_executor/typed_tools.ex`
- Worker 异常收尾：`lib/symphony_elixir/orchestrator/worker_exit.ex`
- Git-only 模板：`priv/workflow_extensions/coding_pr_delivery/templates/tapd/git/codex.md`
- Git-only lifecycle：`priv/workflow_extensions/coding_pr_delivery/templates/_partials/tracker/tapd_git_only_execution_lifecycle.md`
- Repo Provider 文档：`docs/repo_provider.md`
- 运维文档：`docs/operations.md`
- 测试文档：`docs/testing.md`
