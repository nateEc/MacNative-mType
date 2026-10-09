# 普通多行 Tape 生产入口与高度所有权

## 单次完整重建耗时的反证（2026-10-10）

在 293f277 后新增 QA 固定阶段 prompt-render-finished：仅双重启用诊断时测量 renderedPrompt(for:composition:) 整段同步执行，超过 0.125 秒才记录相对时间、耗时及会话状态。没有文本、身份、跨帧缓存、输入／计时健康阈值或调度改变。源码门禁先红：prompt-render-duration-red.log 一项四个预期断言失败，退出 1；它验证诊断接线，不是设备性能行为测试。prompt-render-duration-verified.log 权威退出 0：51 项零失败零跳过，7.233 秒（墙钟 7.240），含主光标、闪烁、渲染快照、Choo 与退休词检查；原创边界 prompt-render-duration-originality.log 退出 0。

唯一隔离包 ../../work/Typebar-Render-Duration-20261010.app，独立域 app.typebar.qa.renderduration20261010、内存数据；prompt-render-duration-package.log 退出 0。初始 AX 后单键 l，普通时间练习再次失败。prompt-render-duration-runtime.log 首次输入处理 0.000852 秒，之后交付间隔 1.844371 秒、preflight=0.000058、elapsed=1.794059、drift=0.794059、failed=1；实际结果弹窗显示 1/0/0/0 且不保存。全部日志没有 prompt-render-finished：在已启用诊断的这次运行中，没有记录到单次同步完整重建超过 125ms。这反驳“某一次完整重建自身耗时约两秒”，不能排除多个短重建／排版积累、处理器外输入回调、框架或自动化观测影响；也不代表 125ms 内重建足够快，更不能据此确定唯一根因。

结果弹窗保持打开时 ⌘Q，唯一主进程句柄正常退出 0，随后无 Typebar。无 TERM、第二实例或用户偏好数据改动；新增诊断本身可能扰动时序。未重跑全量 readiness 或设备 IME，首次延迟尚未解决，完整 goal 继续 active。

## 首次输入返回后的计时延迟定位（2026-10-10）

被测 96f8c30，唯一隔离包 `../../work/Typebar-Phase-20261010.app`，独立域 app.typebar.qa.phase20261010、内存数据及显式阶段诊断。timer-phase-package.log 退出 0。唯一主进程 PID 34067 两轮普通时间练习，各输入一个正确首字母；同一实例通过再来一次重开，没有第二次启动。

timer-phase-runtime.log 第一轮 input-started=6.675791、input-finished=6.676755，处理时长 0.000967 秒；下一 late-delivery=8.579436、间隔 1.942206 秒、preflight=0.000081、drift=0.903418，failed=1。第二轮 input-started=39.159082、input-finished=39.159725，处理时长 0.000645 秒；下一交付间隔 2.274043 秒、preflight=0.000070、drift=1.198413，failed=1。两轮结果弹窗确认失败且不保存。这反驳“handleInsertedText 同步执行本身耗时约两秒”，但不排除处理器外原生输入、排版、观测或调度影响；未开始时也有迟到记录。两轮间没有 clock-stopped／clock-started，未出现已记录的计时任务重启；没有记录不证明任意生命周期组合。

第二轮同时运行系统 /usr/bin/sample 12 秒，timer-phase-sample-native.log 权威退出 0，timer-phase-main-sample.txt 主线程 9527 个样本，其中 1750 个落在 PromptCaretTimerTarget.tick → PromptCaretNativeView.advance → present → ContentView 的 latestRendering 回调 → renderedPrompt；3495 个落在主循环 mach_msg2_trap。源码对应 PromptCaretNativeView.present 在输入身份变化、needsPosition 或缺少主光标位置时重新请求 rendering，生产回调为完整 renderedPrompt。这个证据将下一步检查聚焦到输入返回后的普通主光标投影／排版路径，不证明所有样本都处于首次延迟窗口，不把聚合占比当作连续耗时或唯一根因。先前每字形主题解析优化没有消除实际失败，不能用绿色测试替代该反例。

第一次裸 sample 命令命中 Anaconda 同名工具，缺少 Python 模块，退出 1；原日志 timer-phase-sample-command.log 保留，随后明确使用系统工具，没有因超时重启采样。最终结果弹窗内 ⌘Q，唯一主进程权威正常退出 0，随后 pgrep 无 Typebar；无 TERM。运行日志保留上一轮 Charts 尺寸回退诊断。本轮仅采证及记录，没有改变产品或阈值，没有重跑全量测试、设备 IME 或全部人工验收，goal 继续 active。

## 结果弹窗实际退出复验与阶段诊断（2026-10-10）

被测提交 7eab44f，唯一隔离包 `../../work/Typebar-Result-Quit-20261010.app`（app.typebar.qa.resultquit20261010），内存数据及独立偏好域。打包日志 result-quit-package.log 退出 0；初始读取后输入一个 c，普通计时练习仍失败。result-quit-runtime.log 记录 deliveryGap=1.849543、preflight=0.000064、drift=0.808253、severe=1、failed=1，并保留 Charts 固定尺寸回退诊断。在失败结果弹窗保持打开时按 ⌘Q，唯一主进程句柄正常退出 0，随后无 Typebar 残留；没有 TERM 或第二实例。这实际验证了失败结果弹窗的快捷键退出修正，不代表菜单退出、成功结果、NoStress、多窗口长测试确认或真实 IME 已验收。

随后增加默认关闭的阶段诊断，仍要求 QA 内存包标志与 TYPEBAR_QA_TIMER_DIAGNOSTICS=1 双重启用。仅写固定阶段标签、相对单调时间、时长及会话状态，不记录输入内容、身份或绝对时间；覆盖计时任务进入／退出、迟到唤醒、首次输入处理进入／退出和较慢处理完成。0.25／0.125 秒只是日志筛选条件，不改变计时健康阈值、100ms 调度或退出保护。输入处理时长包含诊断写入，诊断自身可能扰动时间；它不覆盖处理器之外的全部原生输入／渲染阶段，进程退出也不保证执行任务 defer。尚未在实际 GUI 收集新增阶段记录，不据此声称找到首次延迟根因。

../../work/timer-phase-red.log 为新增 API 缺失编译失败，不是行为反例。timer-phase-verified.log 权威退出 0：55 项零失败零跳过（0.859 秒，墙钟 0.866）；包含阶段格式、双重启用源码门禁与相关计时／结果退出回归。timer-phase-originality.log 退出 0，固定参考 pin 的原创边界通过。源码门禁与组件测试不等于完整 ContentView 或设备证明；本轮未重跑全量 readiness，完整 goal 继续 active。

## 延后观测反证与结果弹窗退出边界（2026-10-10）

被测 81b2f51，构建唯一 Debug 隔离包 `../../work/Typebar-Timer-Observation-20261010.app`，独立域 app.typebar.qa.timerobservation20261010、内存记录／令牌、显式数值诊断。`../../work/timer-observation-package.log` 退出 0。原生输入和应用层代码检查未找到显式睡眠／等待；这不排除隐式框架阻塞。为区分观测扰动，初始 AX 读取后只发送一个 `r` 按键，不立即读取 AX，然后等待同一运行句柄并读取独立 stderr 文件。

`../../work/timer-observation-runtime.log` 在之后读取 AX 之前就有唯一一行：deliveryGap=1.939312、preflight=0.000066、elapsed=1.892334、previous=0、due=1、drift=0.892334、severe=1、failed=1。后续 AX 确认计时失败、1/0/0/0、100% 准确率；它反驳“输入后立即读取 AX 才会失败”，但不排除自动化输入本身或其他运行环境影响。停留及后续退出检查期间文件始终只有一条，实际验证 81b2f51 在这一失败终态不重复交付；其他终态／重开组合仍未全验。首次延迟仍待输入／唤醒阶段计时，未放宽阈值，也未把本次失败当作通过。

同一实例 PID 25939，在结果 sheet 中从应用菜单点 Quit 后，句柄仍活跃、AX 仍为结果 sheet。点击再来一次关闭 sheet，回到未开始练习，再按 ⌘Q 后句柄权威退出 0，随后无 Typebar。没有 TERM、额外启动或真实用户数据改动。该对照定位了结果 sheet 存在与退出被阻的边界；尚不能仅凭对照确定所有 AppKit 内部因果。

本机 Xcode macOS 26.2 SDK 的 `System/Library/Frameworks/AppKit.framework/Headers/NSWindow.h:466–470` 定义 preventsApplicationTerminationWhenModal：模态窗口可阻止应用退出，常规默认 YES，框架创建的窗口可能另有默认；API 自 macOS 10.6 可用，覆盖项目最低 macOS 14。源码完整位置为 `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSWindow.h`。据此新增 ResultSheetTerminationBridge，仅挂在本次 completedResult 的 sheet 内容，设置所属窗口标志为 false；移动、移除或 dismantle 恢复原值。不替换代理、不调用 terminate、不修改长测试注册表或其他 sheet；应用级长测试确认继续由原委托负责。历史结果／其他模态页面不在本次改动内。

