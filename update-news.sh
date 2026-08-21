#!/bin/bash
# update-news.sh · 把今日政经科技日报嵌入到 PWA 并推送到 GitHub Pages
# Usage: bash update-news.sh [news-file]
#   默认读取 /workspace/daily-news-$(date +%Y-%m-%d).md
set -e

WORKSPACE="/workspace"
PROTOTYPE="$WORKSPACE/prototype"
NEWS_HTML="$PROTOTYPE/pages/news.html"
SSH_KEY="/workspace/.ssh/mavis_github"
SSH_CONFIG="/workspace/.ssh/config"
GIT_REMOTE="git@github.com:622duan/todo-pwa.git"
PAGES_URL="https://622duan.github.io/todo-pwa/"

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

# 4. 确保 SSH 配置
mkdir -p /root/.ssh
chmod 700 /root/.ssh
# 优先使用 workspace 里的密钥（防止 sandbox 重置丢失）
if [ -f "/workspace/.ssh/mavis_github" ]; then
  cp /workspace/.ssh/mavis_github /root/.ssh/mavis_github 2>/dev/null
  cp /workspace/.ssh/config /root/.ssh/config 2>/dev/null
  chmod 600 /root/.ssh/mavis_github /root/.ssh/config 2>/dev/null
fi
if [ ! -f "$SSH_KEY" ]; then
  echo "❌ SSH 私钥丢失: $SSH_KEY"
  echo "   需要重新生成并添加到 GitHub Deploy Keys"
  exit 1
fi
if [ ! -f "$SSH_CONFIG" ] || ! grep -q "mavis_github" "$SSH_CONFIG" 2>/dev/null; then
  cat > "$SSH_CONFIG" << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile /root/.ssh/mavis_github
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
  chmod 600 "$SSH_CONFIG"
fi

# 5. 配置 git 身份 + remote
git config user.email "Mavis@MiniMax.local" 2>/dev/null || true
git config user.name "Mavis" 2>/dev/null || true
git remote remove origin 2>/dev/null || true
git remote add origin "$GIT_REMOTE" 2>/dev/null || true
git remote set-url origin "$GIT_REMOTE"

# 6. 提交并推送
echo "📤 推送到 GitHub Pages..."
git add -A
if git diff --cached --quiet; then
  echo "⚠️  没有变更（日报和上次一样？）"
  exit 0
fi
git commit -m "🌐 更新政经日报 $(date +%Y-%m-%d)"
git push origin main 2>&1 | tail -5

echo ""
echo "✅ 完成！"
echo "   PWA URL: $PAGES_URL"
echo "⏱  GitHub Pages 部署大约 1-2 分钟"
echo "   打开 app 切到「政经」tab 就能看到新内容"
