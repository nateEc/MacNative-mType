# 主会话单调计时合同

2026-10-04 结束顺序更新：[资格与反馈合同](RESULT_FINISH_PRIORITY_CONTRACT.md) 将新失败／闲置快照纳入日期优先检查，随后失败、过短、闲置等有序评估；原 outcome／时钟不重写，重复闲置结转独立处理。16 项新增及相关 87 项、完整源十模块 92 组通过；窗口、完整成功结束链及整体等价仍开放。本合同下方为先前时钟切换与磁盘阶段证据。

2026-10-04 磁盘验证更新：[历史模型升级合同](DISK_MODEL_MIGRATION_CONTRACT.md) 已验证两代自有存储声明生成的 SQLite 经实际生产模型自动升级，新时长与真实日期保存／重读、旧字节不回填和闭库旧备份恢复。七项新增及相关 81 项通过；这不覆盖旧发行 SDK／实际用户库、macOS 14、真实应用冷启动或睡眠。本合同下方原有证据为计时切换阶段，整体 goal 仍 active。

2026-10-04：当前源码的三个 UI 工厂入口及重复入口接入独立 SessionElapsedClock。倒计时、速度、活动、物理键、Weakspot、burst、回放和结束快照使用同一测量时间域，真实日期单独保留。此前 [格式与服务扩展](RESULT_ELAPSED_TIME_CONTRACT.md) 是先行阶段，现在新会话实际产生 elapsedTime。这不是已在真实用户库完成升级或部署的声明，完整重写 goal 仍 active。

## 来源与时钟选择

只读官方源码固定 91bd24bb8513785c7364cbea29296ff7adafac41。[完整 test-timer](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-timer.ts) 用 performance.now 驱动起点、整秒网格、提前重排和补 tick，起止日志另外保存真实日期。[live-cache](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/live-cache.ts)、[stats](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts) 和 [finish](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts) 分开测量分母、日期资格和尾部剪裁。实现独立用 Swift 编写，不复制源码或资产。

