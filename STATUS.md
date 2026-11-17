# Status

**Status:** Active <!-- Active | Paused | Blocked | Done -->
**Updated:** 2026-11-16

## Summary

iOS 时间记录器：记录你今天做了什么，并把一整天画成一条 24 小时垂直时间线。
原来的「循环倒计时器」已被吸收为「模式 2」——见 README 的「为什么不再有循环」。

## Feature spec (agreed, frozen)

| Item | Decision |
|---|---|
| Mode 1 | 任务名 + 时长 → 倒计时 → 到点提醒一次 + 自动结束记录 |
| Mode 2 | 仅任务名 → 正计时（显示累计时长）→ 20 分钟网格提醒，最多 10 次，手动停止 |
| 提醒文案 | 动态累计时长（「「写作」已经 1 小时 20 分钟了」） |
| 接管 | 开始新任务时静默结束旧任务（`superseded`），不并行 |
| 跨夜 | 一律在 00:00 截断（`midnightCut`） |
| 记录 | SwiftData；时长恒为 `endedAt - startedAt`（时间戳数学，抗杀进程/重启） |
| 画布 | 垂直 24h、不裁剪、空档显式画出、模式 2 块内画提醒刻度 |
| tag / 达成率 / 手工编辑 | 不做 |
| 导出 | JSON + CSV（UTF-8 BOM） |
| 后台 | 不需要保活进程 |

## Progress — 全部完成

- [x] **① Data layer** — `Session`、`DaySegment`/`DaySummary`/`DayComposer`、`SessionStore`
- [x] **② Day canvas** — `DayTimelineView`：垂直 24h、1h = 72pt、不裁剪、空档/未来区分、模式 2 刻度、现在线 + 自动滚动、日期翻页
- [x] **③ Notifications** — `SessionReminderScheduler`：模式 1 单次、模式 2 网格 ≤10 条含累计时长；停止/接管/自动结束批量取消
- [x] **④ Export** — `ExportService` + `ExportSheet`（当天/全部 × JSON/CSV，逐字节验证）
- [x] **⑤ Cleanup** — 见下

## ⑤ 删掉了什么（以及为什么）

| 删除 | 原因 |
|---|---|
| `Views/TimerView.swift` | 根视图已换成 `TodayView`，无人引用 |
| `ViewModels/TimerViewModel.swift` | 只被 `TimerView` 使用 |
| `Services/TimerService.swift` | 被 `SessionStore` 取代（且它把 `elapsed` 重置为余数，对正计时是错的） |
| `Views/TimerControlsView.swift` / `TimerDisplayView.swift` / `TimerPickerView.swift` | 只被 `TimerView` 使用 |
| `Services/NotificationService.swift` | 被 `SessionReminderScheduler` 取代（旧实现预排 64 条 loop 通知，不可持续） |
| `Models/TimerState.swift` / `DisplayMode.swift` | 状态由 `Session.endedAt` 表达；±显示切换随 loop 语义废弃 |
| `Extensions/TimeInterval+Extensions.swift` / `Date+Extensions.swift` | 零引用 / 被 `Duration+Formatting` 取代 |
| `LoopTimer/Resources/AUDIO_FILES_README.md` | 在同步目录里 → 会被打进 .app；移到仓库根 |

同时从 `project.pbxproj` 删掉了 widget 目标 `membershipExceptions` 里指向这 3 个文件的 3 行（同步文件夹的显式成员表，删文件必须同步删）。

## ⑤ 改了什么

