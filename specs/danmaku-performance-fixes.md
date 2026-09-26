# Spec：弹幕渲染性能修复

## 背景

用户反馈弹幕"有的时候"帧率不足。经排查，逐帧绘制路径（painter 层，每帧仅 `drawImage` 预光栅化纹理）已经优化良好，不是瓶颈。性能问题集中在**弹幕入库时的同步光栅化**与**透明度整层合成**，另有 1 个正确性 bug 一并修复。

涉及代码分两部分：

| 部分 | 位置 | 说明 |
|---|---|---|
| 弹幕引擎 | git fork `bggRGjQaUbCoE/canvas_danmaku`（ref: main） | 问题 1/2/4 的引擎侧改动需提交到 fork 仓库；本地参考副本位于 `%LOCALAPPDATA%/Pub/Cache/git/canvas_danmaku-275046d8647a6a26cba1d0dadb9e28688cb3dbf1` |
| 播放器集成层 | `lib/pages/danmaku/view.dart`、`lib/pages/danmaku/controller.dart` | 本仓库内直接修改 |

引擎版本策略：fork 修改后，`pubspec.yaml` 的 `canvas_danmaku` 依赖更新到新 commit ref。

---

## Fix 1（高）：密集弹幕入库的单帧光栅化风暴

### 问题

- `view.dart:91-156` 的 `videoPositionListen` 以 100ms 为桶去重，同一桶内的全部弹幕在**同一次位置事件中同步入库**。
- 引擎侧 `_handleNormalDanmaku`（fork `lib/danmaku_screen.dart`）每条弹幕执行：`generateParagraph` 文本排版 → 描边段落二次排版 → `PictureRecorder.endRecording()` → **`toImageSync()` 同步光栅化 + GPU 纹理上传**。
- 热门视频同一 0.1s 桶可达数十条弹幕 → 单帧内数十次排版与纹理上传，造成集中掉帧。
- `mergeDanmaku` 关闭时，相同文本重复光栅化多份纹理，放大开销。

### 方案

**1a. 引擎侧：入库限流 + 分帧摊销**

在 `_DanmakuScreenState` 增加待入库队列，`_addDanmaku` 改为入队；`_tick` 每帧从队列取出至多 `maxRasterizePerFrame`（建议默认 4，可暴露为 `DanmakuOption` 字段）条执行实际光栅化与轨道分配。约束：

- `selfSend`（自己发送的）弹幕跳过队列，立即入库，保证即时可见。
- 队列按"先到先画"，不排序；队列非空时 ticker 保持活跃。
- `clear()` / `dispose()` / `_updateOption` 触发 `clearParagraph` 时必须清空队列并 `dispose` 队列中已创建的 `Paragraph`（若已排版未光栅化）。

**1b. 引擎侧：相同文本纹理缓存**

`DmUtils` 增加一张 LRU 纹理缓存（建议容量 128，key 为 `content.text + fontSize + fontWeight + strokeWidth + color + selfSend`）。命中则 `image` 直接复用并跳过 `generateParagraph`/`recordDanmakuImage`；缓存条目带引用计数或惰性失效，避免 `DanmakuItem.dispose()` 释放仍被其他条目引用的纹理。

> 简化实现（推荐先行）：仅缓存 key 中含 `content.text`，命中时直接 `image.retain()` 语义不可用时，改为"缓存持有纹理、item 不 dispose、缓存淘汰时统一 dispose"。`mergeDanmaku` 开启时同桶重复文本已被 `count` 合并，此缓存主要收益在 merge 关闭的用户。

### 验收

- 1000 条弹幕在 1 秒内涌入（构造极端段），渲染帧时间 p99 不因入库产生 > 8ms 的尖刺（DevTools timeline 单帧光栅化段）。
- 自发弹幕点击发送后 ≤ 1 帧可见。
- 切集/清空后无纹理泄漏（`ui.Image` 计数不持续增长，用 memory profiler 抽查）。

---

## Fix 2（中）：滚动弹幕纹理尺寸钳制

### 问题

fork `lib/utils/utils.dart` 的 `recordDanmakuImage` 没有 special 弹幕版本 `recordSpecialDanmakuImg` 那样的 `maxRasterizeSize = 8192` 钳制。超长文本 × devicePixelRatio（常见 3）生成数千像素宽纹理，单次光栅化慢、显存占用大，是"偶发"卡顿源。

### 方案

在 `recordDanmakuImage` 中，`toImageSync` 前若 `(w * devicePixelRatio) > maxRasterizeSize`：光栅化宽度钳制到 `maxRasterizeSize`，`DanmakuItem.width` 保持逻辑宽度不变（绘制时已走 `drawImageRect` 缩放分支，天然支持 src/dst 不等）。直接复用 special 版本的钳制代码，抽出共享的私有函数。