会话内决策复核反例包括原值 false、多次更新／移除、移到另一窗口、另一个受保护长测试窗口和生命周期残留。桥无异步 attach，弱引用所属窗口并恢复两种原值；另一窗口标志和保护注册表保持不变。范围内风险复核无其他待修正项，均非独立审计。真实多窗口 Quit、SwiftUI 实际 sheet 后续覆盖属性及修正后菜单／⌘Q 仍需实机验证，不将 SDK 默认解释或组件通过视为原问题已关闭。

`../../work/result-sheet-termination-red.log` 新 API 缺失时编译失败，非动态行为反例；原有实机菜单退出失败为问题证据。`result-sheet-termination-verified.log`：原生属性／迁移／生产接线、长测试关闭／退出、计时、结束优先级及官方挑战共 46 项零失败零跳过，87.190 秒（wall 87.195 秒），退出 0。新增实际不可见 NSHostingView 背景桥之后，`result-sheet-termination-host.log` 四项零失败零跳过，0.235 秒（wall 0.237 秒），退出 0，证明 SwiftUI 挂载与移除确实设置／恢复所属窗口属性；不可见组件不等于实际模态退出。源码核验及行为测试技能促成窄范围、可恢复桥接，没有去掉整应用退出保护。

MANUAL_ACCEPTANCE 新增首次计时、终态交付、本次结果退出及多窗口确认四场景，均待验收；result-sheet-termination-manual-audit.log 确认 1,151 唯一场景结构通过，不替代人工执行。result-sheet-termination-originality-final.log 原创性检查退出 0。完整门禁与修正后主程序未运行；本轮仅上述一个主程序，正常退出且无残留，整体分类不升级，goal active。

## 优化后实机反证与终态时钟入口（2026-10-10）

对 07a4ae6 构建 Debug 隔离包 `../../work/Typebar-Timer-Optimized-20261010.app`（独立域 app.typebar.qa.timeroptimized20261010、内存记录／令牌、诊断显式开启），`../../work/timer-optimized-package.log` 退出 0。唯一实例 PID 23034；未改真实用户偏好、字体、背景或输入源。优化不足以关闭计时缺陷：普通模式两次批量输入及一次单键输入均失败，Tape 按字符模式也失败，全部保留不保存成绩策略。

`../../work/timer-optimized-runtime.log`：第 1 行普通输入 `drift voyage window `，deliveryGap=2.175304、preflight=0.000061、drift=1.151866，实际结果 20/0/0/0、3/3 正确；第 75 行普通输入 `bright amber orchard `，2.606688／0.000057／1.514926，实际结果 21/0/0/0、3/3 正确；第 284 行普通模式首个 `o` 按键，1.982166／0.000065／0.921472，实际结果 1/0/0/0；第 617 行 Tape 输入 `bright marble violet `，2.193193／0.000077／1.152772，实际结果 21/0/0/0、3/3 正确。均 severe=1、failed=1。以上分别为秒级交付间隔、同步预处理秒数及首个到期整秒的延迟；不能再把失败仅归于 Tape 或批量输入。

8 秒普通采样 `../../work/timer-optimized-ordinary-sample.txt` 中主线程 6,334 个样本大部分处于 AppKit 等待（5,737 个 mach_msg2_trap）；12 秒 Tape 采样 `timer-optimized-tape-sample.txt` 仍有刷新投影／渲染工作。这些采样包含输入后及结果阶段，没有阶段标记，不能用整体样本分布排除短暂主线程阻塞或证明调度器根因，也不能据不同采样时长报告提速比例。下一步需进一步区分实际计时唤醒、输入处理与系统／自动化环境，而不是改变安全阈值。未验真实 IME。

记录还重复证明终态生命周期问题：失败后 previous=0、due=1、冻结 elapsed 和 failed=1 持续出现。原生 `session.isFinished` 覆盖 completed／failed／invalidAFK／abandoned／bailedOut；新增 advanceClock 终态返回，位于本机规则／Caps Lock／字体监测之后、elapsed／整秒交付／健康观察／诊断／警示音／阈值／tick 之前。保持本机监测，阻止冻结会话重复交付，不修改首次回调、重开归零、时钟来源或保护阈值。固定参考 test-timer.clear 将 stopped 设为 true 并清除 timeout，本次符合停止后不继续交付的生命周期。

新生产源码接线门禁在 `../../work/timer-terminal-entry-red.log` 一项预期失败（终态 guard 缺失），不是动态 GUI 反例。`timer-terminal-entry-verified.log`：诊断、elapsed clock、Slow Timer、健康阈值、整秒策略、结束优先级和渲染快照共 49 项零失败零跳过，0.825 秒（wall 0.832 秒），退出 0；`timer-terminal-entry-originality.log` 原创性退出 0。范围内风险复核确认终态范围和监测顺序，无其他待修正项，非独立审计；尚未对修正后的主程序确认日志停止，也未重跑完整门禁。

本轮只启动上述一个实例，四轮对照在同一进程内完成。退出快捷键后仍存在，仅向已核验确切 PID 23034 发送 TERM，运行句柄权威退出 143，随后无 Typebar；未再次启动。首次计时延迟、退出快捷键行为及实际设备仍待定位／验证，整体兼容分类不升级，goal active。

## 实机诊断对照与渲染热路径增量（2026-10-10）

被测 b86125a，以 `../../work/Typebar-Timer-Diagnostic-20261010.app` 独立域 app.typebar.qa.timer20261010、内存记录／令牌及显式 TYPEBAR_QA_TIMER_DIAGNOSTICS=1 直接运行唯一实例 PID 19526。打包日志 `../../work/timer-gui-package.log` 退出 0；默认 swift build 为 Debug，不推断 Release 性能。启动前无 Typebar；本轮未修改用户域偏好、字体、背景或输入源。

普通模式输入 `meadow tangent willow `，实际结果为计时失败、3/3 单词正确、22/0/0/0、100% 准确率。`../../work/timer-gui-runtime.log` 首行：deliveryGap=2.721748、preflight=0.000065、elapsed=2.656103、due=1、drift=1.656103、failed=1。由此排除“仅 Tape 才触发”的假设，且本次同步预处理不解释秒级间隔。普通模式失败后继续出现 78 条检查记录，显示终态仍被时钟循环检查；这是后续需处理的生命周期问题，不在本增量中隐式修改。

同一实例点击再来一次，通过真实设置窗口将卷带改为按字符，再输入 `lantern window copper ` 和稍后的 `pocket marble paper `。日志第 79 行起为该轮：首两个回调间隔 1.345796／1.071246 秒、drift 0.345289／0.416546、severe=2、failed=0；随后整秒检查直到 30 秒共 30 条，没有 failed=1。实际结束页为末尾持续闲置无效、6/6 单词正确、42/0/0/0、100% 准确率、30 秒，不保存成绩。它证明这一轮没有计时失败，不等于合格练习或原有失败已修复；未操作真实 IME。

`../../work/timer-gui-sample.txt` 是上述 Tape 运行中 5 秒采样；主线程 3,711 个样本中 1,823 个处于 Tape 定时呈现，1,555 个进入 refreshProjection，其中可见逐字符 renderGlyph 经 futurePromptColor／promptTextColor 反复解析 ThemePreviewPresentation。这是重复工作的直接栈证据，但采样发生在后续 Tape 轮次，不能证明普通模式首次 2.72 秒间隔的根因。退出快捷键后仍有进程，仅向已核验确切 PID 19526 发送 TERM；运行句柄权威退出 143，随后无 Typebar 进程。未再次启动应用。

据热路径证据，将主题、完成／未来／错误／额外颜色、独立光标策略及所需节奏索引提升到每次同步 renderedPrompt 调用的局部值；两个兼容光标绘制函数显式接收同一主题。不缓存到下一次 render，不更改角色规则、遮挡顺序、组合投影、布局、计时阈值或失败策略。新增生产接线源码门禁 `PromptRenderSnapshotTests`，`../../work/prompt-render-snapshot-red.log` 一项九处预期断言失败；这是静态重复求值防回归，不冒称可执行性能或实际属性验证。既有听写遮挡顺序门禁只更新调用签名，顺序断言保留。

`../../work/prompt-render-snapshot-verified.log`：Tape、组合渲染、特殊光标、单词外观、主题预览、文字色策略和诊断共 263 项零失败零跳过，25.611 秒（wall 25.641 秒），退出 0。`prompt-render-snapshot-originality.log` 原创性检查退出 0。范围内风险复核确认局部主题每次重算、两个光标与错误提示沿用原规则，无其他待修正项，非独立审计。未对优化后的主程序做 GUI 或性能复验，不能报告提速幅度或关闭计时缺陷；完整门禁未为本增量重跑，整体分类不升级，goal active。

## 计时失败诊断准备（2026-10-10）

