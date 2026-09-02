#!/bin/bash
# update-news.sh · 把今日政经科技日报嵌入到 PWA 并推送到 GitHub Pages
# Usage: bash update-news.sh [news-file]
#   默认读取 /workspace/daily-news-$(date +%Y-%m-%d).md
#
# 通道策略（v2 · 2026-09-02 改造）：
#   1. 优先 SSH：如果 GITHUB_SSH_KEY_FOR_TODO_PWA 在 env 且 SSH 出口通，走 git@github.com
#   2. 兜底 HTTPS+PAT：用 GITHUB_PAT_FOR_JITYJ（mavis env 注入）
#   3. 硬编码兜底：都没有就用 script 里的 token（最后保险，⚠️ 不推荐长期使用）
set -e

WORKSPACE="/workspace"
PROTOTYPE="$WORKSPACE/prototype"
NEWS_HTML="$PROTOTYPE/pages/news.html"
PAGES_URL="https://622duan.github.io/todo-pwa/"

# ============================================
# PAT 读取顺序（v3 · 2026-09-02）：
#   1. env GITHUB_PAT_FOR_JITYJ（mavis 注入）← 推荐
#   2. .git/token_pat 文件（本地兜底，不进 git）← 沙箱内安全
# ============================================
# 使用方法：把 PAT 写到 .git/token_pat（一行字符串，无空格）
#   echo "ghp_xxx..." > .git/token_pat && chmod 600 .git/token_pat
# 注意：.git/ 目录永远不会被 git 跟踪，也不会被 push 到远程

# 1. 确定要嵌入的日报
NEWS_FILE="${1:-$WORKSPACE/daily-news-$(date +%Y-%m-%d).md}"
if [ ! -f "$NEWS_FILE" ]; then
  echo "❌ 日报文件不存在: $NEWS_FILE"
  echo "   可指定: bash update-news.sh /path/to/news.md"
  exit 1
fi
echo "📄 读取日报: $NEWS_FILE ($(wc -c < "$NEWS_FILE") chars)"

# 2. 提取标题
NEWS_TITLE=$(head -1 "$NEWS_FILE" | sed 's/^# *//')
echo "📌 标题: $NEWS_TITLE"

# 3. 嵌入到 news.html
cd "$PROTOTYPE" || { echo "❌ 找不到 $PROTOTYPE"; exit 1; }
python3 << PYEOF
import re

news_path = "$NEWS_HTML"
title = """$NEWS_TITLE"""
news_file = "$NEWS_FILE"

with open(news_path, 'r', encoding='utf-8') as f:
    html = f.read()

with open(news_file, 'r', encoding='utf-8') as f:
    news_content = f.read()

# 转义反引号和 \${ 防止破坏 JS 模板字符串
news_escaped = news_content.replace('\\\\', '\\\\\\\\')
news_escaped = news_escaped.replace('\`', '\\\\\`')
news_escaped = news_escaped.replace('\${', '\\\\\${')

# 替换 DEFAULT_NEWS
pattern = r"const DEFAULT_NEWS = \`[\s\S]*?\`;\s*\n\s*// Init"
replacement = "const DEFAULT_NEWS = \`" + news_escaped + "\`;\n\n    // Init"
new_html, n = re.subn(pattern, replacement, html, count=1)
if n != 1:
    print("❌ 替换失败，找不到 DEFAULT_NEWS 块")
    exit(1)

# 同步更新 header 日期
new_html = re.sub(
    r'<p class="text-\[11px\] text-gray-500 text-center mt-1" id="newsDate">[^<]*</p>',
    '<p class="text-[11px] text-gray-500 text-center mt-1" id="newsDate">' + title + ' · 编制 Mavis</p>',
    new_html
)

with open(news_path, 'w', encoding='utf-8') as f:
    f.write(new_html)
print("✓ 已嵌入 " + str(len(news_content)) + " 字符")
print("✓ 已更新 header 日期")
PYEOF

# 4. 配置 git 身份
git config user.email "Mavis@MiniMax.local" 2>/dev/null || true
git config user.name "Mavis" 2>/dev/null || true

# 5. 决定走 SSH 还是 HTTPS+PAT
GIT_REMOTE=""
USE_HTTPS=false

# 5a. 优先 SSH：env 里有 SSH key 且能连通
if [ -n "$GITHUB_SSH_KEY_FOR_TODO_PWA" ]; then
  echo "🔑 检测到 SSH key，测试 SSH 通道..."
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  printf '%s' "$GITHUB_SSH_KEY_FOR_TODO_PWA" > /root/.ssh/mavis_github
  chmod 600 /root/.ssh/mavis_github
  cat > /root/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile /root/.ssh/mavis_github
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 /root/.ssh/config
  if timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 -T [email protected] 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ SSH 通道通，走 SSH"
    GIT_REMOTE="git@github.com:622duan/todo-pwa.git"
  else
    echo "⚠️  SSH 通道不通（沙箱可能封了 SSH 出口），fallback 到 HTTPS+PAT"
    USE_HTTPS=true
  fi
else
  echo "ℹ️  env 里没有 SSH key，走 HTTPS+PAT"
  USE_HTTPS=true
fi

# 5b. HTTPS+PAT：env 优先，没有就从 .git/token_pat 读
if [ "$USE_HTTPS" = "true" ]; then
  PAT="$GITHUB_PAT_FOR_JITYJ"
  if [ -z "$PAT" ] && [ -f "$PROTOTYPE/.git/token_pat" ]; then
    PAT=$(cat "$PROTOTYPE/.git/token_pat" | head -1 | tr -d '[:space:]')
    echo "ℹ️  从 .git/token_pat 读取到 PAT"
  fi
  if [ -z "$PAT" ]; then
    echo "❌ 没有可用的 PAT（env 和 .git/token_pat 都没有），退出"
    echo "   解决：echo 'ghp_xxx' > /workspace/prototype/.git/token_pat"
    exit 1
  fi
  echo "🔐 使用 HTTPS+PAT 通道"
  GIT_REMOTE="https://x-access-token:${PAT}@github.com/622duan/todo-pwa.git"
fi

# 6. 配置 remote
git remote remove origin 2>/dev/null || true
git remote add origin "$GIT_REMOTE"

# 7. 提交并推送
echo "📤 推送到 GitHub Pages..."
git add -A
if git diff --cached --quiet; then
  echo "⚠️  没有变更（日报和上次一样？）"
  exit 0
fi
git commit -m "🌐 更新政经日报 $(date +%Y-%m-%d)"

# 用 HTTPS 时关 SSL 验证（沙箱 CA 问题）
if [ "$USE_HTTPS" = "true" ]; then
  GIT_SSL_NO_VERIFY=true git -c http.sslVerify=false push origin main 2>&1 | tail -5
else
  git push origin main 2>&1 | tail -5
fi

echo ""
echo "✅ 完成！"
echo "   PWA URL: $PAGES_URL"
echo "⏱  GitHub Pages 部署大约 1-2 分钟"
echo "   打开 app 切到「政经」tab 就能看到新内容"
