#!/usr/bin/env bash
# 一键发布：构建自检 → 提交 → 同时推到 GitHub 和内网 GitLab
# 用法: ./scripts/release.sh "feat: 你的改动说明"
set -euo pipefail

MSG="${1:-}"
if [[ -z "$MSG" ]]; then
  echo "用法: ./scripts/release.sh \"提交说明\""
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> 1/4 构建自检（编译不过就不发布）"
./scripts/build.sh >/dev/null
echo "    编译通过"

echo "==> 2/4 提交"
git add -A
if git diff --cached --quiet; then
  echo "    没有改动，跳过提交"
else
  git -c commit.gpgsign=false commit -q -m "$MSG"
  echo "    已提交: $MSG"
fi

echo "==> 3/4 推 GitHub"
git push -q github main && echo "    ok"

echo "==> 4/4 推内网 GitLab"
git push -q origin main && echo "    ok"

echo
echo "完成。当前 HEAD: $(git log --oneline -1)"