已追踪实际入口 `runClock → advanceClock → TimerHealthState.observe → failForTimerHealth`。固定参考 `frontend/src/ts/test/test-timer.ts:319` 的短测试范围、125／250／500 ms 和严重延迟超过五次边界与当前策略一致。上轮失败只有最终界面证据，不能据此判断是主线程调度、同步预处理、Tape 渲染还是自动化环境造成。

新增 timing-only 诊断：仅 Info.plist 的 TypebarQAInMemoryStore 为 true 且进程环境 TYPEBAR_QA_TIMER_DIAGNOSTICS=1 时，整秒到期检查后向 stderr 输出一行。字段为相邻回调入口的 uptime 间隔（包含上一轮处理和睡眠／调度）、当前同步规则／Caps Lock／字体检查耗时、会话 elapsed、上一已交付整秒、首个到期整秒、drift、严重延迟计数和失败位。不记录输入、提示、账户、日历时间或成绩载荷；普通包即使设置环境开关也不输出。记录在诊断写入前完成；stderr 输出自身可能影响后续调度，不能把带诊断运行当成无扰动性能基准。未修改阈值、失败／保存策略或时钟采样来源。

`../../work/timer-diagnostics-red.log` 为两个新测试在 API 缺失时编译失败，不冒称计时缺陷的行为反例。`timer-diagnostics-verified.log` 首轮 31 项零失败、1 项因缺少参考路径跳过。提供参考路径与 Anime.js 归档后的 `timer-diagnostics-final.log`：Tape、诊断、elapsed clock、Slow Timer、健康阈值与整秒策略共 224 项零失败零跳过，25.486 秒（wall 25.513 秒），进程退出 0；`timer-diagnostics-originality.log` 检查退出 0。新增测试验证双重开关以及固定数值记录格式；不证明实际 ContentView 输出已观察。

本轮零主程序启动，未采集新的实际运行诊断，也未修复／关闭上一节实际验收失败。范围内风险复核检查开关、内容与调用顺序，无新增待修正项，非独立审计。下一次只启动一个独立内存验收包，显式开关并捕获 stderr，再以普通／Tape 对照定位。完整门禁未为本诊断增量重跑，整体兼容分类不升级，goal active。

## 实际应用入口验收未通过（2026-10-10）

对 f3f988d 构建单独验收包 `../../work/Typebar-Tape-GUI-20261010.app`，Bundle ID 为 app.typebar.qa.tape20261010，TypebarQAInMemoryStore 为 true；SwiftData 和账户令牌使用内存，默认偏好使用独立应用域。未导入、删除或修改共享本机字体／背景。打包日志 `../../work/tape-gui-package-20261010.log` 退出 0。本轮仅启动一个主程序，启动前无 Typebar 进程。

通过真实设置窗口把“单行卷带”从关闭改为按字符，关闭设置返回 ContentView。提示以 `pocket willow voyage` 开头，向 Typing input 输入 `pocket willow voyage `。实际结果窗口报告“计时调度持续延迟，为避免不准确的成绩已停止测试”，显示 3/3 单词正确、21/0/0/0 UTF-16 单位、100% 准确率、2 秒、134 WPM，并明确不保存成绩。无障碍树和屏幕观察一致。这是验收失败记录，不能以正确字符计数替代通过结论；尚未定位为 Tape 渲染、计时策略还是自动化／运行环境的影响，不推断根因，也不放宽保护条件。

未操作真实 IME，未验证候选组合、混合方向或长程退休队列。退出快捷键后进程仍存在，对本轮创建的确切 PID 14630 发送 TERM 清理；不得扩大到其他用户实例。后续应先复现并定位调度延迟，再继续入口验收。整体功能分类不升级，goal active。

## 已确认退休前缀隔离增量（2026-10-10）

configure 在最新候选选择后、修改布局之前检查最终有效退休上下文：同一 owner attempt／上下文 attempt 的 firstRetainedWordIndex 不得低于已接纳值。先选择快照再检查，允许有效新快照替换旧 representable 参数；新 attempt 可以从 0 重新开始。检查不要求异步 session 确认追上原生提前移除的全部前缀，也不改通知或退休状态机。

新增真实 session 先确认前缀 1，再依次提交无 provider 的旧参数、旧完整快照、由新快照替换的旧参数，以及新 attempt。检查实际文字、Tape 位移、主光标和重开归零。`../../work/tape-ack-prefix-red.log` 单项四处失败，旧参数重新放回前缀并将位移从 -138.46875 改成 -207.703125；修正后 verified.log 193 项零失败。补齐新 attempt 边界后的最终 `../../work/tape-ack-prefix-final.log` 193 项零失败零跳过，24.961 秒（wall 24.984 秒），进程退出 0。verified.log 使用同一 tape-ack-prefix- 前缀；`../../work/tape-ack-prefix-originality.log` 原创性检查退出 0。

本轮范围内差异审查未发现其他待修正项；构造配置交错不等于真实 SwiftUI 调度／IME 验收。零主程序启动，无新截图；完整冻结门禁未为本增量重跑，下方完整门禁明确对应此前 19d0c48。更多多行／平滑／隐藏标记／方向／队列组合、策略变更时未确认移除与真实设备仍开放，整体兼容分类不升级，完整 goal active。

## 应用入口完整冻结复验（2026-10-10）

被测原生提交 `19d0c4864105e9c1a0f437c1f6173f90bbbc7b62`。完整脚本 `Scripts/check-native-rewrite-readiness.sh` 的复验会话 94063 权威退出 0；证据目录 `../../work/tape-production-readiness-retry.5Ip2sJ/` 保留 gate.log、826 文件 inputs.sha256、多次运行中校验、freeze-terminal.log 及 logs/ 下 74 份日志。运行中不修改输入；终态 826 项全部校验通过，原生和参考工作树干净，参考 pin 仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。

原生 client-tests.log：4,138 项零失败零跳过，878.757 秒（wall 879.234 秒）；服务 service-tests.log：501 项零失败零跳过，11.830 秒（wall 11.891 秒）。固定源行为探针、16 磁盘迁移相关验证及历史 writer 准备、未打开应用的打包／签名／资源边界／原创性通过。零主程序启动，终态无 Typebar 主程序、相关测试或 Swift 编译残留。日志保留 Core Data／XPC 和只读存储诊断，不将“测试通过”写成“无诊断”。

首轮会话 6300 已退出 1，证据 `../../work/tape-production-readiness.uziUE7/`：周 XP 探针要求 Redis 6.2.6，但默认 PATH 得到 8.6.1，尚未执行全套测试。该轮输入校验终态一致，失败日志保留。核验已有 `../../work/typebar-qa-runtime/redis-6.2.6/src/redis-server` 的版本后，仅通过新门禁进程 TYPEBAR_SOURCE_REDIS_SERVER 指定它；先单独周 XP 源探针通过（redis-recovery.log），再新目录完整复验。未替换系统 Redis、未放宽版本断言、未覆盖旧日志，也未并发重启仍活跃的会话。

53 表面、239 原生键盘布局、94 配置（89 映射／4 部分／1 不适用）、446 独立语言、187 主题身份、57 映射加 1 待映射挑战与 1,147 人工场景结构审计通过。主题精确原生映射仍 0／187（49 相关原创替代、138 无相关替代）；人工场景未执行。本轮无新截图，不把模型／源码／组件回归当作实际 ContentView 输入、混合方向、连接塑形视觉或 IME 实机验收。复杂旧配置／确认队列交错、策略变更时未确认移除及完整方向边界仍开放，功能分类不升级。

本节替代下方阶段记录中“完整门禁待复验／未重跑”的当前状态，不抹去其历史失败与局部证据，也不将完整门禁通过等同完整重写目标完成。完整 goal active。

## 应用投影入口启用增量（2026-10-10）

renderedPrompt 的 usesCompositionProjection 移除 `!usesTapePractice`；composition 非 nil 及既有方向条件保持不变。已有 Tape 字段、双光标、退休、完整新鲜快照、首次配置和连接塑形适配器现在可由应用渲染路径使用。混合方向回退尚未解决，不将它隐式移除；整体目标范围不变。

新增源码门禁测试，检查 Tape 排除消失且 composition／方向条件保留。`../../work/tape-production-gate-red.log` 单项一处预期失败；启用后 `../../work/tape-production-gate-verified.log` 318 项零失败零跳过，28.059 秒（wall 28.095 秒），进程退出 0，筛选为 Tape／ASLPromptComposition／ChooPromptComposition／CompositionProjection／PromptComposition／PromptField。`../../work/tape-production-gate-originality.log` 原创性检查退出 0。

本轮有限会话内决策审查（非独立评审）检查首次新鲜事务、旧 attempt／stop、canonical pace、字段退休、连接策略和旧方向回退。决定启用已接通的适配器，不将源码条件测试冒充实际 ContentView 全流程；已有真实宿主／原生组件回归支持桥接和几何，但应用实际输入操作与 IME 仍缺证据。新旧 representable／确认队列交错、策略改变时未确认移除、混合方向及设备是待验风险。完整冻结门禁待复验，整体功能兼容分类不升级。