- **计时页空态**：空闲时上方显示「最近」3 条记录、输入区锚定在底部，避免整页只剩一个悬空的输入框。
- **画布运行中块**：不再显示右侧时长标签（它的右边缘正好压在「现在」胶囊下面），改由红线表达「进行中」。
- **Siri 一句话记录**：新增 `QuickStartSessionIntent`（单一 `内容` 参数）+ `QuickInputParser`（「做饭25分钟」「看书半小时」「健身1小时20分钟」「跑步 40」「写作」→ 名称 + 时长）。Siri 短语只能唤醒、不能携带 String/Int 参数（`App Shortcuts` 编译期限制：一句只能一个参数且必须是 AppEntity/AppEnum），所以走「唤醒 → 追问一句 → 解析」的流程。
- **计时页与详情页日期解耦**：`SessionStore` 现在同时发布两份投影 —— `segments/summary`（详情页，跟随 `day`，可翻历史）与 `todaySegments/todaySummary`（永远今天）。计时页的「最近」列表与页脚汇总只读后者；`start()` 不再改写 `day`，所以浏览历史时开始新任务不会把详情页拽回今天（0 点截断仍会在「本来就在今天」时跟随跨日）。
- **快捷指令 / Siri 支持**：新增 `Intents/SessionIntents.swift` —— `StartSessionIntent`（任务 + 时长分钟，0 = 不定时）、`StopSessionIntent`，以及 `AppShortcutsProvider` 的 Siri 短语。SwiftData 容器提到 `Persistence.shared`，让后台被意图唤起时也能 `attachIfNeeded()`；`perform()` 会 await 提醒注册（后台意图返回即被挂起）。
- **提醒泄漏修复**：会话可能在进程死亡期间结束（0 点截断、reconcile 去重），没人取消它的待投递通知——实测堆积到 33 条。新增 `sweepStaleReminders(keeping:)`，在每次 reconcile 时清掉不属于当前会话的 `session-*` 请求。
- **主界面拆成两页**（左右滑动）：`TodayView` 变成 pager 容器（`TabView` + `.page`，index dots 隐藏、改用自绘的两点指示器，可点可滑）；新增 `TimerPageView`（计时：输入 + 运行中卡片 + 页脚汇总）与 `DayPageView`（今天：汇总 + 画布 + 导出）。工具栏内容随页切换——日期与前后翻页只在「今天」页出现，设置只在「计时」页出现。
- **输入简化**：去掉「不定时 / 定时长」分段控件，改为单一「时长（分钟）」输入框，**0 = 不定时**；数字键盘带「完成」工具条，时长通过 `@AppStorage("inputMinutes")` 记住上次的值。
- **画布「现在线」错位修复**：`rows` 原来用 `segment.end > nowTick` 判断 marker 插入点，但 `nowTick` 是视图状态、可能比 store 重算分段时用的 `now` 更旧 → 判据命中 → marker 被插到一天最顶部。改为锚定 `.future` 段的起点（`DayComposer` 就在那里切分，语义上就是「现在」）。
- **模式 1 主显示修正**：压缩运行卡片时丢了分支，倒计时任务的大号数字显示成了「已用时间」，现已改为剩余时间。
- **Live Activity 竞态修复**：`endAll()` 原来在 `Task` 内部才读 `Activity<T>.activities`，那时新建的 activity 已在列表里 → **刚请求成功就被自己立刻结束**（真机上表现为「锁屏什么都不显示」，模拟器日志里却能看到 `Received new activity`）。改为在调用点先快照，并用 `Activity.activities` 作为唯一真相（不再缓存实例）。同时：`Activity.request` 只在 app 活跃时有效，故在 `scenePhase == .active` 时再 sync 一次；`areActivitiesEnabled == false` 或请求失败时在运行卡片里显示原因（橙色提示 + 「去开启」跳设置）。
- **Live Activity 重新接线**（A1）：`TimerActivityAttributes` 改为 `sessionID/title/startedAt/plannedEnd`，`ContentState` 故意为空——widget 用 `Text(timerInterval:)` 自己走时钟，**一个 session 只需 1 次 request + 1 次 end，零更新流量**。`SessionStore` 在 start/stop/接管/自动结束/`reconcile` 时 `sync(with:)`；`StopTimerIntent` 通过 NotificationCenter 回到 store。
- **设置页**（B1）：新增「静音」开关；`TodayView` 的响铃不再写死 `Bell`/`isMuted: false`，改读 `@AppStorage`；汇总行加了一个设置入口。
- **App 图标**（C1）：CoreGraphics 脚本生成浅色/深色/着色三档 1024×1024（圆环缺口 + 中心点），`Assets.car` 现在能正常产出。
- **后台**：`Info.plist` 删掉 `UIBackgroundModes: audio`；`AudioService` 不再常驻激活音频会话，改为播放时激活、播完释放。
- **entitlements**：删掉未使用的 app group（它会使命免费 Apple ID 重签失败）。
- **部署目标**：`26.2` → `17.0`（README 声称 iOS 17+，而 SwiftData 也需要 17.0）。
- **AccentColor / WidgetBackground**：补齐颜色，不再引用空色板。

