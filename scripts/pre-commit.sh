#!/bin/sh
# mcd-deal-radar 文档健康检查
# 背景：本项目的 SKILL.md 曾多次被 Markdown 格式化工具破坏——
#   1) frontmatter 的 --- 被转义成 \---（导致 skill 无法被识别）
#   2) 大量行尾双空格被注入
# 本脚本在提交前拦截这些问题，防止坏文件进入仓库。

set -e
ERRORS=0

# 只检查被暂存的 Markdown 文件
STAGED_MD=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)

if [ -z "$STAGED_MD" ]; then
    exit 0
fi

for f in $STAGED_MD; do
    # 跳过已删除的文件
    [ -f "$f" ] || continue

    # 检查 1：\--- 转义（frontmatter 杀手）
    if grep -q '\\---' "$f" 2>/dev/null; then
        echo "❌ [$f] 发现 \\--- 转义（会破坏 Markdown 分隔线/frontmatter）："
        grep -n '\\---' "$f" | head -5
        ERRORS=1
    fi

    # 检查 2：行尾双空格（格式化工具注入的痕迹）
    TRAILING=$(grep -c ' $' "$f" 2>/dev/null || true)
    TRAILING=${TRAILING:-0}
    if [ "$TRAILING" -gt 0 ]; then
        echo "❌ [$f] 发现 $TRAILING 处行尾双空格（疑似被格式化工具污染）："
        grep -n ' $' "$f" | head -5
        ERRORS=1
    fi

    # 检查 3：转义的星号 \*（加粗被破坏）
    if grep -q '\\\*' "$f" 2>/dev/null; then
        echo "❌ [$f] 发现 \\* 转义（会破坏 Markdown 加粗）："
        grep -n '\\\*' "$f" | head -5
        ERRORS=1
    fi
done

# SKILL.md 专项检查：frontmatter 必须以 --- 开头且 YAML 可解析
SKILL="skills/mcd-deal-radar/SKILL.md"
if git diff --cached --name-only | grep -q "^$SKILL$" && [ -f "$SKILL" ]; then
    if ! head -1 "$SKILL" | grep -q '^---$'; then
        echo "❌ [$SKILL] 第一行必须是 ---（frontmatter 起始符）"
        ERRORS=1
    fi
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # 无 pyyaml 时跳过
s = open('$SKILL', encoding='utf-8').read()
parts = s.split('---')
assert len(parts) >= 3, 'frontmatter 不完整'
d = yaml.safe_load(parts[1])
assert d and d.get('name') and d.get('description'), 'name/description 缺失'
" 2>/dev/null; then
            echo "❌ [$SKILL] frontmatter YAML 解析失败或 name/description 缺失"
            ERRORS=1
        fi
    fi
fi

if [ "$ERRORS" -ne 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " 提交被拦截：文档格式存在问题（见上方 ❌）"
    echo " 修复方法：撤销本次改动并从上一次干净提交恢复："
    echo "   git checkout -- <文件>"
    echo " 然后重新应用改动（避免触发编辑器自动格式化）。"
    echo " 强行提交（不推荐）：git commit --no-verify"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

echo "✅ 文档健康检查通过"