零主程序启动，无新截图。下方历史章节“应用保护未解除”是此前阶段状态；本节只替代该入口状态，不撤销其余未完成项。完整 goal active。

## 连接文字策略增量（2026-10-10）

Tape 投影此前默认逐槽排版，未传共享字段布局已有的 joinsLetters。现在该参数从 session 的 usesJoiningScriptPrompt 经 TapePracticePrompt／桥接传入 owner；单行 PromptFieldTextLayout 与多行每字段词盒都使用该策略。多行布局变更检测及复用检查纳入策略，owner 变化触发重配置；同字段刷新、完整事务刷新和前缀重建保留参数，newlineSource 保存它。默认 false 保持既有调用兼容，不引入新的字体或上游资产。

新增阿拉伯文 `سلام\nمرحبا نهاية` 及固定 `لام` 候选：先确认共享布局连接／分离宽度差异超过 1 点，使反例确实区分塑形；同一多行布局 false／true／false／true 切换，比较实际字段宽度。实际 RTL owner 同样切换，检查 outline 主光标宽度、右边距锁定及接受推进。对照复用同一原生字段布局，证明参数和几何接线，不独立证明 TextKit 本身或与上游的像素等价。

`../../work/tape-joining-red.log` 保留缺少新参数的预期编译失败；`../../work/tape-joining-first.log` 专项一项零失败，0.087 秒（wall 0.089 秒）。加入实际 owner 检查后 `../../work/tape-joining-verified.log` 191 项零失败零跳过，24.861 秒（wall 24.884 秒），进程退出 0；`../../work/tape-joining-originality.log` 原创性检查退出 0。

零主程序启动，无新截图；不是视觉或实机输入法验收。单行连接候选的完整组合、独立 pace／退休交错、混合方向、策略改变时未确认移除队列、应用渲染保护与真实设备仍开放。完整冻结门禁未重跑，整体功能分类不升级，完整 goal active。

## 首次完整投影事务增量（2026-10-10）

configure 的首次 provider 读取现在区分完整事务和旧三字段同字段快照。完整事务检查 attempt、元数据成对、活动 map／词目录、传入退休前缀不回退与同 attempt 原生保留字段边界；同步替换字段、渲染、换行描述、退休上下文和主 glyph ID，再执行既有配置流程。旧快照仍按同字段／单行限制接受。provider 返回后比较 retirementRevision，stop 或重配置使外层事务中止。

新增初次读取后 provider 即不可用的反例：传入旧字段 0，唯一可用快照已跨行；检查配置结束后的新文字、接受推进和主光标纵坐标。另在初次 provider 内 stop，确认随后 present 不再读取。`../../work/tape-initial-transaction-red.log` 保留测试中负号与 try 的语法错误；修正后 `red-verified.log` 单项三处行为失败，旧行纵坐标 0 对新行 45。产品修复后 `verified.log` 回归通过；加入原生保留字段检查和停止断言后的最终 `../../work/tape-initial-transaction-final.log` 190 项零失败零跳过，24.827 秒（wall 24.850 秒），进程退出 0。上述 red-verified.log／verified.log 均使用相同 tape-initial-transaction- 前缀。`../../work/tape-initial-transaction-originality.log` 原创性检查退出 0。

零主程序启动，无新增截图；应用投影渲染保护未解除，复杂旧 representable／确认元数据交错、更多重入与队列组合、方向／连接塑形和真实 IME 仍开放。完整冻结门禁未重跑，功能分类不升级，完整 goal active。

## 应用快照构造增量（2026-10-10）

TapePromptProjection.snapshot 从传入的同一 session 值绑定输入身份、原始字段、最终渲染、按 Zen／声明换行／生成换行选择的拓扑和退休上下文。拒绝 attempt 不匹配、退休前缀不一致、缺少活动字段 map 或退休词目录。构造器不重新读取 live session；调用者负责用同一捕获值生成 rendering，字段存在检查不能证明任意外部 rendering 的新鲜性。

应用 TapePracticePrompt 调用加入 latestProjection：捕获 session 与 compositionText，渲染该捕获值，并显式传入 practiceLineScrollContext。辅助函数新增可选捕获 session 参数，旧调用默认读取当前状态；两条退休回调明确写 self.session，不修改捕获副本。应用 `!usesTapePractice` 投影渲染保护尚未解除，当前 provider 在无 map 时拒绝构造；因此不能声称应用用户路径已经启用投影。

新增单行／多行两场景，验证输入、候选、活动字段、canonical caret、拓扑与退休元数据，拒绝旧 attempt、前缀不一致及无 map。`../../work/tape-session-snapshot-red.log` 保留缺接口编译失败；`verified.log` 初版 189 项零失败，24.651 秒（wall 24.673 秒）。显式捕获后 `captured.log` 因局部 let session 遮蔽应用状态导致回调编译失败；明确 self.session 后最终 `../../work/tape-session-snapshot-final.log` 189 项零失败零跳过，24.892 秒（wall 24.914 秒），进程退出 0。上述 verified.log／captured.log 均使用相同 tape-session-snapshot- 前缀。`../../work/tape-session-snapshot-originality.log` 原创性检查退出 0。

零主程序启动，无新增截图。应用 provider 仅编译接通，构造器行为有测试，但应用实际用户流程未验；初始新鲜配置、入口启用、方向／连接塑形、复杂队列和真实 IME 仍开放。完整冻结门禁未重跑，整体兼容分类不升级，完整 goal active。

## 单行退休字段身份增量（2026-10-10）

prepareRetirement 在字段投影路径使用 compositionField.index 作为活动索引；旧非投影路径继续通过上下文 glyph ID 查找。此前投影词框虽按字段索引读取，活动字段仍依赖 glyph ID，共享 ID 时错认首词并漏发前缀移除。改动不新增退休状态机，也不改通知／补偿规则。

既有跨词退休测试增加共享上下文 glyph ID 维度，共方向 × letter／word × 旧偏移目录有无 × 独立／共享 ID 十六组合；检查实际移除、确认后的主光标稳定、一次补偿与重复确认。共享 ID 是主动构造边界，不是实际部分 canonical 字素或 IME 可达性证明。`../../work/tape-single-field-identity-red.log` 单项八处漏通知失败；修复后 `../../work/tape-single-field-identity-verified.log` 188 项零失败零跳过，24.597 秒（wall 24.620 秒），进程退出 0。`../../work/tape-single-field-identity-originality.log` 原创性检查退出 0；范围内差异审查无其他待修正项。

零主程序启动，无新增截图；应用实时 snapshot 构造、入口启用、初始新鲜配置、复杂队列、连接塑形／方向和真实设备仍开放。完整冻结门禁未重跑，整体兼容分类不升级，完整 goal active。

## SwiftUI 投影桥接增量（2026-10-10）

TapePracticePrompt 与私有 TapePromptBridge 传递 compositionField、hidesCompositionExtras 和 latestProjection。session 初始化器仅在 rendering 含 map 时绑定实际字段，从 session 读取 hideExtraLetters，provider 默认 nil；旧调用保留默认值和旧布局。没有改动应用层 `!usesTapePractice` 渲染保护，也没有声称用户已能通过应用入口使用该功能。

新增真实 NSHostingView 测试：跨行已提交输入加 emoji 候选，比较实际高度、接受推进、主光标宽度与纵坐标；随后只替换 provider 返回快照为中文候选，保持 SwiftUI 模型不变，确认实际 owner 一次读取和新文字。NSWindow 不显示且关闭，owner stop；无主程序启动，无新增截图。参照量测明确传入 compositionMap。

`../../work/tape-bridge-field-red.log` 单项两处失败，分别为旧布局高度 138 对投影 135、光标纵坐标 46 对 45；传递显式字段后 `../../work/tape-bridge-field-first.log` 单项零失败，0.203 秒（wall 0.205 秒）。加入 provider 桥接断言后的 `../../work/tape-bridge-field-verified.log` 188 项零失败零跳过，24.772 秒（wall 24.794 秒），进程退出 0。`../../work/tape-bridge-field-originality.log` 原创性检查退出 0；差异审查未发现本轮范围内待修正的问题。

这只证明桥接接线与固定 LTR／letter 场景；应用调用的实时 snapshot 构造、Tape 退休上下文身份、初始新鲜配置、多方向／连接塑形、复杂队列和实际 IME 仍开放。完整冻结门禁未重跑，功能分类不升级，完整 goal active。

## 完整事务的独立 pace 验证（2026-10-10）

完整快照测试抽取共享场景并新增独立 `requestPacePosition(fromDeadline: true)` 路径：在不更新 representable 的跨字段输入后依次切换 emoji／空／中文候选，验证单次 provider 读取、最新文字、接受推进、canonical pace 目标横纵坐标，以及 deadline 不改变主光标。随后正常 present 验证主光标纵坐标；既有无效快照／停止边界仍执行。配置为 LTR、letter、关闭动效，不外推到平滑／RTL／混合方向／实际 IME。