### 验收

- 构造 5000 字符弹幕，入库不产生 > 8ms 帧尖刺，纹理宽度 ≤ 8192px。
- 正常长度弹幕绘制不变形（`image.width == item.width.ceil()` 快速路径仍优先命中）。

---

## Fix 3（中）：透明度 < 1 时避免整层 saveLayer

### 问题

`lib/pages/danmaku/view.dart:174-187`：`DanmakuScreen` 外包 `AnimatedOpacity`，透明度绑定 `danmakuOpacity`。默认 1.0 走免 layer 快速路径；用户调低后，每帧整个弹幕画布在 saveLayer 中合成，GPU 开销近似翻倍，并叠加 Fix 1/2 的入库开销。

### 方案

去掉外层 `AnimatedOpacity`，改为引擎侧逐条应用 alpha：

- fork `DanmakuOption` 增加 `double opacity` 字段；`_updateOption` 处理变更。
- `BaseDanmakuPainter.paintImg` 的 `_paint` 从 `static final` 改为接收 `color` 参数（或 painter 持有带 alpha 的 paint），绘制时 `paint.color = Color.fromRGBO(0,0,0,opacity)`——`drawImage` 只取 paint 的 alpha。
- 显隐切换（`enableShowDanmaku` 0↔1）保留动画：`view.dart` 中仅当切换发生时用 `AnimatedOpacity` 包裹（或用 `TweenAnimationBuilder` 过渡 `DanmakuOption.opacity`）。稳定态（opacity 恒定 < 1）不经过 layer。

### 验收

- 设置透明度 0.6，弹幕正常半透明显示；GPU rasterizer 耗时较改前下降（DevTools raster 线程对比）。
- 透明度滑块拖动时过渡平滑；关闭弹幕仍淡出。

---

## Fix 4（低）：隐藏弹幕后 ticker 空转

### 问题

`view.dart:96` 隐藏仅靠 `AnimatedOpacity → 0`，paint 被跳过后 `drawTick`/`expired` 停止更新，ticker 满帧率空转至 `durationInMilliseconds` 过期后才停止（fork `_lazyTick` 注释已自证：`expired is always false` when opacity is 0）。纯 CPU/耗电浪费。

### 方案

在 `view.dart` 增加对 `playerController.showDanmaku` 的监听：隐藏时 `_controller?.pause()`，恢复时 `_controller?.resume()`。`pause()` 后引擎 `_running=false`、ticker 停止，`_isEmpty` 判断不再依赖 paint。

- 实现位置：`PlDanmaku` 的 `initState` 中 `ever`/`listen`（GetX Rx），`dispose` 时取消。
- 引擎侧无需改动（`pause/resume` 已存在）。

### 验收

- 播放中关闭弹幕，DevTools timeline 确认 ticker 帧回调停止。
- 重新打开弹幕，滚动恢复、无重复弹幕、无位置跳变（`resume` 时 `_lastTick` 重置已有逻辑保证）。

---

## Fix 5（bug）：权重过滤 `return` 应为 `continue`

### 问题

`lib/pages/danmaku/view.dart:117`：

```dart
for (DanmakuElem e in currentDanmakuList) {
  if (e.weight < danmakuWeight) return; // 应为 continue
```

同一 0.1s 桶内只要有一条弹幕低于权重阈值，其后所有弹幕被静默丢弃。正确性 bug，非性能问题，顺带修复。

### 方案

`return` → `continue`。

### 验收

- 设置权重过滤为"仅显示高权重"，桶内混合权重时低权重被过滤、高权重正常显示。

---

## 附：不建议本次处理

- `view.dart:124` mode==7 高级弹幕逐条 `jsonDecode`：频率低（高级弹幕稀少），收益小。
- `plPlayerController` 的 `makeHeartBeat` 每秒心跳：业务设计，不属于渲染问题。
- 引擎每帧 `fold` 汇总 length 与 painter 重建：O(轨道数) 常数级，实测非瓶颈。

## 实施顺序与依赖

1. **Fix 5**（1 行，立即）→ 2. **Fix 4**（仅集成层）→ 3. **Fix 2**（fork，独立）→ 4. **Fix 1a**（fork，核心）→ 5. **Fix 1b**（fork，依赖 1a 的队列结构）→ 6. **Fix 3**（fork + 集成层，涉及 option 协议变更，最后做）。

Fix 1/2/3 改 fork 后统一 bump `pubspec.yaml` 中 `canvas_danmaku` ref 一次。
