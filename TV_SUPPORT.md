# 在 Sony BRAVIA XR-65A95K（Google TV）上运行 Kazumi

A95K 是 Google TV 设备，本质上就是一台 Android 电视。Flutter 应用跑在上面没问题，
真正卡住的只有**启动器可见性**这一个点。下面是本次改动、构建方式和安装步骤。

---

## 一、改了什么

| # | 文件 | 改动 | 作用 |
|---|------|------|------|
| 1 | `android/app/src/main/AndroidManifest.xml` | 新增独立 `LEANBACK_LAUNCHER` intent-filter | **核心修复**。Google 官方规定：没有这个 category 的应用不会出现在电视主屏应用列表里 |
| 2 | 同上 | `android:banner="@drawable/tv_banner"` | 主屏应用行里显示的横幅图 |
| 3 | 同上 | `uses-feature android.software.leanback required=false` | 声明支持电视；不加会被商店/启动器的 TV 过滤器筛掉 |
| 4 | 同上 | `uses-feature android.hardware.touchscreen required=false` | Android 默认会推断「必须有触摸屏」，电视没有，会导致不兼容判定 |
| 5 | `android/.../MainActivity.kt` | intent channel 新增 `isLeanback` | 让 Dart 侧知道自己在电视上 |
| 6 | `lib/tv/tv_support.dart` | 新增 | 遥控器 OK 键映射 + 十英尺文字放大 |
| 7 | `lib/main.dart` / `lib/app_widget.dart` | 接线 | 启动时探测 TV 环境并注入 |
| 8 | `.github/workflows/build-tv-apk.yaml` | 新增 | 一键云构建 arm64 APK |

`LAUNCHER` 那个 filter 原样保留，所以**手机和平板侧行为完全没变**，
把 `leanback` 相关行删掉就等于回滚。

### 为什么遥控器方向键能直接用

Flutter 的焦点系统本身就支持方向键在 Material 组件之间移动，而这个项目的
卡片是 `Card > InkWell`、`导航` 是 `NavigationRail`——全是原生可聚焦组件，
**不需要重写 UI**。真正缺的只有两点，已在 `lib/tv/tv_support.dart` 补上：

- **OK 键**：不同遥控器分别上报 `enter` / `select` / `numpadEnter` / `space`。
  全部映射到 `ButtonActivateIntent`，由框架转成 `ActivateIntent` 发给当前聚焦控件。
  （注意：直接映射 `ActivateIntent` 会递归，这是实现时容易踩的坑。）
- **文字太小**：65 寸屏在客厅距离看，手机尺寸的字读不清。TV 下统一 ×1.3，
  并把 `focusColor` 提到 32% 白色——否则焦点高亮在沙发上根本看不见。

---

## 二、怎么构建 APK

本机没有 Flutter / Android SDK / JDK，所以推荐**云构建**。

### 方式 A：GitHub Actions（推荐，无需装任何东西）

1. 在 GitHub 上 fork 这个仓库到自己账号下（需要 push 权限才能跑 workflow）。
2. 打开 Actions 标签页 → 左侧选 **Build TV APK** → 右侧 **Run workflow**。
3. 等待约 10–20 分钟（首次要拉 Flutter SDK，更慢）。
4. 构建完成后在页面底部下载 **`kazumi-tv-apk`** 里的 `Kazumi-tv-arm64.apk`。

workflow 里带一步校验：构建完会检查产物里 `LEANBACK_LAUNCHER` 和 `banner`
是否真的还在，**万一 manifest 被改坏会直接构建失败**，而不是给你一个装得上
但主屏找不到的 APK。

> A95K 是 arm64，所以只构建 `android-arm64`，体积比通用包小很多。

### 方式 B：本地构建

需要 Flutter 3.47.7、JDK 17、Android SDK + NDK 28.2.13676358：

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

如果构建卡在 jni 包的 CMake 上，加这一步（上游 CI 也这么做）：