初次 `../../work/tape-complete-pace-first.log` 七项三处横坐标失败；参照布局只 configure／量测，未执行 requestProjectedScroll，所以没有更新 Return filler 缩进。补上与 owner 相同的滚动请求后 `../../work/tape-complete-pace-flow.log` 单项零失败（0.136 秒，wall 0.137 秒），产品代码未修改，不将该失败记为产品缺陷。最终 `../../work/tape-complete-pace-verified.log` 187 项零失败零跳过，24.349 秒（wall 24.372 秒），进程退出 0；`../../work/tape-complete-pace-originality.log` 原创性检查退出 0。

本轮仅测试和证据文档，零主程序启动，无新增截图；应用层保护未解除，初始配置选择、复杂队列、连接塑形与方向、实机验收仍开放。完整冻结门禁未重跑，整体功能兼容分类不升级，完整 goal active。

## 完整实时投影事务增量（2026-10-10）

TapePromptProjectionSnapshot 可同时携带换行词描述与退休上下文；两者缺一即拒绝，旧三字段快照保留仅同字段刷新规则。原生 owner 以同一输入／字段／文字／拓扑事务调用既有 configure，允许跨字段，不另建滚动或退休状态机。验证 attempt、活动字段存在、退休前缀不回退，并在 provider 返回后重新验证停止／配置身份；未变化快照不重新配置，避免无谓取消待执行事务。光标读取缓存覆盖多行投影，最新文字通过已有 rendering provider 提供，不修改只读光标配置文本。

新增实际 owner 测试以 `a\nbc tail` 跨字段输入后直接 present，依次切换 emoji 候选、空候选和中文候选，检查单次读取、实际文字、接受推进和主光标纵坐标；另拒绝旧 attempt、单边元数据及与结构换行不符的空拓扑，验证 provider 中 stop 后不再读取。该测试关闭 pace，不构成独立 pace 完整事务或实际输入法验收。

证据：`../../work/tape-transaction-snapshot-red.log` 保留缺少新初始化参数的编译失败，`first.log` 保留只读配置文本的编译失败；`config-fixed.log` 单项零失败。最终 `../../work/tape-transaction-snapshot-verified.log` 186 项零失败零跳过，24.519 秒（wall 24.541 秒），进程退出 0；`../../work/tape-transaction-snapshot-originality.log` 原创性检查退出 0。上述 first.log／config-fixed.log 均使用相同 tape-transaction-snapshot- 前缀。

本轮零主程序启动、无新增截图。应用层 `!usesTapePractice` 保护未解除；初始配置的新鲜多行快照选择、独立 pace 的完整事务、复杂队列、连接／混合方向和真实 IME 仍开放。完整冻结门禁未重跑，兼容分类不升级，完整 goal active。

## 多行投影字段身份与 filler 隔离增量（2026-10-10）

多行投影 owner 的跨词判定、活动词框、纵向退休边界和完成时活动字段保护改用 compositionField.index；canonical glyph ID 不再充当字段唯一身份。前缀纯确认也要求字段索引不变。TapeNewlineTextLayout 的 precedingBreak、存活 filler 过滤、动画 channel、重排及计划请求统一按稳定词／字段索引存储；canonical alias 仍仅负责字形关联。旧非投影 owner 的字符查找逻辑保留。

退休测试扩展为方向 × 动效 × 确认／停止 × 退休上下文共享／独立 glyph ID，共十六组合；另新增 Return 描述共享 ID 的 filler 隔离测试，对照独立 ID 在 0／60／125ms 的真实字段框。两者主动构造身份冲突，不是实际 IME 或共享 canonical 字素的可达性证明。`../../work/tape-field-identity-red.log` 一项六处失败，修复字段事务后 verified.log 184 项仍有一次异步退休通知缺失；加入组合标签后的 diagnostic.log 单项未复现。原测试只运行主队列 2ms，而产品回调没有该时限约定，故改为等待实际事件（1 秒上限），没有改产品通知或重试。那次失败的具体触发原因仍未证明，不宣称已确定根因。

`../../work/tape-filler-identity-red.log` 一项八处失败准确暴露 filler 通道合并；修复后 `../../work/tape-field-identity-final.log` 185 项 Tape 相关回归零失败零跳过（24.334 秒，墙钟 24.356 秒），originality.log 通过（同目录 tape-field-identity- 前缀）。行为先行、有界会话内三轮决策／风险检查及根因排查为本会话工作，不是独立审计。零 Typebar 主程序启动、终态零测试／编译残留，无新图或完整门禁复跑。

真实部分字素字段、其余仍使用 canonical 词身份的路径、复杂异步队列、实际 RTL／连接塑形、多行／跨词实时快照、生产入口和 IME／设备仍开放；通知失败保留为待观察证据。应用保护、配置与整体兼容分类不升级，goal active。

## 多行投影纵向退休事务增量（2026-10-10）

跨行检测改为通过退休上下文的词身份读取真实投影字段框，不再要求旧字符偏移。原生前缀移除按存活字段框与已展示 leading edge 计算补偿；newlineSource 保留 compositionMap，在退休后的原生重建中继续使用投影词盒，避免退回旧 Character 目录。原有首跳策略、独立横纵动画与异步通知 revision 保护保持。

新增真实 session／owner 测试主动清空旧偏移目录，使用候选溢出与 emoji；方向 × 即时／平滑 × 确认／停止共八组合覆盖纵向退休、主／pace 位置、重复确认不补偿两次，以及停止取消未完成或已排队的通知。`../../work/tape-projected-retirement-red.log` 一项六处失败，暴露缺失纵向移动及退休；first.log 修复后一项通过，verified.log 最终 184 项 Tape 相关回归零失败零跳过（24.363 秒，墙钟 24.385 秒），固定源／动画环境齐备；originality.log 通过。上述四份日志均在同目录、使用 tape-projected-retirement- 前缀。

行为先行、有界会话内决策与风险复核关注跨行几何、投影保存及取消，不是独立审计。零 Typebar 主程序启动、终态零测试／编译残留，本增量无新持久组件图或完整门禁复跑。测试使用 Latin 改流方向，实际 RTL 文字／混合方向、共享 canonical ID 的部分字段、复杂重叠队列与像素级退休等价仍需证据；多行实时快照、完整生产入口、IME／设备仍开放。应用保护与整体兼容分类不升级，goal active；下方“纵向退休未接线”为此前阶段状态。

## 多行投影 owner 与双光标几何增量（2026-10-10）

显式 compositionField 与 newlineWords 配置现在让实际 TapePromptNativeView 的文字层使用持久流投影词盒；layout 类型切换纳入 reset。横向请求按真实字段索引、raw UTF-16 接受数和隐藏 extras 读取新入口；活动词保护使用字段索引，不由旧字符锚点猜测。主光标使用字段内最终 before／after，letter 锁定边距，word 按字段前缘定位；独立 pace 使用 canonical 首／末 alias 加实际文字 origin。新增只读 projectedAdvance 用复制的流预览，不修改真实移除状态或动画。没有新增时钟。

新增实际 owner 测试主动清空旧 glyphCharacterOffsets，保留真实会话的字段投影与原始词描述；方向 × letter／word 四组合验证文字 margin、主光标 x／y 与 canonical pace x／y。该反例不代表真实 IME 必然产生空目录。`../../work/tape-multiline-owner-red.log` 一项两处失败（推进及缺失主光标），first.log 三项通过，verified.log 183 项零失败零跳过（均为同目录 tape-multiline-owner- 前缀）。持久 `../../work/tape-multiline-owner.EIrmj0/` 的 final.log 183 项零失败零跳过（24.234 秒，墙钟 24.256 秒），四张 tape-multiline-owner-{ltr,rtl}-{letter,word}.png 已逐张查看，originality.log 通过。不可见窗口关闭、零主程序启动，终态零测试／编译残留。

行为先行、有界会话内决策与风险复核关注几何身份和活动字段保护，不是独立审计。测试使用 Latin 内容改变流方向，不能证明 Hebrew／Arabic、连接塑形或混合方向等价。仅接通固定配置快照；多行 latestProjection 刷新尚未接入，纵向退休仍需字段索引与保留投影 map 的完整事务迁移，不能据此解除应用入口保护。实际 IME／设备、跨词实时事务、匿名行及完整门禁仍待验证，配置／整体兼容分类不升级，goal active。下方“主 owner 尚未接线”为此前阶段状态。

## 多行持久流投影词盒增量（2026-10-10）

TapeNewlineTextLayout 增加显式 compositionMap 入口，在现有 TapeNewlineFlow 内按字段索引建立独立原生槽盒；不把虚拟候选槽转换成旧 Character offset。字段盒去除提交 gap、关闭普通段落的结构换行，Return 拓扑仍由原有描述与持久流拥有；native 文字绘制使用同一投影盒。增加字段框、opaque cell 框、canonical 首／末 alias 框及按 raw UTF-16 接受数请求滚动的入口，推进继续复用隐藏 extras／零宽槽规则。旧入口默认 nil 保持原路径。字段一次分组，未变化文字盒复用，不加入新时钟。