## 实现笔记

- **画布用真实布局高度**，不是 `.offset`：布局位置必须等于时间位置，否则 `scrollTo` 全部落到 0。「现在」marker 是 VStack 里的零高度行。
- **通知计划是纯函数**：`plan(for:now:)` 生成全部请求，`schedule(for:)` 只负责注册；identity 是 `startedAt`，重跑幂等。
- **首次授权顺序**：`.notDetermined` 时 `add` 会被拒（`UNErrorCodeNotificationsNotAllowed`），所以流程是「注册 → 请求 → 若授权状态变化再注册一次」。少这一步，第一次会话的提醒会静默丢失。
- **不保活进程**：时长来自时间戳，提醒来自系统，秒表只在 app 前台刷新界面。
- **浏览历史日不会被拽回今天**：`reconcile()` 只在「本来就在今天」时跟随跨日。

## Dev aids (DEBUG only)

```bash
xcrun simctl launch booted com.monsur.LoopTimer -seedDemoDay     # 播种一整天的样例（只播一次）
xcrun simctl launch booted com.monsur.LoopTimer -demoStopwatch   # 起一个模式 2 任务
xcrun simctl launch booted com.monsur.LoopTimer -demoCountdown   # 起一个 20 秒倒计时
xcrun simctl launch booted com.monsur.LoopTimer -demoYesterday   # 打开昨天
xcrun simctl launch booted com.monsur.LoopTimer -stopActive      # 结束当前会话（截图用）
xcrun simctl launch booted com.monsur.LoopTimer -showDay         # 直接切到「今天」页
xcrun simctl launch booted com.monsur.LoopTimer -demoIntent      # 直接调用 StartSessionIntent（25 分钟）
xcrun simctl launch booted com.monsur.LoopTimer -demoQuick       # 直接调用「快速记录」，内容=「做饭25分钟」
xcrun simctl launch booted com.monsur.LoopTimer -demoParse       # 把解析结果写到 tmp/parse.txt

> 反复启动时用 `simctl launch --terminate-running-process`，否则参数会被静默忽略（进程还活着时会 attach 到旧进程）。
xcrun simctl launch booted com.monsur.LoopTimer -demoTrickyTitle # 插入需要 CSV 转义的标题
xcrun simctl launch booted com.monsur.LoopTimer -dumpPending -provisionalAuth
    # 把提醒计划 + 授权状态写到 <container>/tmp/reminders.txt（provisional 授权可静默通过，
    # 因为 simctl privacy 没有 notifications 服务）
xcrun simctl launch booted com.monsur.LoopTimer -dumpExport       # 写 export-day/-all 到 tmp
xcrun simctl launch booted com.monsur.LoopTimer -showExport / -showSettings
xcrun simctl launch booted com.monsur.LoopTimer -dumpTimeline
    # 把画布的 rows / 每段高度 / 总高写到 tmp/timeline.txt
xcrun simctl launch booted com.monsur.LoopTimer -demoStopwatch -dumpLiveActivity
    # 在 +2s/+8s/+26s 把系统实际持有的 activity 列表写到 tmp/liveactivity.txt
```

## 验证状态

- 模拟器 Debug + 真机 Release 构建通过
- 两种模式开始/停止/接管、模式 1 自动结束、0 点截断、持久化、画布、导出字节、通知注册与取消均已实测
- App 图标在 SpringBoard 正常显示；`Assets.car` 已生成
- Live Activity 生命周期实测（`-dumpLiveActivity`，模拟器）：
  开始 → `count=1 state=active`；接管 → 旧 activity 结束 + 新 activity `count=1`；
  倒计时到点 → `count=0 state=idle`。锁屏外观仍需真机确认（模拟器无法锁屏）

## 尚未做

- 真机验收 Live Activity 的锁屏/灵动岛外观与 stop 按钮（模拟器无法锁屏）
- `APP_STORE_PUBLISHING.md` / `Live-Activity.md` / `RUNNING_ON_DEVICE.md` 仍是旧版本描述，未更新
- 画布上连续超短记录的浮动标签压叠（纯视觉）