```bash
sed -i -e 's/-Wl,/-Wl,--build-id=none,/' ~/.pub-cache/hosted/pub.dev/jni-*/src/CMakeLists.txt
```

---

## 三、装到 A95K 上

> `adb` 已经打包在 `tools/platform-tools/` 里（已 gitignore），**不需要**装
> Android Studio 或完整 SDK。装 + 验证 + 启动由一个脚本包办。

### 第一步：开开发者选项（只需做一次）

1. 遥控器按 **HOME** 回到主屏。
2. 齿轮 **设置** → 左侧选 **设备偏好设置** → **关于**。
3. 找到 **版本**（或 **软件版本** / *Build*）这一项，**用遥控器连按 7 次**。
4. 提示「您现在处于开发者模式」，按 **确定**。
5. 返回上一层再进 **关于**，最下面会出现 **开发者选项**。
6. 进 **开发者选项** → 打开 **USB 调试**。

### 第二步：连电视

**插线**（最省事）

1. 用**数据线**（不能是只供电的充电线）连电脑和电视。
   A95K 的 USB 口在**背面**，找标着 `BRAVIA` 的那个。
2. 电视上弹「允许 USB 调试吗？」→ 遥控器选 **允许**。

**无线**（不用插线）

1. **设置** → **设备偏好设置** → **关于**，记下 **IP 地址**。
2. **开发者选项** → 打开 **无线调试**。
3. 记下屏幕上显示的「配对端口」，然后：

```bash
cd /Volumes/Samsung_T5/ai/Kazumi
./tools/platform-tools/adb pair <电视IP>:<配对端口>
./tools/platform-tools/adb connect <电视IP>:5555
```

### 第三步：一键安装

把 Actions 下载的 `Kazumi-tv-arm64.apk` 放进 `~/Downloads`，然后：

```bash
cd /Volumes/Samsung_T5/ai/Kazumi
./install_to_tv.sh
```

脚本会依次完成：找 APK → 检查电视连接 → 安装 → **验证 LEANBACK 是否真的注册**
→ 检查电视是否声明 leanback → 启动。

也可以手动指定：

```bash
./install_to_tv.sh ~/Downloads/Kazumi-tv-arm64.apk
```

> **为什么要「验证 LEANBACK」这一步**：`adb install` 显示成功**不代表**电视
> 启动器会列出这个应用。只看安装结果会漏掉 category 没打进去的情况，
> 而那正是这次要修的核心问题。脚本用
> `cmd package resolve-activity -c android.intent.category.LEANBACK_LAUNCHER`
> 实际查一遍。

---

## 四、遥控器怎么用

| 键 | 作用 |
|----|------|
| 方向键 | 移动焦点。横屏时左侧是竖排导航栏，右边是内容区 |
| OK / 确认 | 打开当前选中的番剧 |
| 返回 | 逐层返回；在首页连按两次退出 |

---

## 五、已知限制（说清楚，别踩坑）

1. **播放器需要实测**。项目用 `media_kit`（libmpv），在真实电视上一般能跑，
   但我**没有在 A95K 上实际验证过**。如果播放黑屏或卡住，需要再调。
2. **纯触摸手势的功能在遥控器上不可用**。比如图片预览的双指缩放、
   弹幕输入框。项目里 `PageView` 几乎没用到（只有引导页和弹幕源面板），
   所以影响面很小，但这两个地方确实没法用遥控器操作。
3. **文字 ×1.3 是折中值**。如果你觉得还是偏小，改
   `lib/tv/tv_support.dart` 里 `television = TvEnvironment._(true, 1.3)` 里的
   `1.3` 即可。
4. **规则里的广告**来自片源本身，项目不插广告。

---

## 六、回滚

把 `AndroidManifest.xml` 里带 `tv` / `leanback` / `banner` 的行删掉，
再把 `main.dart` 和 `app_widget.dart` 里接的 `TvSupport` 去掉即可。
Dart 侧的 `lib/tv/` 目录删掉也不影响其他平台。