两项新增验证实际 session 的候选溢出／emoji 虚拟槽、两种流方向、接受推进与候选末端隔离、缺失身份返回 nil、canonical alias，以及横向移除 Return 词后多次候选重建不会复活词或丢失结构行。两张不可见测试画布组件图已逐张查看，窗口均关闭；测试使用 Latin 内容切流方向，不据此声称真实 Hebrew／Arabic 或混合方向塑形完成。主／pace owner 与纵向退休尚未使用新入口，应用层保护未解除。

`../../work/tape-multiline-projection-red.log` 为缺失接口的预期编译失败；first.log 暴露嵌套词盒遗漏主线程隔离，actor-fixed.log 一项通过（均为同目录 tape-multiline-projection- 前缀）。持久 `../../work/tape-multiline-projection.fJbDTk/` 的 verified.log 50 项通过，分组／复用与 alias 验证后 final.log 80 项零失败零跳过（8.953 秒，墙钟 8.963 秒），固定源与动画归档齐备，originality.log 通过。行为先行、有界会话内决策与风险复核关注结构所有权、候选重建和二次复杂度，不是独立审计。

零 Typebar 主程序启动、终态零测试／编译残留，无完整门禁复跑。多行 owner 接线、主 after／独立 pace、行跳与前缀确认事务、匿名结构行、连接塑形／混合方向、跨词实时快照与实机仍开放。此为实际持久流组件的实现增量，不是完整生产功能；配置／整体兼容分类不升级，goal active。

## 多行投影迁移前基线与所有权（2026-10-10）

在 `f6d6cf596c47f1e5dca49f7ddc96cc22a0773e7d` 实测 TapeNewlineLayoutTests、TapeNewlineFlowTests、TapeNewlineTransitionTests、TapeNewlinePrefixTests、TapeWordVisibilityTests：37 项零失败零跳过（8.115 秒，墙钟 8.120 秒），固定参考与 animejs 4.2.2 归档齐备；证据 `../../work/tape-multiline-baseline.log`。零主程序启动、终态零测试／编译残留。仅建立迁移基线，未实现多行组合投影。

有界会话内决策复核核对固定原版 test-ui.ts 的完整 scrollTape（958–1161）及原生 TapeNewlineTextLayout／TapeNewlineFlow。不可替换的行为是：根据已展示框移除词；保留词移除后的三个 Return 结构节点；清理 leading afterNewline 时只补偿最后一个 filler；只访问活动词之后至多两个 filler，三倍视口封顶；对存活 filler 与主／pace 同步补偿；横向通道 125ms 且不接管独立纵向退休。普通 PromptFieldTextLayout 的段落排版不包含这些持久状态，不能直接作为多行 Tape 的整个 owner。

后续修改点应是现有持久流内的 Word 原生盒和身份查找：最终字段槽／opaque cell ID 用于文字、主 after 与 canonical pace；真实字段索引用于词框与拓扑；raw UTF-16 接受单位用于 letter 推进；旧 Character offset 仅留旧路径。不得由拼接文字拆词，也不得把候选末端算成接受推进。必须用实际候选溢出／跨字段融合、Return 后 extras、隐藏额外槽、同向 RTL、前缀确认与重复／取消反例验证。匿名结构行、多个 Return 的可达性、连接塑形、混合方向和跨词快照事务仍需额外证据；本决策不是独立审计，也未解除应用层保护。

## 单行投影跨词前缀移除增量（2026-10-10）

后续身份隔离反例主动清空旧 glyphCharacterOffsets、保留真实 session 的完整 compositionTextMap，扩展为方向 × 模式 × 有无旧偏移八组合；这不是实际 IME 产生该快照的证明。`../../work/tape-prefix-identity-red.log` 一项十二处断言失败，暴露前缀确认仍被旧偏移准入阻挡，累计补偿为零且重复通知。现将投影补偿完全按字段身份读取，缺失投影字段返回未知，不回退借用旧字符框；只有非投影路径读取旧偏移。verified.log 59 项零失败零跳过（4.619 秒，墙钟 4.626 秒），originality.log 通过，三份日志均以 tape-prefix-identity- 为前缀。行为先行、有界决策和风险复核为本会话检查，无独立审计；零主程序启动、终态零残留，无新增图或完整门禁复跑。

固定源码 scrollTape 使用最后已展示的位置判断离屏词，而不是下一动画目标。原生投影 owner 原先仍向未准备的旧 Character 目录读取词框，导致单行跨词不移除前缀；现改为实际 projectedLayout.fieldFrames[word.index]，确认前缀时以旧字段的真实前缘计算有符号补偿。旧字符路径保持原逻辑，缺失投影字段不借用旧词框。未改输入、计分、回放、异步通知取消机制或时钟。

新增真实 session／owner 测试覆盖 LTR／RTL、letter／word 四组合：第 2 词跳第 3 词只移除完全离屏的第 0 词；确认后主光标不跳、文字 margin 与累计补偿方向正确；重复确认不重复通知或补偿。`../../work/tape-projection-retirement-red.log` 保留测试字段属性名编译错误，red-verified.log 修正后两方向均失败（缺失移除通知），first.log 修复后一项通过，verified.log 扩大 59 项零失败零跳过（4.455 秒，墙钟 4.463 秒）。这些日志均使用 tape-projection-retirement- 前缀；originality.log 原创性检查通过。

行为先行和有界会话内决策／风险复核重点为展示坐标、RTL 补偿和重复确认，不是独立审计。零 Typebar 主程序启动、终态零测试／编译残留，无新增持久组件图。完整门禁未为此增量重跑；下方 4,125 项属于修改前冻结版本。应用层保护、跨词实时快照、多行拓扑／退休事务、部分 canonical 关联及混合方向／连接塑形／实机仍开放，兼容分类不升级，goal active。

## Tape 投影完整冻结复验（2026-10-10）

对原生提交 `c23523d77f7cec2e1b6ed95cbcf87db6d5a19f3c`、固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的唯一完整门禁会话 20569 已明确退出 0；没有因日志缓冲重复启动。原生 4,125 项零失败（876.373 秒，墙钟 876.934 秒），自托管服务 501 项零失败（11.839 秒，墙钟 11.902 秒），未打开应用的包／签名／资源边界和原创性检查通过。所有 825 个 Git 跟踪输入在运行中及终态校验一致；参考仓库干净且仍固定于上述提交，终态进程检查无 Typebar／测试／Swift 编译残留。

持久证据为 `../../work/tape-projection-readiness.rrFGcC/`：readiness.log、frozen.sha256、75 份子日志及 232 张组件图。四张新增 tape-projection-letter／word／rtl-letter／rtl-word.png 已逐张查看，证明不可见组件捕获中存在实际文字与光标，不代表整机交互或 IME 验收。日志保留 CoreData／只读存储等诊断原文，不以最终通过声称日志完全无诊断。全程零 Typebar 主程序启动。

1,147 人工场景仅通过唯一性／结构检查，未执行人工验收；配置仍 89 映射／4 部分／1 不适用，主题精确映射仍 0／187，挑战仍 57 映射／1 待映射。应用层 Tape 投影保护未解除，跨词／多行拓扑与退休事务、混合方向／连接塑形、真实 IME 和整体功能等价仍未完成，goal active。本段更新下方专项阶段“完整门禁另行验证／未重跑”的当前状态，不把完整门禁通过当作完整重写完成。

## 同字段 fresh snapshot 与取消边界增量（2026-10-10）

TapePromptProjectionSnapshot 一次主线程读取绑定 input identity、原始字段和最终渲染。实际投影 owner 在展示前、独立 pace 请求读取同字段快照，更新文字、实测槽框、接受推进与主／pace；同次 owner 展示复用缓存，不重复调用 provider。缺失、旧 attempt、跨字段或结构行变化不覆盖当前模型；完整跨词退休事务仍交给后续配置。停止释放 provider；回调返回后复核 generation／attempt／协调器，不能让已停止或被替换 owner 安装快照。

六新增验证接受推进无需下一次配置、独立 pace 截止点先刷新候选而不定位主光标、缺失／旧 attempt／跨词拒绝及停止后不读 provider、有限重入、回调中停止、pace 回调中停止。共享 PromptCaretNativeView 在读取 latestInput 后确认配置仍有效，修正停止后的旧局部配置继续执行；无新时钟或产品依赖，不改输入、计分、回放和存储。

`../../work/tape-projection-fresh-red.log` 为快照类型／接口缺失；first.log 一项通过，expanded.log 三项一处失败发现重入读取两次，将保护移至回调前后 fixed.log 十五项通过。这三个成功／扩展日志亦位于 `../../work/`，前缀 tape-projection-fresh-。持久证据 `../../work/tape-projection-fresh.QRh0qZ/` 的 verified.log 131 项通过；stop-red.log 一项失败准确暴露停止后仍安装新文字，修正 generation 后 final.log 132 项通过；pace-stop-red.log 一项失败暴露共享 pace 继续返回旧 frame，修正共享入口后 terminal.log 最终 151 项零失败零跳过（6.746 秒，墙钟 6.763 秒），固定参考／动画归档环境齐备。

