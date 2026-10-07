# Pace 单调时钟和日期隔离

当前 [零时长追赶定位](CARET_LINE_COMPOSITION_CONTRACT.md) 已接入原生截止回调，绘制仍合并，负时长不瞬移。新增九项、相关 112 项通过；36 组固定源码轨迹含待应用错词修正，前一目标由逻辑目录查询而非普通插值起点。没有改变时钟政策、模拟实体睡眠或声称任意追赶／呈现交错等价。

当前普通原生层的 [独立截止点调度](CARET_LINE_COMPOSITION_CONTRACT.md) 从同一生产单调模型读取剩余时长，单个待执行 Timer 与绘制计时器分开；请求时间使用进程内呈现时间，不写入记录。下文不创建每字符 timer 的表述为旧阶段，模型时间域和结果日期边界不变；睡眠／唤醒、OS 迟到全部顺序和实机仍待验证。

当前 Pace 的首次启动、词提交、逻辑刷新和原生插值读取同一个可注入的进程内单调时间源。事件日期和 TimelineView 日期不再作为 Pace 的经过时间，因此壁钟向前跳不使节奏提前耗尽、向后跳不冻结推进。这只修复 Pace 时间域，不代表整个测试计时系统或 Monkeytype 全功能已等价。

## 源码和平台依据

