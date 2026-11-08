#!/usr/bin/env bash
# 美颜相册 · 一键推送到 GitHub 并触发云端编译 IPA
#
# 用法：
#   bash push.sh                                  # 交互式，全部提示输入
#   bash push.sh 你的用户名 仓库名                  # 交互式补 token
#   GH_TOKEN=ghp_xxx bash push.sh 你的用户名 仓库名  # 全自动
#   bash push.sh 你的用户名 仓库名 ghp_xxx --watch   # 推完盯着编译进度
#
# 可选参数：
#   --public   仓库建成公开（默认私有）
#   --watch    推送后轮询 Actions，直到 IPA 编译完成
#
# 只需要一个 GitHub Personal Access Token：
#   https://github.com/settings/tokens  →  Generate new token (classic)
#   勾选 repo + workflow 两项，生成后复制，形如 ghp_xxxxxxxx
#   （不勾 workflow 也能推，但没法用 API 手动触发构建）

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

VISIBILITY="private"
WATCH=0
POSITIONAL=()

for arg in "$@"; do
  case "$arg" in
    --public) VISIBILITY="public" ;;
    --watch)  WATCH=1 ;;
    --*)      echo "未知参数：$arg"; exit 1 ;;
    *)        POSITIONAL+=("$arg") ;;
  esac
done

OWNER="${POSITIONAL[0]:-${GH_OWNER:-}}"
REPO="${POSITIONAL[1]:-${GH_REPO:-beauty-album}}"
TOKEN="${POSITIONAL[2]:-${GH_TOKEN:-}}"

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\n[失败] %s\n' "$*" >&2; exit 1; }

# ---------- 0. 环境检查 ----------

command -v git  >/dev/null 2>&1 || die "没有找到 git，请先安装 Git for Windows"
command -v curl >/dev/null 2>&1 || die "没有找到 curl（Git Bash 自带，请用它运行本脚本）"

[ -f project.yml ] || die "当前目录没有 project.yml，请把脚本放在 BeautyAlbum 目录下运行"

# ---------- 1. 收集参数 ----------

if [ -z "$OWNER" ]; then
  read -r -p "GitHub 用户名: " OWNER
fi
[ -n "$OWNER" ] || die "用户名不能为空"

if [ -z "$REPO" ]; then
  read -r -p "仓库名 [beauty-album]: " REPO
  REPO="${REPO:-beauty-album}"
fi

if [ -z "$TOKEN" ]; then
  printf 'GitHub Token（输入时不显示）: '
  read -r -s TOKEN
  printf '\n'
fi
[ -n "$TOKEN" ] || die "Token 不能为空"

API="https://api.github.com"
AUTH_HDR="Authorization: Bearer ${TOKEN}"

step "验证 Token"
ME_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH_HDR" -H "Accept: application/vnd.github+json" "$API/user")
if [ "$ME_CODE" != "200" ]; then
  die "Token 无效或已过期（HTTP $ME_CODE）。请到 https://github.com/settings/tokens 重新生成，勾选 repo 和 workflow"
fi
say "Token 有效，账号：$OWNER，目标仓库：$OWNER/$REPO（$VISIBILITY）"

# ---------- 2. 本地 git 仓库 ----------

step "初始化本地仓库"
if [ ! -d .git ]; then
  git init -q
  git symbolic-ref HEAD refs/heads/main
  say "已创建 .git，默认分支 main"
else
  say "已是 git 仓库，沿用现有历史"
fi

git config user.name  >/dev/null 2>&1 || git config user.name  "BeautyAlbum"
git config user.email >/dev/null 2>&1 || git config user.email "beautyalbum@local"

step "提交源码"
git add -A
if git diff --cached --quiet; then
  say "没有新的改动，跳过提交"
else
  git commit -q -m "美颜相册 iOS 源码 $(date '+%Y-%m-%d %H:%M')"
  say "已提交 $(git rev-list --count HEAD) 个版本"
fi

# ---------- 3. 远端仓库 ----------

step "检查远端仓库"
REPO_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "$AUTH_HDR" "$API/repos/$OWNER/$REPO")
if [ "$REPO_CODE" = "200" ]; then
  say "仓库已存在，直接推送"
