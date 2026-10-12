#!/bin/bash
# 一键把 Kazumi 装到 Sony Google TV 并验证电视支持是否真的生效。
#
# 用法:
#   ./install_to_tv.sh              # 自动寻找下载好的 APK
#   ./install_to_tv.sh 路径/xxx.apk # 指定 APK
#
# 前提：电视上已按 TV_SUPPORT.md 第三节打开开发者选项 + USB调试(或无线调试)。

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB="$HERE/tools/platform-tools/adb"
PKG="com.predidit.kazumi"
ACT="$PKG/com.example.kazumi.MainActivity"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[34m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ -x "$ADB" ] || { red "找不到 adb：$ADB"; exit 1; }
"$ADB" start-server >/dev/null 2>&1

# ---------- 1. 找 APK ----------
if [ $# -ge 1 ]; then
  APK="$1"
else
  APK="$(find "$HOME/Downloads" "$HERE" -maxdepth 3 -name '*tv*.apk' -o -maxdepth 3 -name 'app-release.apk' 2>/dev/null | head -1)"
fi
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  red "没找到 APK。"
  echo "请把 GitHub Actions 下载的 Kazumi-tv-arm64.apk 放进 ~/Downloads，然后重跑；"
  echo "或者直接指定路径： ./install_to_tv.sh ~/Downloads/Kazumi-tv-arm64.apk"
  exit 1
fi
blue "APK: $APK"

# ---------- 2. 连电视 ----------
if ! "$ADB" devices | grep -qE 'device$'; then
  yellow "没检测到电视。请先在电视上：设置 → 设备偏好设置 → 关于 → 连点版本 7 次 → 开发者选项 → 开 USB调试"
  echo "插好数据线后，电视上会弹「允许 USB 调试吗？」→ 用遥控器选【允许】。"
  echo
  echo "如果你更想用无线（不用插线），把电视 IP 告诉我，或自己执行："
  echo "    $ADB pair <电视IP>:<配对端口>    # 配对端口在 开发者选项 → 无线调试 里看"
  echo "    $ADB connect <电视IP>:5555"
  exit 1
fi
green "✓ 已连接电视"

# ---------- 3. 安装 ----------
echo "正在安装（第一次可能要 1-2 分钟，APK 比较大）..."
if ! "$ADB" install -r "$APK"; then
  red "安装失败。"
  echo "如果提示 INSTALL_FAILED_UPDATE_INCOMPATIBLE，先卸载再装： $ADB uninstall $PKG"
  exit 1
fi
green "✓ 安装完成"

# ---------- 4. 验证电视支持真的生效 ----------
# 这一步是整个脚本的重点：装得上不代表电视认，光看「安装成功」会漏掉
# LEANBACK 没打进去的情况，那样主屏依然找不到图标。
HAS_LEANBACK="$("$ADB" shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER \
  "$PKG" 2>/dev/null | tr -d '\r' | tail -1)"

if echo "$HAS_LEANBACK" | grep -q "MainActivity"; then
  green "✓ 电视启动器入口已注册（主屏应用列表里应该能看到 Kazumi）"
else
  red "✗ 没检测到 LEANBACK_LAUNCHER —— 主屏会找不到这个应用。"
  echo "  这个 APK 可能不是带电视支持构建的。请确认是跑 Build TV APK 得到的产物。"
fi

if "$ADB" shell pm list features 2>/dev/null | grep -q "android.software.leanback"; then
  green "✓ 电视确实声明了 leanback（文字放大等 TV 适配会生效）"
else
  yellow "! 这台设备没声明 leanback，DTV 适配不会启用（但应用仍可运行）"
fi

# ---------- 5. 启动 ----------
echo
echo "正在启动…"
"$ADB" shell am start -n "$ACT" >/dev/null 2>&1
sleep 2
if "$ADB" shell pidof "$PKG" >/dev/null 2>&1; then
  green "✓ 进程已运行。去电视上看看，遥控器方向键应该能移动焦点"
else
  yellow "没检测到进程。去电视【应用 → 全部应用 → Kazumi】手动点开试试。"
fi

echo
blue "排查用命令："
echo "  $ADB logcat -s flutter:* | grep -i 'Tv:'   # 看 TV 环境探测日志"
echo "  $ADB shell dumpsys activity activities | grep -i kazumi"