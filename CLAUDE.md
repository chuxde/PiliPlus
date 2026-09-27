# CLAUDE.md

PiliPlus（B站第三方客户端，Flutter）的本地 fork，维护分支 `my-mods`。

## 仓库结构

- `origin` → https://github.com/chuxde/PiliPlus.git（我的 fork）
- `upstream` → https://github.com/bggRGjQaUbCoE/PiliPlus.git（上游）
- 日常改动直接提交在 `my-mods` 分支；推送前先问用户（用户要求过不要擅自 push）

## 本地自有改动（rebase 时需保留）

- **系统媒体控制上下集**：`lib/services/audio_handler.dart`（skipToNext/skipToPrevious + onNext/onPrev）、`lib/pages/video/view.dart`（bindMediaSessionSkip）
- **本地构建配置**：`android/app/build.gradle.kts`（compileSdk 37.0 DSL）、`android/gradle.properties`（kotlin.incremental=false）、`lib/scripts/patch.ps1`（pub 缓存路径自动探测）
- **弹幕性能修复**：`specs/canvas_danmaku-perf.patch` + canvas_danmaku 已通过 `dependency_overrides` 指向 chuxde/canvas_danmaku 的 `perf` 分支（commit ea7d1b7）

## 后续更新流程（上游发新版时）

```bash
git fetch upstream
git rebase upstream/main        # 在 my-mods 上，解决冲突
flutter pub get
```

1. 若 `pubspec.yaml` 中 Flutter 版本变了 → 先 `flutter upgrade`，**再重打 SDK 补丁**（见下）
2. 若上游更新了 `canvas_danmaku` 的引用：保留上游 lock 后，将 `specs/canvas_danmaku-perf.patch` 重新应用到新提交、推送到 chuxde/canvas_danmaku、更新 `dependency_overrides` 的 ref
3. 重新构建验证

### Flutter SDK 补丁（必须）

项目源码依赖补丁后的框架 API（公开的 `TabBarState`、`IndicatorPainter` 等），**不打补丁会有 100+ 编译错误**。上游 CI 构建前执行 `lib/scripts/patch.ps1`，本地同样：

```powershell
$env:FLUTTER_ROOT = "D:\dev\flutter"
$env:GITHUB_WORKSPACE = "D:\vscode\piliplus\PiliPlus"   # 即项目根
powershell -ExecutionPolicy Bypass -File lib\scripts\patch.ps1 android
```

- 脚本开头会 `git reset --hard` 清掉旧补丁再重打，**幂等**；`flutter upgrade` 或任何 SDK git 操作会清掉补丁，之后必须重跑
- 补丁同时作用于 SDK 和 pub 缓存里的 `material_ui`/`cupertino_ui` 包（脚本会自动删缓存重下再打）
- 脚本会改全局 git user.name/email 为 ci/example@example.com，跑完记得恢复

## 编译遇到过的问题与解决

| 问题 | 解决 |
|---|---|
| Flutter 命令卡死无输出 | 中断的 upgrade 留下残留进程持锁：`taskkill` 掉所有 `dart.exe`/`flutter.bat`/`java.exe`，删除 `bin/cache/lockfile` 和 `BIT*.tmp`，再重新跑一次让其自修复 |
| `flutter_inappwebview` 检出缺 Java 源文件（编译报类找不到） | Windows 260 字符路径限制导致 git 检出失败。已设 `git config --global core.longpaths true`，然后在该包目录 `git restore .` |
| AGP 报 `Failed to find target with hash string 'android-37'` | SDK 仓库里 API 37 只有 `android-37.0`（新版次命名）。已改用 AGP 9.1 DSL：`compileSdk = 37` + `compileSdkMinor = 0`（android/app/build.gradle.kts）。注意 `permission_handler_android` 要求 compileSdk ≥ 37，不能降到 36 |
| Kotlin 报 `Could not close incremental caches / Storage already registered` | 已在 `android/gradle.properties` 加 `kotlin.incremental=false`；杀掉残留 `java.exe`（Gradle/Kotlin 守护进程）后重试 |
| media-kit 构建时从 GitHub Releases 下载 libmpv jar 超时 | 需要代理可达 github.com；jar 缓存在 `build/media_kit_libs_android_video/<日期>/`，SHA 校验失败会自动重下 |
| `material_ui` 里 `TabBarState` 等类型找不到 | SDK/material_ui 补丁没打，见上节重跑 patch.ps1 |
| 依赖 git 包（canvas_danmaku 等）的本地改动 | 一律放 fork 分支并走 dependency_overrides，**不要**改 pub 缓存（会被 pub cache repair 冲掉） |

## 网络/代理环境

- 机器走 Clash TUN（Fake-IP DNS），GitHub/Google 可达；`filehelper.qq.com` 经代理 TLS 握手失败（mail.qq.com 正常），需 DIRECT 规则
- 中国镜像可选：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`

## Release 签名

- `android/app/key.jks` + `android/key.properties`（storeFile/storePassword/keyAlias/keyPassword），均已被 gitignore
- **密钥和密码已备份与否需向用户确认**；丢失则无法覆盖更新已安装的应用
- 换机器构建需拷贝这两个文件

## 常用构建命令

```bash
flutter build apk --release --target-platform android-arm64
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 其他备忘

- 本机 Flutter 在 `D:\dev\flutter`（已打补丁的 3.47.5），JDK 17 在 `D:\dev\jdk-17`
- 项目分析的 codegraph 索引在 `.codegraph/`（已 gitignore）
- QQ 客户端 UI 自动化（SendKeys/mouse_event）在此环境不可靠，Computer Use 会话不可用；发文件优先让用户手动操作