行为先行、决策复核及风险复核为本会话有界检查，不是独立审计。三轮反例为重入、owner 停止与独立 pace 停止，保留失败证据；跨词／多行、混合方向、连接塑形及任意异步顺序仍开放。独立 pace 量测使用原生 uptime，确定性测试采用即时动效，不据此宣称平滑队列／任意 RAF 等价。本轮无新增持久组件图，组件窗口不可见并关闭，零 Typebar 主程序启动。应用层保护未解除，完整门禁另行冻结验证，兼容分类不升级、goal active。

## RTL 投影与有限自然坐标增量（2026-10-10）

实际单行投影组件支持同向 RTL：共享 PromptFieldTextLayout 新增显式 unbounded，外层使用实测自然总宽、内部连接字段不因测量提案折行，RTL 镜像不再依赖十亿点提案；默认有界排版、复用隔离与普通生产路径保持不变。Tape 接受推进按 leading edge 与活动字段右边界计算，主 letter 光标右端锁定边距、word 按活动词右端平移；pace 别名使用同一有限坐标。投影方向查询不再读旧文字 storage，而按逐槽文本／原始字段目标及既有方向策略解析。

直接核对固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 scrollTape 符号、Caret 的测试流向／逐词与逐字方向规则；参考干净，Swift 6.2.4／最低 macOS 14，不引入平台新 API。`../../work/tape-projection-rtl-red.log` 一项四处预期失败：旧 RTL 路径未消费显式接受推进；first.log 九项通过。shared-red.log 十一项两处失败暴露连接字段仍内部折行，修正无界模式的内部宽度限制。以上三个日志位于 `../../work/` 且前缀 `tape-projection-rtl-`。

最终 `../../work/tape-projection-rtl.qIeQwW/verified.log`：111 项零失败零跳过（6.054 秒，墙钟 6.067 秒），固定参考与 Anime 归档齐备。三新增覆盖四主光标样式、有限坐标／接受推进／pace、RTL 完成字段后的 letter／word 推进、双向自然与默认有界连接字段量测；普通字段换行与旧 Tape 回归同跑。两张 tape-projection-rtl-letter／word.png 实际组件图逐张查看，窗口始终不可见并关闭，零 Typebar 主程序启动。配置量测诊断不是设备 FPS。

行为先行、源码驱动与差异风险复核约束本增量；没有新动画时钟、产品依赖、输入／计分／回放或存储修改。应用层 Tape 组合保护未解除，多行拓扑、fresh provider、退休队列、混合／反向方向、真实阿拉伯文连接塑形及系统 IME／设备仍开放；几何单元测试不证明这些组合。完整冻结门禁未重跑，94 配置 89／4／1、主题精确 0／187、挑战一项待映射不升级，完整 goal active。下方仅 LTR 的表述为历史阶段。

## 实际 Tape owner 投影组件增量（2026-10-10）

TapePromptNativeView 新增显式 compositionField／hidesCompositionExtras 输入，支持单行 LTR 无结构 Return 的实际组件投影。文字绘制复用 PromptFieldTextLayout 独立槽框，主光标经真实 before／after 锚点解析，canonical pace 保留首末别名；letter 主光标锁定边距，word 按活动字段原点平移。推进使用原始接受单位前缀与实测槽宽，不随候选主光标终点推进。缺少显式字段时不自动启用新布局；多行／RTL 仍走旧路径，应用层 Tape 投影保护未解除，尚未接通完整生产功能。

风险复核修正两处边界：十亿点仅是无换行测量上限，实际 NSView 宽度取有限槽框范围；投影／旧布局切换显式重置并重提交滚动，避免光标组件清空协调器后外层因距离相同漏滚。`../../work/tape-owner-projection-red.log` 为新增组件 API 不存在；first.log 七项通过。broad.log 72 项一处失败，准确暴露回到旧布局后的推进归零，根因是布局 resolver 切换清空协调器而外层未重提交；fixed.log 八项通过。以上 first／broad／fixed 文件均位于 `../../work/`，前缀 `tape-owner-projection-`。

证据 `../../work/tape-owner-projection.MkeS4c/verified.log`：96 项零失败零跳过（5.811 秒，墙钟 5.822 秒）；最后收紧缺失投影 ID 返回 nil 而非落回旧字符目录，final.log 再验 96 项零失败零跳过（5.781 秒，墙钟 5.792 秒），固定参考及 Anime 归档齐备。两新增覆盖实际 letter／word、emoji 接受单位与虚拟槽、候选更新／取消及返回旧布局、canonical pace、有限视图尺寸；两张 tape-projection-letter／word.png 为真实组件，已逐张查看。窗口始终不可见并关闭，零 Typebar 主程序启动、终态无 xctest 残留。字体量测诊断仅配置计时，不是设备 FPS。originality.log 因相对参考路径拒绝执行，改绝对路径后 originality-verified.log 通过；manual-audit.log 1,145 唯一人工场景仅结构检查通过。

行为先行、根因调试与风险复核约束本增量；没有新时钟、产品依赖、输入／计分／回放／存储修改。完整冻结门禁尚未重跑。fresh provider、字段退休／多行拓扑、RTL／连接塑形、隐藏 extra 完整组合、字体／设备与真实 IME 仍开放。94 配置 89／4／1、主题精确 0／187、挑战一项待映射均不升级，完整 goal active。

## 投影实测推进距离增量（2026-10-10）

推进槽接口新增 inlineAdvance：按实际槽 ID 的 allocation 宽度顺序求和，不以 canonical offsets 或墨迹并集代替；hidesExtras 跳过 .extra，下一槽明确为零宽时扣除最近正宽，缺失下一槽不误判为零宽。直接复核固定参考 test-ui.ts 的完整 scrollTape 当前词宽计算段；调用者仍须提供真实下一槽以及 blind／hideExtra 设置，字段前缀、方向和退休补偿不在此函数中。

两新增测试包含真实 PromptFieldTextLayout 测得的 emoji／虚拟候选槽宽，以及受控隐藏 extra／零宽／缺失下一槽边界。`../../work/tape-measured-advance-red.log` 保留初始红灯（缺接口及错误测试枚举类型）；修正测试类型后的 `tape-measured-advance-red-verified.log` 仍因缺接口失败。最终 `tape-measured-advance-verified.log` 34 项零失败零跳过（3.578 秒，墙钟 3.583 秒），参考与动画归档环境齐备。行为先行及差异风险复核约束本增量；真实量测不是浏览器像素等价，受控框不代表全部字体和连接塑形验收。

尚未接入 TapePromptNativeView，也未解除生产组合投影保护；这不是可见功能完成。完整门禁未重跑，无新图、零主程序启动；词容器几何、候选主／pace、结构行与队列组合仍开放，goal active、兼容分类不升级。

## 投影推进槽接口增量（2026-10-10）

新增 TapePromptProjection.advanceCells：从活动原始字段的 inputUTF16.count 选择最终 fieldRuns 中非提交 gap 的前缀，保留独立槽 ID 与属性，不用候选主光标终点或拼接字符串字符偏移。off／word／无 map／空输入返回空前缀。固定 scrollTape 对应行为为以 input.length 遍历实际 letter 节点，因此一个已提交 emoji 的两个 UTF-16 单位可能选择一个额外候选槽；这项源混合单位行为不擅自改为 grapheme 计数。隐藏 extra 和下一槽零宽回退仍由待接几何层处理。

证据 `../../work/tape-advance-cells.CjtdUn/`：红灯 `../tape-advance-red.log` 为新接口不存在；focused.log 四项一处失败，夹具目标有可复用 canonical ID，无法满足虚拟槽断言，改为目标末尾的真实候选溢出。broad.log 32 项零失败但缺参考环境而跳过一项，不计完整成功；补齐固定参考与归档后的 verified.log 最终 32 项零失败零跳过（3.585 秒，墙钟 3.589 秒）。四新增检查接受前缀／候选终点分离、UTF-16 与真实虚拟槽、空输入及活动字段归属。行为先行和差异风险复核约束本次接口；无持久化、输入、计分或时钟改动。

这是原生几何适配的前置接口，尚未接到 TapePromptNativeView；生产 Tape 组合投影保护仍保留，不能计作可见功能完成。完整门禁未重跑、无新图、零 Typebar 主程序启动。实际候选槽布局、隐藏 extra／零宽补偿、pace 别名、退休队列、方向与实机 IME 仍待验，兼容分类不升级、goal active。

## Tape 事件快照锚点证据（2026-10-10）

下一步组合投影适配前先核对固定参考的真实事件 getter／logger／helpers。既有完整 scrollTape／Caret／RAF 探针不再用 getCurrentInput 替身，而由真实 input 快照提供推进长度；六类 composition 更新（含 emoji、组合符、控制字符、清空和中文）不改变快照，切活动字段后无新 input 返回空。480 个已提交快照共 2,880 次候选隔离断言通过，128 普通、32 前缀退休和 28 方向例的输出 JSON 与改动前逐字节相同。

