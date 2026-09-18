#!/usr/bin/env bash
#
# 把本仓库发布到你自己的 GitHub 仓库。
#
# 用法：
#   bash scripts/publish.sh https://github.com/<你的用户名>/MoveMentor.git
#
# 想自定义提交身份（默认从仓库地址推断用户名）：
#   GIT_NAME="Your Name" GIT_EMAIL="you@example.com" bash scripts/publish.sh <地址>
#
# 这个脚本会做四件事：
#   1. 校正本仓库的提交身份（当前是占位的 MoveMentor <movementor@users.noreply.github.com>）
#   2. 把已有提交的作者一起改成新身份，否则 GitHub 不会把提交算到你名下
#   3. 添加或更新 origin
#   4. 推送并打印验证结果
#
# 它**不会**做破坏性操作：不用 --force，不改写已经推到远程的历史。
# 如果远程仓库不是空的，脚本会停下来说明怎么处理，而不是硬覆盖。

set -euo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "用法: bash scripts/publish.sh <仓库地址>" >&2
  echo "例如: bash scripts/publish.sh https://github.com/yourname/MoveMentor.git" >&2
  exit 1
fi

# ---- 解析 owner / repo -------------------------------------------------------

clean="${url%.git}"
clean="${clean%/}"

case "$clean" in
  *github.com[:/]*)
    rest="${clean#*github.com}"
    rest="${rest#:}"
    rest="${rest#/}"
    owner="${rest%%/*}"
    repo="${rest#*/}"
    ;;
  *)
    echo "无法识别的仓库地址：$url" >&2
    echo "请使用形如 https://github.com/<用户名>/<仓库名>.git 的地址。" >&2
    exit 1
    ;;
esac

if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$repo" ]; then
  echo "无法从地址里解析出用户名和仓库名：$url" >&2
  exit 1
fi

name="${GIT_NAME:-$owner}"
email="${GIT_EMAIL:-$owner@users.noreply.github.com}"

echo "== MoveMentor 发布到 GitHub =="
echo "  仓库：$owner/$repo"
echo "  提交身份：$name <$email>"
echo ""

# 必须在仓库根目录
if [ ! -d .git ]; then
  echo "当前目录不是 Git 仓库。请先 cd 到 MoveMentor 目录再运行。" >&2
  exit 1
fi

# ---- 1. 校正身份 -------------------------------------------------------------

git config user.name "$name"
git config user.email "$email"
echo "[1/4] 已写入本仓库的提交身份"

# ---- 2. 改写历史作者 ---------------------------------------------------------

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "[2/4] 本仓库还没有任何提交，跳过作者改写"
else
  snapshot="$(mktemp)"
  trap 'rm -f "$snapshot"' EXIT
  git log --format='%an <%ae>' > "$snapshot"

  if grep -qvF "$name <$email>" "$snapshot"; then
    total="$(git rev-list --count HEAD)"
    echo "[2/4] 有提交的作者不是上面这个身份，开始改写 $total 个提交的作者…"
    echo "      （中途想放弃：git rebase --abort）"
    # --allow-empty 是必要的：历史里若存在空提交，不带它 amend 会失败而中断整个 rebase。
    git rebase --root --exec "git commit --amend --reset-author --allow-empty --no-edit"
    echo "      改写完成"
  else
    echo "[2/4] 所有提交的作者已经正确，无需改写"
  fi

  rm -f "$snapshot"
  trap - EXIT
fi

# 工作区必须干净才继续
if [ -n "$(git status --porcelain)" ]; then
  echo "" >&2
  echo "工作区还有未提交的改动，先处理掉再推送：" >&2
  git status --short >&2
  exit 1
fi

# ---- 3. 配置 origin ----------------------------------------------------------

if git remote get-url origin >/dev/null 2>&1; then
  current="$(git remote get-url origin)"
  if [ "$current" != "$url" ]; then
    git remote set-url origin "$url"
    echo "[3/4] origin 原指向 $current，已更新为 $url"
  else
    echo "[3/4] origin 已正确指向 $url"
  fi
else
  git remote add origin "$url"
  echo "[3/4] 已添加 origin → $url"
fi

# 提前提醒远程非空的情况，避免推送到一半才报错
if git ls-remote --heads origin main 2>/dev/null | grep -q .; then
  echo ""
  echo "⚠ 远程 main 分支上已经有提交了（建仓时可能勾了 README / License / .gitignore）。"
  echo "  直接推送会被拒绝。推荐做法：删掉远程仓库，重新建一个空的，再运行本脚本。"
  echo "  想保留远程那个提交的话，先执行：git pull --rebase origin main"
  echo ""
  read -r -p "  仍然继续尝试推送？[y/N] " answer
  case "$answer" in
    [yY]*) ;;
    *) echo "  已中止。"; exit 1 ;;
  esac
fi

# ---- 4. 推送 ----------------------------------------------------------------

echo "[4/4] 推送中…（Windows 会弹出浏览器让你登录 GitHub，授权一次即可）"
echo ""

if ! git push -u origin main; then
  echo "" >&2
  echo "推送失败。对照下面几种情况处理：" >&2
  echo "  · ! [rejected] ... (fetch first)  → 远程非空：git pull --rebase origin main 后重试" >&2
  echo "  · 认证失败 / 反复弹窗            → 清掉旧凭据：git credential-manager erase <<< \$'protocol=https\\nhost=github.com\\n'" >&2
  echo "  · 卡住不动                       → 大概率网络不通，见 docs/07-发布到GitHub.md 末节" >&2
  exit 1
fi

echo ""
echo "== 完成 =="
git remote -v
echo ""
echo "提交数：$(git rev-list --count HEAD)"
git log --format='  %h  %an <%ae>  %s' | head -3
echo ""
echo "打开 https://github.com/$owner/$repo 确认页面已就绪。"
echo "别忘了：仓库要设为 Public（参赛要求「仓库公开」是硬指标）。"