elif [ "$REPO_CODE" = "404" ]; then
  say "仓库不存在，正在创建…"
  PRIVATE_FLAG="true"
  [ "$VISIBILITY" = "public" ] && PRIVATE_FLAG="false"
  CREATE_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "$AUTH_HDR" -H "Accept: application/vnd.github+json" \
    "$API/user/repos" \
    -d "{\"name\":\"$REPO\",\"private\":$PRIVATE_FLAG,\"auto_init\":false,\"description\":\"美颜相册 - 美容院客户相册与档案管理\"}")
  case "$CREATE_CODE" in
    201) say "仓库创建成功" ;;
    422) say "仓库名已被占用但当前账号无权访问，改用其他名字重试" ; die "请换一个仓库名" ;;
    *)   die "创建仓库失败（HTTP $CREATE_CODE）" ;;
  esac
else
  die "查询仓库失败（HTTP $REPO_CODE）"
fi

# ---------- 4. 推送 ----------

step "推送到 GitHub"
git remote remove origin 2>/dev/null || true
git remote add origin "https://${OWNER}:${TOKEN}@github.com/${OWNER}/${REPO}.git"

if ! PUSH_LOG=$(git push -u origin main 2>&1); then
  printf '%s\n' "$PUSH_LOG" | tail -6
  say "直接推送失败，尝试合并远端已有历史…"
  git fetch origin main >/dev/null 2>&1 || true
  if git merge --allow-unrelated-histories --no-edit origin/main >/dev/null 2>&1; then
    if ! PUSH_LOG2=$(git push -u origin main 2>&1); then
      printf '%s\n' "$PUSH_LOG2" | tail -6
      die "推送失败。检查 Token 是否勾选 repo，以及仓库是否开了分支保护"
    fi
  else
    die "远端 main 有冲突内容，无法自动合并。请手动处理后重跑本脚本"
  fi
fi

# 把 Token 从 git 配置里抹掉，避免明文留在 .git/config
git remote set-url origin "https://github.com/${OWNER}/${REPO}.git"
say "推送完成，已从 .git/config 移除 Token"

# ---------- 5. 触发构建 ----------

step "触发云端编译"
DISPATCH_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "$AUTH_HDR" -H "Accept: application/vnd.github+json" \
  "$API/repos/$OWNER/$REPO/actions/workflows/build.yml/dispatches" \
  -d '{"ref":"main"}')

case "$DISPATCH_CODE" in
  204) say "已手动触发构建（push 通常也会自动触发，重复触发会自动排队）" ;;
  403) say "Token 缺少 workflow 权限，跳过手动触发；push 已自动触发构建" ;;
  404) say "找不到 workflow 文件，push 已自动触发构建" ;;
  *)   say "手动触发返回 HTTP $DISPATCH_CODE，push 已自动触发构建" ;;
esac

# ---------- 6. 盯进度（可选）----------

if [ "$WATCH" = "1" ]; then
  step "等待编译完成（每 15 秒查一次，最长 20 分钟）"
  i=0
  while [ "$i" -lt 80 ]; do
    sleep 15
    i=$((i + 1))
    RUN_JSON=$(curl -s -H "$AUTH_HDR" "$API/repos/$OWNER/$REPO/actions/runs?branch=main&per_page=1")
    STATUS=$(printf '%s' "$RUN_JSON" | grep -o '"status": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    CONCLUSION=$(printf '%s' "$RUN_JSON" | grep -o '"conclusion": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    say "[$((i * 15))s] 状态：${STATUS:-未知}${CONCLUSION:+ / 结果：$CONCLUSION}"
    if [ "$STATUS" = "completed" ]; then
      if [ "$CONCLUSION" = "success" ]; then
        say "编译成功，IPA 已挂到 Release"
      else
        say "编译失败，去日志看具体报错：https://github.com/$OWNER/$REPO/actions"
      fi
      break
    fi
  done
fi

# ---------- 7. 收尾 ----------

cat <<EOF

============================================================
完成。

仓库：      https://github.com/$OWNER/$REPO
构建进度：  https://github.com/$OWNER/$REPO/actions
IPA 下载：  https://github.com/$OWNER/$REPO/releases

构建成功后，Release 里会有一个 BeautyAlbum.ipa：
  - 电脑用 Sideloadly 导入手机（需要 Apple ID，免费账号 7 天有效期）
  - 或 AltStore / SideStore 自签安装
  - 有开发者证书的可以直接重签，有效期 1 年
  - TrollStore 支持的系统可直接装，不掉签

首次构建约 6-10 分钟，之后改代码再跑本脚本就是增量构建。

额度说明（GitHub 官方计费）：
  - 公开仓库 + 标准 macOS runner：完全免费，不限次数
  - 私有仓库：每月 $12 额度，macOS 按 $0.062/分钟算，约 190 分钟/月，够跑 20 次左右
  - 想无限免费就跑：bash push.sh 用户名 仓库名 --public
============================================================
EOF
