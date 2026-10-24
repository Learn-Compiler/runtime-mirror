# runtime-mirror

[`https://gitcode.com/cann/runtime.git`](https://gitcode.com/cann/runtime.git) 的自动镜像仓库。
由 GitHub Actions 每 12 小时同步一次，**不需要任何 PAT 或 secret**。

## 仓库结构（单仓库方案）

```
main              ← 本 README + .github/workflows/sync-runtime.yml   ← 默认分支，受保护
master            ┐
9.1.0             │
9.2.0             ├─ 上游镜像内容：18 个分支
ci                │   （含 refactor/... 这类带斜杠的分支）
refactor/...      ┘
v9.2.0            ┐
v9.1.1            ├─ 上游镜像内容：18 个 tag
...               ┘
```

**代码在 `master` 等分支，不在 `main`。** 打开仓库看到的 `main` 只是配置分支。

为什么这么拆：GitHub 的 `schedule` 触发器**只在默认分支的 workflow 文件上生效**，
而镜像会写满 `master`/`9.x`/所有 tag。所以固定用 `main` 当配置分支，镜像永远不碰它 ——
推送的 refspec 只取上游存在的 ref（上游没有 `main`），清理残留 ref 时也显式跳过 `main`。

## 用法

```bash
# 拿最新代码
git clone --branch master https://github.com/Learn-Compiler/runtime-mirror.git

# 拿某个版本
git clone --branch v9.2.0 https://github.com/Learn-Compiler/runtime-mirror.git
git clone --branch 9.0.0-test https://github.com/Learn-Compiler/runtime-mirror.git

# 看上游领先多少
cd runtime-mirror
git remote add upstream https://gitcode.com/cann/runtime.git
git fetch upstream && git log --oneline HEAD..upstream/master | head
```

## 同步机制

| 项 | 值 |
|---|---|
| 频率 | 每 12 小时（UTC `17 */12 * * *`，即北京时间 08:17 / 20:17） |
| 触发 | `schedule` + 推送到 `main` + 手动 `workflow_dispatch` |
| 凭据 | 仓库自带的 `GITHUB_TOKEN`（`contents: write`），无需配置 |
| 体积 | 约 55 MB（18 分支 + 18 tag） |
| 增量 | 先比对两边 ref，一致就跳过克隆，不重复下载 |
| 重试 | 抓取失败自动重试 3 次（GitCode 偶发 TLS 断连） |

手动同步：Actions → **Sync runtime from GitCode** → Run workflow。

## 几个关键实现细节

**不用 `git clone --mirror`**：GitCode 会广播大量 `refs/tmp/*` 临时 ref（网页端操作残留），
`clone --mirror` 会把它们连同垃圾对象一起抓下来（在 pypto 上实测：58 MB 膨胀到 422 MB）；
而推回 GitHub 时，GitHub 只接受 `refs/heads/*` 和 `refs/tags/*`，遇到 `refs/tmp/*` 会直接报错拒绝整个 push。
所以用 `git init --bare` + 显式 refspec，只跟踪 heads 和 tags。

**不用 `push --mirror`**：那会删掉镜像端所有上游没有的 ref —— 包括 `main`，workflow 跟着消失，
定时任务就死了。改成「显式 refspec 推送 + 逐个删除残留 ref 时跳过 `main`」。

**上游若新增 `main` 分支**：会和本仓库的配置分支冲突。workflow 里有断言，遇到这种情况会
直接失败并报错，需要人工决策（把配置分支改名，或调整 `PROTECTED_BRANCH`）。

## 注意事项

**许可证**：runtime 属于 CANN 开源项目，使用 **CANN Open Software License Agreement Version 2.0**
（不是 Apache/MIT 这类标准开源协议）。3.3 条款允许分发，但要求「向接收方提供协议副本、保留所有声明」——
`LICENSE` 随镜像保留，满足要求；2.1 条款把使用范围限定在华为 AI 处理器生态内。建议在仓库 About 写清
「上游镜像，版权归华为，许可见 LICENSE」。

**别手动改镜像分支**：`master`、`9.x` 等分支每 12 小时会被上游内容强制覆盖，你在上面提的 commit 会丢。
要加说明就改 `main` 上的 README。

**Actions 60 天自动停用**：GitHub 会在仓库连续 60 天无活动后停用定时 workflow。本仓库每 12 小时
都在推分支，不会触发；如果哪天停了，去 Actions 页面点一下 Enable 即可。

## 兜底：改在本机跑

runner 在美国，拉 GitCode 偶尔会超时（本机实测 runtime 首次抓取要 4~5 分钟）。走 SSH，同样不需要 PAT：

```bash
./scripts/sync-local.sh

# 装成每 12 小时自动跑的 systemd timer
mkdir -p ~/.local/bin ~/.config/systemd/user
cp scripts/sync-local.sh ~/.local/bin/runtime-mirror-sync
chmod +x ~/.local/bin/runtime-mirror-sync
cp scripts/runtime-mirror.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now runtime-mirror.timer

systemctl --user list-timers runtime-mirror.timer
journalctl --user -u runtime-mirror.service -n 30 --no-pager
```

本机脚本和 workflow 行为一致：只推 heads/tags、清理残留时跳过 `main`，没更新时秒级跑完。
两边可以同时开着，不会冲突。