证据 `../../work/tape-event-anchor.lQ5PzM/`：before／after 为初始替换对照；verified.log 保留计数预期误算 3,072 的失败，按实际循环 480×6 修正为 2,880；final.json 与 before.json 的 cmp 通过。native.log 中 TapePromptPresentationTests 17 项零失败（3.555 秒，墙钟 3.558 秒），含完整固定源横向通道对照，参考环境齐备、没有跳过。源码仅 QA 动态读取，不复制进原生产品。

本次为减少实现不确定性的源码探针增量，不改产品行为，未做产品红灯测试。使用源码驱动与行为先行技能，差异风险复核未见新增产品路径；候选事件虽保持为最后更新，DOM 仍是受控的三字母框，未执行真实候选排版、系统 IME 或事件控制器。原生 Tape 组合投影仍未接通：必须分开已提交推进锚点与候选主光标，不可直接以候选终点替代 Tape advance。完整门禁本轮未重跑；零主程序启动，无新增截图，兼容分类不升级、goal active。

本轮解除普通目标含换行时的 Tape 生产回退，复用既有 SwiftUI／AppKit 词框，不复制 Monkeytype 产品代码、字体或资产。固定只读参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。这是完整原生重写的一个增量，不是功能等价完成声明。

## 行为与源码依据

生产 `ContentView` 与实际挂载测试共用 `TapePracticePrompt(session:...)`。目标初始声明换行时，从尚未生成 Return 的引语首词起就预留三个原生实测行高；Zen 仍为两行。引语初始控制字符能力与后来生成的文本拓扑分开：messagingStyle 后来生成 LF、初始能力仍为 false 时，按已生成词框自然高度呈现，四行不误截成三行，也不因此准入 Return。普通无换行仍单行。

固定源 `frontend/src/ts/test/test-ui.ts` 完整 `updateWordsWrapperHeight` 的普通 Tape 分支，声明换行选三行，否则选实际 words 高度／当前词高度；raw showAllLines、计时／无限、自定义、force、页面／结果／缺失活动词仍有各自门禁。`test-logic.ts` 初次生成保存控制字符能力，`input/handlers/before-insert-text.ts` 按该能力准入；未修改原生对应输入能力。QA 探针执行完整固定函数的 768 组自有测量，并以 24 组有效夹具对照挂载组件的三行比例。CSSOM 是受控边界，不宣称浏览器排版或字体像素等价。

Tape 自己拥有高度和滚动，不能再嵌入生产父层的独立 184 点 `PracticePromptViewport`。抽取并共用 `PracticeLineDisplayPolicy.needsOuterViewport`，普通非 Tape／ASL／Choo 保留原外层，Tape 直接呈现；16 组策略组合及实际挂载的无 NSScrollView 检查覆盖该边界。静态生产路由断言加共用策略／初始化器挂载，不等于完整 ContentView 运行期或实体键盘证明。

完整固定 `test/test-words.ts`、`utils/strings.ts` 与 `buildWordHTML` 的八组实际建词证明：末尾分隔符不会另生成未来空词。原生导航的 target.count 空尾仅在未物化 future、无字形／Return／缺口且非隐藏边界时过滤；真正的中间空词、活动空词、连续 Return 空行及隐藏边界空目标保留。隐藏边界直接复用会话既有事实，不根据语言或当前修饰器猜测；`TypingEngine` 只提取同一呈现条件，无输入接受、计分、持久化或服务协议改动。

真实会话挂载覆盖 word／letter、四种模式短题、引语按需生成、错误 Return replacement 与纠正、连续退休及完整成绩／可移植记录／回放、RTL／emoji／组合字符、字号、狭窄独立缺口和平滑重开。所有窗口从未显示，defer 中 stop／close；本轮零 Typebar 主程序启动，没有新 timer、依赖、设置字段或迁移。

## 先行证据与修正

- `/tmp/typebar-ordinary-tape-entry-red.log` 最初夹具字段／参数顺序编译错误，不算行为红测；修正后 `entry-behavior-red.log` 七项有 27 个预期失败（10.636 秒），随后 `entry-first.log` 28 项零失败（8.553 秒）。此处简写文件均位于 `/tmp/typebar-ordinary-tape-` 前缀。
- `/tmp/typebar-ordinary-tape-outer-viewport-red.log` 一项两失败（1.119 秒），实际 Tape 外层确有独立滚动容器；修正共用父层策略，而非只修测试根视图。
- `/tmp/typebar-ordinary-tape-entry-expanded.log` 41 项四失败（13.494 秒）：自然四行错误变成五行。完整源码建词后，`tail-red.log` 两项 15 失败（1.681 秒）确认多余末尾词是产品缺陷；保留四行期望，修正投影。`entry-corrected.log` 52 项零失败（11.879 秒），`entry-regression.log` 304 项零失败零跳过（51.413 秒）。
- `/tmp/typebar-ordinary-tape-boundary-red.log` 同时暴露真实隐藏空词误删与一个错误测试假设（中文不走空格提交）。读取实际语言策略后纠正后者，`captured-boundary-red.log` 一项仅剩真实空词误删失败（0.763 秒）；改为会话实际隐藏边界条件。未修改输入策略来迎合错误假设。
- `/tmp/typebar-ordinary-tape-entry-final-regression.log` 304 项零失败但 15 跳过（27.593 秒），因漏传参考路径，不能算完整对照成功。补齐固定参考／锁定 Anime.js 后，`entry-pinned-regression.log` 304 项零失败零跳过（50.186 秒），其中十二个普通入口测试通过（6.737 秒）。

十一张定向图位于 `/tmp/typebar-ordinary-tape-focused-images.WA8xid/ordinary-tape-*.png`，主代理已逐张查看。非空断言要求灰色文字像素，不允许只凭蓝色光标通过；短题三行、后来两行／四行、退休与纠错另有实际几何断言。窄图裁剪是预期，不据此宣称完整设备可读性。

## 有界风险复核与未完成项

同会话三轮复核分别检查初始能力／拓扑／高度分离、生产外层所有权、空尾与真实隐藏边界身份。反例先失败再修正；不是独立审计。两个旧静态测试只删除与本次新生产行为矛盾的“必须保留回退”断言，原几何／退休断言不变，新入口测试明确断言解除保护。

任意 IME／组合 replacement、hint、no-space 内部 LF 完整导航、零偏移别名、未来缺失目标激活、反向纵横队列及字体重建确认时序、可见范围性能、原版字体／主题资源、ASL／Choo 全部组合与实体设备仍开放。CFG-02／MET-67 与 tapeMode 仍部分兼容；94 配置的 90 映射／3 部分／1 不适用不代表功能全通过。此前普通换行生产回退的历史结论仅在本合同范围更新，其余缺口不升级，完整 goal active。

## 最终冻结验收

首轮十五文件冻结哈希始终一致；`/tmp/typebar-ordinary-tape-final-readiness.log` 终态退出 1，在页面证据审计发现旧测试符号引用，尚未执行原生全量／服务／打包，不计成功。修正页面证据矩阵的重命名符号，登记本轮十三项真实测试，不提升兼容分类；原始失败日志保留，之后重新冻结运行。

最终重新冻结十六个文件，`/tmp/typebar-ordinary-tape-verified-frozen.sha256` 在启动、中途与终态逐项一致。`/tmp/typebar-ordinary-tape-verified-readiness.log` 终态退出 0：原生 3,953 项零失败零跳过（978.921 秒），服务 501 项零失败零跳过（11.730 秒）。十二项普通入口测试 7.026 秒，十一项控制投影测试 0.037 秒、九项 Zen 入口 2.807 秒；十万词耐久 177.552 秒，16 项隔离磁盘迁移 5.589 秒。原生全量中实际只读失败／损坏存储夹具和系统 Contacts／CoreData 诊断均保留，不能当作 XCTest 失败，也不据此宣称设备环境无诊断。

固定源码门禁（含本轮 768 组／八组实际建词）、53 页面／modal 表面、1,126 唯一人工场景结构、94 配置的 90 映射／3 部分／1 不适用、未启动应用包／签名／资源及原创长文字边界检查全部通过。人工结构检查不是实际人工验收，原创边界检查不证明全部功能、字体或设备等价。73 份原始日志位于 `/tmp/typebar-ordinary-tape-verified-logs.7Ob20I`，210 张图位于 `/tmp/typebar-ordinary-tape-verified-images.ayvvel`。主代理终态后逐张复查十一张 `ordinary-tape-*.png` 与八张 `zen-tape-*.png`；普通图有灰色文字像素，Zen 黑字／透明背景限制沿用旧合同。退休 pace 开／关整张 PNG 仍精确一致。

终态确认无测试、编译、门禁或 Typebar 主程序残留，再仅补本合同、README、规范和盘点的验收记录；其余十二个冻结文件保持一致。参考始终为干净固定 pin，本轮零主程序启动，完整 goal 继续 active。