官方只读检出仍固定 `91bd24bb8513785c7364cbea29296ff7adafac41` 且干净。[pace-caret](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/pace-caret.ts) 用 performance.now 建立起点和绝对截止点；[W3C 2026 年 2 月工作草案的时钟定义](https://www.w3.org/TR/2026/WD-hr-time-3-20260225/#clocks) 区分受调整的壁钟与不受调整的单调时钟。草案不是浏览器实现证明。

默认原生时间源选择 [Swift SuspendingClock](https://developer.apple.com/documentation/swift/clock/suspending)，从配置时捕获的本地 Instant 测量相对秒数，再在首次接受输入／组合开始时建立 Pace 起点。Apple 定义该时钟在系统睡眠时停止增长；选择这个平台政策不等于证明所有浏览器的睡眠行为相同。没有使用日期修正、NTP 推算或持久化系统启动时间。

本机 Swift 6.2.4，SDK 的 _Concurrency.swiftinterface 明确 SuspendingClock／now／Instant.duration(to:) 自 macOS 13 可用，Swift.swiftinterface 明确 Duration.components 的秒与 attosecond 两项；项目最低 macOS 14，无新依赖或最低版本变更。只使用 Swift Clock 抽象，不新增直接 mach 时间函数、系统启动时间查询或遥测。SDK 源在 Xcode MacOSX.sdk/usr/lib/swift 中，本轮编译验证实际接口，不以最新主分支代替安装版本。

## 状态和消费者边界

| 消费者 | 当前时间来源 | 明确边界 |
| --- | --- | --- |
| 首次接受输入与组合开始 | PaceCaretClock.now 的本地秒数 | 配置后等待及被拒首空格不消耗节奏；不是把输入 Date 翻译成单调时间 |
| 错词提交与会话 tick | 同一个已配置 clock | 提交仍先推进到当前截止点再保存修正，blind／重交规则不变；词模式夹具隔离了结束计时的日期边界 |
| 原生光标和 fallback 目标 | session.paceCaretFrame() 内部采样 | TimelineView 仅触发刷新，不把 timeline.date 传给 Pace；原有形状、字体、主题、减少动态效果和关闭时无逐帧层不改 |
| 结果日期、时长、速度和回放 | 原有日期及保存合同 | 不加入单调秒数、不重算旧值。整个测试的 timed completion、实时／最终 WPM 等仍可能受壁钟跳变影响，是后续必需工作，不被本轮宣称修复 |

生产模型只接受数值时间源，不接受 Date。测试辅助层保留日期到明确数值样本的便捷适配，以保持历史夹具的同一截止点断言；这不是生产回退路径。会话测试直接注入独立可控时钟，词内事件日期与节奏样本刻意不相关。每个新会话的模拟起点明确设置，不依赖前一会话查询留下的样本。

重设模式丢弃原 Pace 和时间源，已开始会话不自动重新启动；重开创建新会话并重新配置。关闭 Pace 释放其捕获的时钟引用；不创建 per-character timer、异步时钟任务或新 GUI。模型对非有限样本不前进，对注入的回退样本不倒退已消费逻辑步；真实默认时钟的合同保证单调。非法首次样本保持未启动，测试模型可用后再 start，真实默认源无该非法输入合同；不声称新增了生产时钟故障恢复。

PaceCaretClock／进程内起点不编码、不写入 SwiftData、预设、归档或服务。格式仍 24／设置仍 4。回退本批只影响新会话的暂态行为，无数据转换、双写或清理；此前自定义小数和 v2 偏好的回退限制继续适用，真实旧库／旧二进制恢复仍未验。实际 paired result 测试比较日期、回放、字符统计及精确速度／准确率不变，但这不是所有时间故障下的完整结果等价证明。

## 行为证据

先行两项原生测试编译成功，实际执行两项、三处失败（其中一处为 XCTUnwrap 引发的 unexpected 异常），分别暴露向前一小时的 frame 投影和词提交耗尽；没有把编译错误算作 RED。删除日期 frame 接口后，将同样的跳变场景移到真正会话 tick／词提交，并使用明确独立的单调样本检查目标和半步插值，没有降低断言或保留仅测试旧 API 的绿灯。

新增 PaceCaretClockTests 十二项：向前／后日期、提交、晚开始／被拒输入、blind 修正、模式重设与重开、新旧时钟隔离、结果不变、非法／回退样本、关闭释放、默认系统样本及未注入的默认会话路径。相关首轮 48 项有两处失败，因同一历史测试中的第二个会话没有恢复模拟起点；仅补夹具 reset，原断言保留。扩大 116 项通过（0.335 秒），补默认路径后最终定向 117 项零失败（0.341 秒）。

四个实际完整源码模块仍是 pace-caret、collections/results、db、test/test-words。原 46 组选择加 19 组推进，共 65 组通过；新两组分别改变 OwnedDate.now 而保持 performance 时钟独立，核对实际源码目标及剩余 animation duration。第一次新增探针将既有 const 壁钟变量赋值而失败，修正为受控可变绑定后通过；此探针加载错误不算行为反例。Query DSL、认证、标签 PB、单调 clock／timeout、Caret 是有界适配，没有运行 DOM、animejs、浏览器或官方账号，实际睡眠和像素等价不由此证明。

日志为 `/tmp/typebar-pace-clock-red.log`、`/tmp/typebar-pace-clock-green.log`、`/tmp/typebar-pace-clock-expanded.log`、`/tmp/typebar-pace-clock-final-focused.log`、`/tmp/typebar-pace-clock-source.log` 和 `/tmp/typebar-pace-clock-source-final.log`。新增三条人工场景保持待验收，清单审计只验证结构，不把自动化当实机通过。

完整串行门禁客户端 2814 项零失败、零跳过（671.138 秒），服务端 164 项零失败（1.776 秒）；834 条人工场景结构、固定参考／原创性／元数据审计及未开窗应用包检查通过。实际十万词 passed 为 145.470 秒，旧 12000 次组合字形删除双投影为 0.025376 秒；不证明活动 Pace 实机帧率或布局性能。门禁和日志捕获均已成功结束，期间没有编辑文件；其后只补结果记录，生产行为不改。

完整门禁日志 `/tmp/typebar-pace-clock-readiness.log`，完整客户端／服务捕获为 `/tmp/typebar-pace-clock-gate-client.log` 和 `/tmp/typebar-pace-clock-gate-service.log`；package 捕获未含最终审计行，以门禁成功退出和 `macOS app package check passed` 为准。AddressBook／CoreData XPC 环境诊断不是 XCTest 断言失败，也不算系统服务验收。固定参考仍干净，Typebar 图形进程为零，真实背景成绩目录不存在；没有真实音频／库写入或部署。

门禁后提交前定向 117 项零失败（0.327 秒），四模块 65 组源码夹具及 834 场景结构检查仍通过；日志为 `/tmp/typebar-pace-clock-postgate-focused.log` 和 `/tmp/typebar-pace-clock-postgate-source.log`。生产代码／服务／依赖在门禁后未变，文档保存不代表窗口或渲染验收。

## 仍需完成的验收

整个测试结束和速度计时的单调时间域、实体睡眠／唤醒、系统时间修改与帧调度、IME／VoiceOver／窗口取消、活动 Pace CPU／长练习内存、Tape／逐字混合 RTL／其他动画组合仍开放。已只读核对完整 [test-timer](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-timer.ts)：主计时器使用 performance.now、理想秒截止点及晚到补进，原生主计时的日期依赖仍需后续迁移；本轮没有执行该完整模块的 timer 行为探针。引语／标签身份和认证、PB 快照、官方主题、挑战、内容分布及 XP 精确公式等整体缺口不关闭。当前源码 VM 和 headless 绿灯不改变功能追踪表中的部分／未验状态。

行为优先和根因调试先复现日期污染；源码驱动验证固定 Monkeytype、W3C 和安装 SDK；迁移安全限定成绩不回写；原生 UI 技能保持现有视觉层和减少动态效果，文档技能分开本轮证据与历史记录。会话内有界决策／风险复核，不是独立评审；完整纯原生重写 goal active。