默认与既有 Pace 一样选择 [Apple SuspendingClock](https://developer.apple.com/documentation/swift/suspendingclock)：系统睡眠期间不增长，与日历日期调整分离。主时钟和 Pace 各有起点，刷新／关闭 Pace 不重设主计时。这不是浏览器睡眠等价证明：真实睡眠、唤醒、后台调度、完整浏览器和像素均未运行。最低 macOS 14 与依赖不变，TimelineView 日期不提供测量源。

## 运行态及保存边界

| 消费者 | 新会话时间来源 | 保存内容 |
| --- | --- | --- |
| 首次准入输入／组合开始 | 当次操作捕获样本 | 真实 startedAt |
| 批次、删除及嵌套输入 | 最外层一次采样，嵌套复用 | 回放相对偏移 |
| 物理边沿、Weakspot、burst、AFK | 同域私有测量坐标 | 匿名相对证据 |
| 倒计时、实时速度、警告／timer health | 当前测量秒数与原整秒网格 | 暂态不持久化 |
| 完成、失败、BailOut、放弃 | 结束样本冻结 | elapsedTime v1 raw 秒数及真实 finishedAt |
| 重开／重复 | 同一源、全新起点和队列 ID | 旧结果不修改 |

私有 Date 容器只适配既有区间算法，值来自本地时钟相对秒数，并非日历日期。measuredStartedAt、measuredFinishedAt、activeTimingDate、origin／Instant／uptime 均不进入结果、实体、归档或服务。公开日期始终是真实传入日期，结束日期倒退也不伪造。归档仍 25、设置仍 4，旧 WPM／Raw／准确率／回放不回算。

纯引擎 Date 注入 API 默认保留旧测试路径；显式附加时钟才产生新字段，UI 新建／重复全部显式启用。已输入或记录物理活动后不能附加／替换时钟，已启用时钟不能中途替换。Rejected 首空格不开始，marked composition 可开始但不产生已接受文本；结果不因后来时钟增长改变。

延迟代码 Tab 保留触发输入的日期与测量坐标，回放仍在源输入偏移；实际回调另捕获执行时间／日期用于结束。立即嵌套不多采样，旧纯模拟 nil 执行日期保持确定性；旧 attemptID 的回调不进入重开后的队列。操作内一致采样不代表整个 UI 帧的 getter／tick 只读一次，也不代表 RAF 性能等价。

实时速度读 raw 秒数，结束非 custom 分母两位舍入、custom 原精度；Zen／BailOut 物理证据仍按不足七秒尾部剪裁。上一 prestart 物理 down 的间隔保持源码夹零规则。物理 timingEvidence 绑定剪裁前 raw，practiceTiming／WPM 绑定模式分母，真实日期只用于日历资格／展示等。

新增本机资格拒绝具有新时长的普通完成 time：模式分母不超过 120 秒且偏离实际有符号日期差超过 0.1 秒。120.004→120 仍检查，120.005→120.01 只跳过该检查；BailOut 和旧无字段记录不新增规则。AFK 整秒区间及其他条件不放宽。当前 outcome 的 AFK／失败呈现与源 finish 全部检查优先级仍不宣称等价。

## 迁移与回退

切换单元为未开始的新会话，不改变已有会话时间域；格式／服务先扩展再接入 producer。没有打开真实 SwiftData 库、启动 GUI、修改系统日期、创建账号或部署服务。可选列与内存模型不证明真实旧 schema 可升级／回退。

真实安装／分发前须用隔离旧库副本验证升级、重启、导出和恢复，保留升级前库／旧档；不得双 writer，坏显式字段不得静默降为旧记录。若 schema、精度或服务能力不符，应停止实际切换、保留数据并隔离诊断，不清库或覆盖归档。旧二进制可能忽略字段／错误派生时间；回退需恢复升级前副本或向前修复，不宣称安全读取新库。源码已启用不是上线门禁通过。

本机长时长／零仍可归档，服务 raw 大于零／不超过 3600 秒等约束不写进引擎。新 producer 要求精确 v1/resultElapsedTime 能力，不能丢字段降级上传；旧完成成绩的旧协议回退不变。损坏保护、归档墓碑和真实日期精度沿用先行合同。

## 证据与剩余工作

六项先行测试实际执行 30 处失败（含一处缺字段 unwrap）；此前两次 API 编译错误不是行为 RED。实现后剩一处物理间隔夹具错误，按实际源码前一 down 夹零修正期望，未改物理策略。扩展十五项、相关 144 项零失败（3.133 秒）；最后二十项、相关 149 项零失败（3.187 秒）。资格新夹具首次三处失败是不足半秒尾段不进入 AFK 完整区间，输入移至完整区间后保持原规则，不放宽 AFK。

二十项覆盖日期正／负一小时、倒计时、速度／结束冻结、物理末键、组合、批次一次采样、延迟 Tab、重开与 Pace 隔离、AFK／练习时长、Unicode／burst、资格／舍入、BailOut／旧记录、实时最小速度、无限挑战及真实 producer→内存 SwiftData→归档→发布准备。内存不是旧库；准备不是 HTTP／真实网络，服务完整回归另由门禁验证。

新增 Scripts/check-source-session-clock.mjs 在内存执行完整实际 test-timer.ts，16 组自有夹具覆盖 Date 跳变、提前重排、理想网格、补 tick 副作用、结束防重复、慢计时严格阈值／次数和长模式排除。animejs 调度、缓存、度量、UI／音效均为明确自有绑定，不执行浏览器／RAF／完整保存链。已有十模块 78 组探针继续单独覆盖实际事件／stats／finish，不将二者说成端到端浏览器测试。

日志：/tmp/typebar-session-clock-red-executed.log、/tmp/typebar-session-clock-green.log、/tmp/typebar-session-clock-expanded.log、/tmp/typebar-session-clock-final-focused.log、/tmp/typebar-session-clock-final-focused-corrected.log、/tmp/typebar-session-clock-source.log 和 /tmp/typebar-session-clock-terminal-source.log。新增三条人工场景全部待验收；只串行测试／构建，内存测试隔离，运行期间不编辑，应用包只验证不打开。

完整串行门禁成功退出：客户端 2859 项零失败、零跳过（682.526 秒），同轮明确启用的十万词耐久通过 148.004 秒；服务端 175 项零失败、零跳过（1.810 秒），843 场景仅结构检查、固定参考／原创性／元数据和未开窗应用包验证通过。旧 12000 次组合书写簇退格双投影 0.024789 秒只是旧样本，不证明新时钟实机性能。AddressBook／CoreData XPC 环境诊断不是测试断言失败或系统服务通过。

完整日志 /tmp/typebar-session-clock-readiness.log；客户端／服务完整日志在临时清理前捕获为 /tmp/typebar-session-clock-gate-client.log 和 /tmp/typebar-session-clock-gate-server.log。package passed 以完整门禁日志为证，没有另存完整分项 package 日志。编译、测试、打包期间不编辑项目；终态后只补文档，没有改变生产／测试／服务或依赖。参考仍固定且干净，无 GUI／系统时间修改／真实库／部署；真实背景成绩目录仍不存在。

门禁后提交前，定向 149 项再次零失败（3.253 秒），完整源 timer 16 组、既有十模块 78 组及 843 场景结构再次通过。日志 /tmp/typebar-session-clock-postgate-focused.log、/tmp/typebar-session-clock-postgate-source.log 和 /tmp/typebar-session-clock-postgate-terminal-source.log。生产代码在全量门禁后未变，补充验证不能代替设备验收。

会话内源码驱动、行为优先、迁移安全及有界决策／风险复核保障采样、队列与旧数据边界，非独立审计。真实旧库／回退、睡眠／系统时间／IME／窗口／VoiceOver、长期资源／组合、完整完成策略与整体等价仍开放；主题、挑战、原始内容身份覆盖不升级。文档技能保存证据，不把 Markdown 当设备／渲染验收。
