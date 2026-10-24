#!/usr/bin/env bash
# 把 gitcode.com/cann/runtime.git 镜像到 GitHub 的 runtime-mirror 仓库（本机兜底方案）
# 走 SSH，不需要 PAT；只推 master/9.x/tag 等镜像 ref，绝不动 main（main 装着 workflow）。
#
# 用法: ./sync-local.sh
# 环境变量:
#   RUNTIME_UPSTREAM     上游地址，默认 https://gitcode.com/cann/runtime.git
#   RUNTIME_MIRROR_REPO  目标地址，默认 git@github.com:Learn-Compiler/runtime-mirror.git
#   RUNTIME_MIRROR_WORK  持久缓存目录，默认 ~/.cache/runtime-mirror

set -euo pipefail

UPSTREAM="${RUNTIME_UPSTREAM:-https://gitcode.com/cann/runtime.git}"
MIRROR="${RUNTIME_MIRROR_REPO:-git@github.com:Learn-Compiler/runtime-mirror.git}"
WORK="${RUNTIME_MIRROR_WORK:-$HOME/.cache/runtime-mirror}"
BARE="$WORK/upstream.git"
PROTECTED="${RUNTIME_PROTECTED_BRANCH:-main}"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

mkdir -p "$WORK"

# 防止两次运行重叠（手动跑的时候定时器也触发了）
exec 9>"$WORK/.sync.lock"
if ! flock -n 9; then
  log "上一次同步还在进行，跳过本次。"
  exit 0
fi

git config --global http.postBuffer 524288000 2>/dev/null || true
git config --global http.lowSpeedLimit 100 2>/dev/null || true
git config --global http.lowSpeedTime 300 2>/dev/null || true
git config --global http.version HTTP/1.1 2>/dev/null || true

if [ ! -d "$BARE" ]; then
  log "首次运行，初始化本地裸仓库…"
  git init --bare -q "$BARE"
fi

# 只跟踪 refs/heads/* 和 refs/tags/*。
# 绝不能用 clone --mirror：GitCode 会广播 8168 个 refs/tmp/* 临时 ref，
# 全抓下来会让 58MB 膨胀到 422MB，且推回 GitHub 会被拒。
git -C "$BARE" remote get-url origin >/dev/null 2>&1 || git -C "$BARE" remote add origin "$UPSTREAM"
git -C "$BARE" remote set-url origin "$UPSTREAM"
git -C "$BARE" config --unset-all remote.origin.fetch 2>/dev/null || true
git -C "$BARE" config remote.origin.fetch '+refs/heads/*:refs/heads/*'
git -C "$BARE" config --add remote.origin.fetch '+refs/tags/*:refs/tags/*'

# 清理历史遗留的非法 ref（比如之前用 --mirror 克隆过留下的 refs/tmp/*）
stray=$(git -C "$BARE" for-each-ref --format='%(refname)' | grep -v -E '^refs/(heads|tags)/' || true)
if [ -n "$stray" ]; then
  log "清理 $(printf '%s\n' "$stray" | wc -l) 个遗留的非 heads/tags ref…"
  printf '%s\n' "$stray" | sed 's/^/delete /' | git -C "$BARE" update-ref --stdin
fi

log "增量抓取上游 ref（--prune 同步上游已删除的分支和 tag）…"
fetch_ok=0
for attempt in 1 2 3; do
  if git -C "$BARE" fetch --prune --no-tags origin; then
    fetch_ok=1
    break
  fi
  log "第 $attempt 次抓取失败（多为链路抖动/TLS 断连），15 秒后重试…"
  sleep 15
done
if [ "$fetch_ok" -ne 1 ]; then
  log "连续 3 次抓取失败，放弃本次，等下一个周期。"
  exit 1
fi

# 上游若出现 main，会和本仓库的 workflow 分支冲突，必须人工处理
if git -C "$BARE" show-ref --verify --quiet "refs/heads/$PROTECTED"; then
  log "错误：上游出现了 $PROTECTED 分支，会覆盖镜像仓库的 workflow。中止。"
  exit 1
fi

log "推送镜像 ref 到 $MIRROR（不碰 $PROTECTED）…"
git -C "$BARE" push --force "$MIRROR" \
  'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'

# 清理上游已删除的 ref，跳过受保护分支
remote_refs=$(git -C "$BARE" ls-remote --refs --heads --tags "$MIRROR" | awk '{print $2}')
local_refs=$(git -C "$BARE" for-each-ref --format='%(refname)')
removed=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  [ "$ref" = "refs/heads/$PROTECTED" ] && continue
  if ! printf '%s\n' "$local_refs" | grep -qxF "$ref"; then
    if git -C "$BARE" push --quiet "$MIRROR" ":${ref}"; then
      log "  删除上游已不存在的 ref: $ref"
      removed=$((removed + 1))
    fi
  fi
done <<< "$remote_refs"
log "共清理 $removed 个残留 ref"

log "完成。"
git -C "$BARE" for-each-ref --format='%(refname)' | sed 's#refs/##' | awk -F/ '{print "  " $1}' | sort | uniq -c
log "本地缓存体积: $(du -sh "$BARE" | cut -f1)"
