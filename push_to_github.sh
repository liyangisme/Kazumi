#!/bin/bash
# 把电视适配的改动推到你的 fork，然后告诉你下一步点哪里。
#
#   ./push_to_github.sh
#
# 第一次运行会要求输入 GitHub 用户名和密码：
#   Username: 你的 GitHub 用户名
#   Password: **粘贴 Personal Access Token，不是登录密码**
#   （GitHub 从 2021 年起不接受账号密码做 git 推送）

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1

FORK="https://github.com/liyangisme/Kazumi.git"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
blue() { printf '\033[34m%s\033[0m\n' "$*"; }

FORCE_DIRECT=0
[ "${1:-}" = "--direct" ] && FORCE_DIRECT=1

# 探测可用链路。git 全局配置的代理端口经常和实际监听的端口对不上
# （比如配 7890、代理软件实际跑 7897），所以这里逐个试，不硬编码。
pick_route() {
  if [ "$FORCE_DIRECT" = 1 ]; then
    echo "user 指定直连"; return
  fi
  # 全局配的代理优先，但必须真的在监听。
  # 只输出 host:port —— 往返回值里掺 "global" 之类的标记会让 case 匹配不到，
  # 掉进兜底分支拼出垃圾地址，踩过。
  local cfg host port
  cfg="$(git config --global --get http.proxy 2>/dev/null | sed -E 's#^[a-zA-Z]+://##; s#/.*$##')"
  host="${cfg%:*}"; port="${cfg##*:}"
  # nc 要 host 和 port 分开传，"host:port" 会被当成整个主机名
  if [ -n "$cfg" ] && nc -z -G 2 "$host" "$port" 2>/dev/null; then
    echo "$cfg"; return
  fi
  [ -n "$cfg" ] && echo "（全局代理 $cfg 没在监听，改用自动探测）" >&2
  # Clash / v2rayN / Surge 常见端口
  for p in 7897 7890 7891 1080 1087 8888 10809 10808 6152 20171; do
    nc -z 127.0.0.1 "$p" 2>/dev/null && { echo "127.0.0.1:$p"; return; }
  done
  echo "direct"
}

ROUTE="$(pick_route)"
# 用字符串而不是数组：macOS 自带 bash 3.2，在 `set -u` 下展开空数组会直接
# 报 unbound variable 把脚本打断。代理参数里没有空格，词分割是安全的。
case "$ROUTE" in
  direct)  blue "走直连（没找到可用代理）"
            PROXY="-c http.proxy= -c https.proxy=" ;;
  *)       blue "走代理 $ROUTE"
            PROXY="-c http.proxy=http://$ROUTE -c https.proxy=http://$ROUTE" ;;
esac

# 先探一下链路，别等 push 挂掉才发现走不通
if ! git $PROXY ls-remote --heads fork main >/dev/null 2>&1; then
  red "连不上你的 fork。"
  echo "  试试： ./push_to_github.sh --direct        # 绕过代理直连"
  echo "  或确认代理软件已启动、且全局端口配置正确："
  echo "        git config --global --get http.proxy"
  exit 1
fi
green "✓ 链路通了"

git remote set-url fork "$FORK" 2>/dev/null

if git rev-parse fork/main >/dev/null 2>&1; then
  if ! git merge-base --is-ancestor fork/main HEAD; then
    red "远端有你本地没有的新提交。先同步再推："
    echo "    $0 --sync"
    exit 1
  fi
  green "✓ 确认是 fast-forward，不会覆盖你 fork 里的任何东西"
fi

echo
blue "开始推送…"
PUSH_ERR="$(git $PROXY push fork main:main 2>&1)"
if [ $? -ne 0 ]; then
  # PAT 缺 workflow scope 时 GitHub 会直接拒掉整个 push。这条最容易撞上，
  # 因为改 workflow 文件属于敏感操作，token 默认就是没权限的。
  if echo "$PUSH_ERR" | grep -q "without \`workflow\` scope"; then
    red "推送被拒：你的 Token 没有 workflow 权限。"
    echo
    echo "改动里包含 .github/workflows/build-tv-apk.yaml，GitHub 要求"
    echo "专门授权才能推这类文件。两个办法，选一个："
    echo
    echo "  办法 A（改 Token，1 分钟）"
    echo "    https://github.com/settings/tokens → Generate new token (classic)"
    echo "    勾选  repo  和  workflow  → 生成后立刻复制"
    echo "    然后重跑本脚本，在 Password 位置粘贴新 Token"
    echo
    echo "  办法 B（不动 Token，在网页上建这个文件）"
    echo "    https://github.com/liyangisme/Kazumi/new/main"
    echo "    文件名填  .github/workflows/build-tv-apk.yaml"
    echo "    内容粘贴下面这段，再 Commit changes："
    echo
    sed 's/^/      /' .github/workflows/build-tv-apk.yaml
    echo
    echo "  办法 B 完成后，其余文件就可以正常推了，重跑本脚本即可。"
    echo "$PUSH_ERR" | tail -2
    exit 1
  fi

  red "推送失败。"
  echo "$PUSH_ERR" | tail -3
  echo
  echo "最常见两个原因："
  echo "  1) 密码位置填了 GitHub 登录密码 → 必须是 Personal Access Token"
  echo "     生成：https://github.com/settings/tokens → Generate new token (classic)"
  echo "     勾选 repo 权限 → 生成后立刻复制（只显示一次）"
  echo "  2) 网络不通 → 打开你的代理软件再重跑一次本脚本"
  exit 1
fi

green "✓ 推送成功"
echo
blue "接下来："
echo "  1. 打开  https://github.com/liyangisme/Kazumi/actions"
echo "  2. 左侧选  Build TV APK"
echo "  3. 右侧点  Run workflow  → 确认"
echo "  4. 等 10~20 分钟，跑完后在页面最下方 Artifacts 下载 kazumi-tv-apk"
echo "  5. 解压得到 Kazumi-tv-arm64.apk，放到 ~/Downloads"
echo "  6. 回到这台电脑执行： ./install_to_tv.sh"