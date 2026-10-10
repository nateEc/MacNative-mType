# 普通多行 Tape 生产入口与高度所有权

## 原生语言菜单降低完整宿主同步布局开销（2026-10-10）

在 d3c7bd7 完整门禁之后进行可撤回试探：语言 Picker 原路径在每次会话更新时参与大量菜单项的 SwiftUI 图更新。用 owner-local NSPopUpButton 保留完整有序语言身份，仅选项列表变化时重建菜单，普通输入只同步选择与最新 binding。原生控件保留“语言”AX 标签与系统外观，继承 SwiftUI disabled；现有 selectLanguage、重启保护、引语过滤及 onChange 链不变，无全局缓存、额外计时器或动画／健康阈值修改。

安装版本为 Swift 6.2.4／macOS 26.2 SDK，最低目标仍 macOS 14。核对本机 [NSPopUpButton 主接口](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSPopUpButton.h)，采用旧 initializer／选择／菜单 API，不用 macOS 15 新增便捷 API。会话内决策审查与风险审查重点为完整身份、旧闭包、禁用、拒绝变更与退休，不是独立第三方审计。

native-language-popup-probe.log 单项零失败（9.567s，墙钟 9.569），四组首字符同步布局约 182–199ms，后续约 52–55ms。随后恢复旧 Picker 对照 native-language-popup-baseline-restored.log 单项零失败（14.018s，墙钟 14.020），首字符约 323–339ms。恢复新控件后的最终同路径约 189–197ms，后续约 52–55ms。配置相同、四组尺寸选项不变，但顺序、随机提示与系统负载不构成公平硬件基准；不把这些 DEBUG 数字换算为实际 Release 首键故障已解决。

边界回归先保留失败：native-language-popup-lifecycle-red.log 三项六处失败（0.719s，墙钟 0.721）；动作派发的三处由独立测试未初始化 NSApplication 引起。补该测试环境后 native-language-popup-dispatch-red.log 三项三处真实生命周期失败（0.685s，墙钟 0.686）。增加宿主拒绝绑定后 native-language-popup-rejected-red.log 四项四处失败（0.858s，墙钟 0.859），包括拒绝后仍显示未接受语言。修正为回读实际 binding，并在 detach／dismantle 清理 action、target 和回调；native-language-popup-behavior-final.log 四项零失败（0.254s，墙钟 0.256）。

native-language-popup-final.log 19 项零失败零跳过（154.922s，墙钟 154.925），包含全部十一项生产宿主、四项菜单行为、视觉聚焦集成和语言命令／引语选择。覆盖全部菜单标题／身份／顺序与项目复用、程序更新不派发、最新 callback、disabled、空列表、拒绝及接受 binding、同 owner 与退休释放。native-language-popup.png 为不可见宿主生成的组件图，已检查系统菜单与标签显示；非完整窗口验收。固定参考原创性边界退出 0；所有运行终态后才编辑记录，零 Typebar 主程序启动。

审查后补菜单数量保持断言，native-language-popup-menu-count-final.log 四项零失败零跳过（0.302s，墙钟 0.304）。这些对照支持语言菜单路径贡献实质开销，不锁定 SwiftUI 内部逐项重建机制或整个首键根因。风险审查未发现剩余可落实缺陷；真实键盘菜单操作、Release 首键、最低系统和完整窗口仍待验。此前全量门禁冻结 2ca44a8，不覆盖本次原生菜单新增生产代码；兼容分类与完整 goal active 不变。

## 近期增量的完整冻结门禁复验（2026-10-10）

冻结 2ca44a8 的完整门禁通过，见 [当前组合投影门禁证据](COMPOSITION_PROJECTION_CONTRACT.md)。客户端 4,211／服务 501 项零失败零跳过，845 文件哈希终态一致，74 日志保留；字体延迟目录查询、跨行候选及 Tape 退休回调检查均通过，Release 构建 374.72s、未打开包／签名／原创性边界通过。零主程序启动，权威会话终态后才编辑记录。

这补齐此前字体与混排增量之后的自动化复验，不证明首键延迟修复或排除全部退休竞态；真实 IME、可见窗口、全部原版行为与人工验收继续开放，完整 goal active。

## 配置面板禁用传播对照未解释首键同步成本（2026-10-10）

冻结 f90a03c 工作区洁净后，仅临时将配置面板 .disabled(visualFocus.isFocused) 改为 .disabled(false)，其余命中测试、AX 隐藏、opacity 动画与全部内容保持；此为根因定位试探，无预先故意失败阶段，不是交付候选。configuration-disable-layout-probe.log 一项零失败（14.902s，墙钟 14.904），四组首字符同步布局约 347–385ms，后续约 131–139ms，第二字符事件交付仍有 411–480 次根布局。不能支持禁用传播是首键同步成本主因，也不能将不同次数当作优化或退化的公平基准。

权威测试会话终态后立即恢复原行为，再运行完整首键宿主与 TypingVisualFocusIntegrationTests。configuration-disable-layout-restored.log 三项零失败零跳过（16.802s，墙钟 16.804），首字符同步布局约 360–392ms，隐藏配置键盘不可编辑保护检查通过。git diff 确认生产源码及测试无改动，零 Typebar 主程序启动，无新全量门禁／Release GUI。

源码 TypingVisualFocus.set 将聚焦提交排至下一轮主线程；同步布局与后续 RunLoop 交付分开测量。本轮仅排除一个不足的修复候选，不锁定完整根因。后续优先追踪聚焦提交前的同步图更新／测量，保留配置交互功能、默认动画和计时健康阈值；首键性能及完整兼容 goal 仍 active。

## 字体家族目录按需查询，不宣称首键修复（2026-10-10）

当前源码确认 NativePracticeFont.postScriptName(for:) 在验证名称及直接字体匹配之前提前求值系统 availableFontFamilies。新增副作用计数回归：空名称、含内部控制字符名称和直接有效 PostScript 名称应零次查询；无法直接解析时仍查询一次当前目录。font-family-lazy-red.log 一项两处预期失败（0.611s，墙钟 0.613），实际提前枚举三次，最后累计四次。

仅将 installedFamilies 参数改为非逃逸 autoclosure，并在需要家族匹配时求值；保留规范化、直接名称优先、家族匹配及本地覆盖／预览行为，不缓存系统字体，不改变动画或计时健康阈值。font-family-lazy-final.log 19 项零失败但缺固定参考一项跳过（15.946s，墙钟 15.950），不算完整通过。终态后补环境重跑 font-family-lazy-pinned.log：19 项零失败零跳过（16.396s，墙钟 16.400），覆盖字体预览／命令、已安装名字、统计观察范围及四组完整宿主连续输入。固定参考原创性检查退出 0。

完整宿主首字符同步布局仍约 351–363ms，未证明主要延迟改善。此修改消除已实证的无用目录访问，不关闭首键问题；后续需继续定位同步布局。零 Typebar 主程序启动，无新 Release GUI 或全量门禁；全部测试及审计终态后才编辑记录，完整 goal active。

## 最新候选读取路径的 intrinsic 约束失效（2026-10-10）

源码沿首键问题检查发现，configure 已按实际尺寸通知失效，但 refreshRendering 在最新 provider 返回改变内容时仍无条件 invalidateIntrinsicContentSize。实际 Auto Layout 父视图挂载字段回归先验证候选“中”→“文”尺寸相等、几何代次和辅助文本更新。field-fresh-size-red.log 一项通过，父 needsLayout 未能区分该问题；改查字段 needsUpdateConstraints 后，field-fresh-constraints-red.log 一项一处预期失败（0.717s，墙钟 0.718）。这是约束失效证据，不是整个父树无需布局的证明。

refreshRendering 现在保存旧 intrinsicContentSize，仍更新 rendering／模型、follower、重绘与辅助文本，仅尺寸变化时 invalidateIntrinsicContentSize 并请求布局。新增缓存 PNG 比较确认同尺寸内容变化仍到达绘制路径，以及 80 字候选改变高度时约束和布局失效仍发生的正例。首次 green 日志五处失败：缓存绘制影响父布局状态，且测试未提供改变的 latestInput，第二次 present 合理地不再读取 provider。identity 日志补新输入身份后仅父布局断言失败；最终删除不成立的“光标正常变化也不能布局”要求，保留精确 intrinsic 约束要求、尺寸变化、内容、像素和辅助文本断言，未修改生产光标读取策略。

field-fresh-constraints-final.log 177 项零失败零跳过（50.571s，墙钟 50.590），含完整宿主组合更新／取消／提交／回删、字段／光标、Tape 前进。独立固定参考原创性检查退出 0。完整宿主首字符同步布局仍约 355–365ms，后续约 135ms；本修正不证明首键性能问题解决。所有测试和审计终态后才编辑记录，零 Typebar 主程序启动；没有新完整门禁或 Release GUI，真实 IME、首键和完整功能兼容 goal 继续开放。

## 同尺寸候选更新的反例验证（2026-10-10）

补强上轮尺寸失效修正：实际 PromptFieldNativeView 将候选“中”更新为“文”，先断言测量尺寸确实相等，再断言不请求额外布局；同时几何代次增加、候选 caret 槽可测量、可访问文本精确更新，且缓存绘制 PNG 与原候选不同。此检查不允许用尺寸相同跳过内容重建。保留完全重复配置不变与字体变大必须布局的两端正反例。

第一轮 field-equal-size-content.log 20 项中一处失败（0.825s，墙钟 0.828）：试图通过未挂载视图的 needsDisplay 标志判断重绘，该标志未保持。生产源码明确仍设置 needsDisplay，不据此认定调度故障；改为实际 bitmapImageRep／cacheDisplay 输出比较，不放宽内容或像素变化要求。field-equal-size-content-pixels.log 20 项零失败零跳过（0.192s，墙钟 0.195）。这证明显式绘制使用新内容，不单独证明可见窗口的系统重绘交付时序。

固定参考／归档下 field-equal-size-content-regression.log 100 项零失败零跳过（3.297s，墙钟 3.310），涵盖字段布局、组合、ASL／Choo／Tape。此轮是已有生产修正的反例覆盖，无预先故意失败阶段；错误测试参照和修正日志均保留。没有产品代码变化、GUI 主程序启动或新完整门禁；真实 IME、可见交付、首键延迟及完整功能兼容仍开放，goal active。

## 原生字段重复配置的尺寸失效修正（2026-10-10）

检查同步更新路径发现 PromptFieldNativeView.configure 无条件 invalidateIntrinsicContentSize 并设置 needsLayout，即使模型／测量尺寸完全相同。新增实际原生视图回归先配置、布局并清除 dirty，再重复同一配置；field-layout-invalidation-red.log 一项一处预期失败（0.722s，墙钟 0.723），失败为重复配置仍请求布局。测试同时保留几何代次、尺寸和辅助功能值不变，以及字体变大必须改变尺寸并请求布局的正例。

生产改为配置前保存 intrinsicContentSize，仍更新完整 rendering、控制器／最新 provider、视口通知和可访问值，并保持重绘；仅实际测量尺寸变化才通知 intrinsic size 失效和请求布局。不缓存旧 rendering，不更改光标或计时阈值。field-layout-invalidation-green.log 53 项零失败零跳过（44.677s，墙钟 44.683），含完整生产宿主的输入、组合更新／取消／提交／回删，以及模型投影。完整宿主首键同步布局仍约 360–363ms，后续约 134–138ms；不声称该修正解决首键性能故障。

field-layout-invalidation-regression.log 在固定参考与锁定 Anime 归档下扩展原生字段、ASL／Choo／Tape 组合等共 100 项零失败零跳过（3.186s，墙钟 3.198）。原创性首次调用漏写 --reference，退出 1 为参数错误，原日志保留；正确调用 field-layout-invalidation-originality-verified.log 退出 0。全部进程终态后才补文档，零 Typebar 主程序启动，无新完整门禁／Release GUI。真实 IME、尺寸变化组合和实际首键故障仍需更广验收；完整功能 goal active。

## typingPanel 类型边界候选撤回（2026-10-10）

按根因调试重新检查既有五秒采样的输入后显式布局分支（540 个样本，不与初次挂载 872 或交付 523 相加）：最高单一路径的项目帧包括 ContentView.body 60、typingPanel 53、renderedPrompt 53、原生提示 updateNSView 30、configure 25 和 measure 19；均为嵌套包含计数，不构成互斥占比或精确耗时。旧采样早于静态背景修正，只用于提出候选，不替代当前版本复测。

会话内决策审查检验一个候选：仅将 practiceLayout 内 typingPanel 包为 AnyView，所有提示、设置、动画和原生输入保留。不是独立审计；探索性性能假设没有先制造失败。practice-typing-panel-boundary-probe.log 一项零失败零跳过（15.224s，墙钟 15.225），含四组十二次输入及背景切换 owner 保持、固定 frame、不可见窗口断言；首键布局 357–361ms，后续约 133–138ms，没有可观察局部收益。因此撤回该生产改动，不保留无收益抽象。

恢复原结构后 practice-typing-panel-boundary-restored.log 一项零失败零跳过（15.175s，墙钟 15.177）；生产与测试源码均与上次提交相同，本轮仅保留诊断记录。零 Typebar 主程序启动，无新全量门禁／实机验收，不宣称首键问题已修复。已排除动画关闭、尺寸协商和两处类型擦除作为充分修复；后续须继续找具体同步更新成本，同时推进仍未完成的原版功能矩阵，不能以不断增加诊断替代功能交付。完整 goal active。

## 根布局失效栈与减少动态效果反证（2026-10-10）

继续诊断上轮高频布局，测试宿主增加 needsLayout 写入计数；TYPEBAR_TEST_LAYOUT_STACK=1 时，在第二字符同步布局之后分别捕获第十次布局和第十次失效的栈，每种每宿主最多一次、最终限制为 40 帧，默认不采集。调用 super／原属性行为不改，不通过私有 API 干预框架。探索性检查没有故意失败阶段，所有 owner、固定 frame 和不可见窗口断言保留。

practice-root-layout-stack.log 一项通过，布局栈来自 NSWindow 显示周期观察者，经布局树到根宿主，不是测试显式调用循环；初次版本下一字符再次打印同一已捕获栈，后续改为只在第二字符打印，没有重新采集的额外证据。practice-root-invalidation-stack.log 一项零失败零跳过（15.179s，墙钟 15.180）：失效栈来自 SwiftUI NSHostingView.requestUpdate／动画完成监听，经 RunLoop block 设置 needsLayout。符号定位不是框架内部语义的完整证明，也未锁定具体生产动画。

用 TYPEBAR_TEST_REDUCE_MOTION=1 将隔离 AppSettings 设置为应用已有的减少动态效果选项，不改生产默认。practice-root-layout-reduced-motion.log 一项零失败零跳过（15.283s，墙钟 15.285）：四组第二字符交付布局均零次，第三字符一次；首字符同步布局仍 351–364ms，后续约 132–142ms。支持高频交付布局与动画路径相关，但反驳将其视为首键同步布局主要成本；不以关闭动画作为产品修复或删减功能。

最终恢复测试默认动画，开启有界栈采集，与统计范围共两项零失败零跳过：practice-root-layout-stack-final.log（15.874s，墙钟 15.877），第二字符交付次数 164／224／217／196，首字符同步布局 358–364ms。采栈会扰动次数，不将差值声称为优化。后续应继续追踪昂贵的同步 SwiftUI 图更新／测量，而非把全部布局次数当作相同成本。本轮零 GUI、生产代码未改、没有新全量门禁或实机验收；完整兼容 goal active。

## 完整宿主根布局次数与交付阶段定位（2026-10-10）

沿根因调试流程增加诊断性 NSHostingView 子类，仅在 layout 入口计数并调用 super，生产代码未改。探索性计数没有预先故意失败阶段；新增每次输入后固定宿主 frame 不变断言，原生输入 owner、背景切换和窗口不可见断言继续保留。次数不是性能阈值，不冻结框架内部调用数量。

practice-root-layout-count.log 一项零失败零跳过（15.299s，墙钟 15.301）：四组均同步布局一次，第二字符整段累计布局 227–285 次，首／第三字符三次。终态后将事件交付和末次显式布局分开计数。practice-root-layout-phases.log 与统计观察范围共两项零失败零跳过（15.795s，墙钟 15.797）：四组第二字符交付阶段 249／249／263／254 次，首／第三字符各两次，末次显式布局全部零次；同步布局仍全部一次。首字符同步布局约 357–367ms，后续约 132–138ms；100ms 交付窗口中的高频布局不等同于每次都有完整内容重建或高成本。

默认／空 sizingOptions 均出现该模式，关闭宿主尺寸协商不足以消除重复交付布局。证据将后续诊断缩小到事件期间的布局失效来源，但尚未区分框架行为、不可见测试宿主影响或生产状态更新，也不能直接解释实际 Release 首键故障。本轮零 Typebar 主程序启动，无生产修改／新全量门禁／实机验收；上一全量门禁仅覆盖此前冻结版本。完整兼容 goal 保持 active。

## 静态背景修正后的全量冻结门禁（2026-10-10）

冻结已推送的 ff2bfb01950f75b0c363359773da114ef85305fe，运行 check-native-rewrite-readiness.sh；固定参考仍为 91bd24bb8513785c7364cbea29296ff7adafac41，明确传入 Redis 6.2.6 与锁定 Anime.js 归档。主会话 42745 权威退出 0 后才编辑本记录。843 个跟踪文件运行前记录 SHA-256，结束后逐项核对通过；测试与编译期间没有源码改动、重启或并行第二轮。

backdrop-readiness.Qp2a41.gate.log 与同名目录保留完整门禁日志。客户端 4,179 项零失败零跳过（904.347s，墙钟 904.898），服务 501 项零失败（12.138s，墙钟 12.200）。固定源码行为对照、历史磁盘模型准备及未打开的 Release 包校验通过；生产构建 445.69s，签名、包资源边界和原创性检查通过。日志保留系统 CoreData／AddressBook 告警，不据此认定产品失败；本轮没有额外执行联系人查询或修改操作。

本轮零 Typebar 图形主程序启动，结束后 pgrep 确认无实例；未执行新 Release GUI 或真实键盘／IME 验收。本次证明冻结版本自动化门禁通过，不证明首键计时健康故障修复，也不替代人工场景、主题配色和全部原版配置的兼容性验收。完整 goal 继续 active；后续仍需定位实际练习页布局开销并补齐功能矩阵。

## 静态背景调度修正与整页采样（2026-10-10）

按根因调试技能直接采样完整宿主测试：首次人工附加 sample 时进程已结束，退出 255，不算有效采样；确认原测试终态后，重跑并检测该 swift-test 的 xctest 子进程，自动附加五秒采样。practice-host-sampled-verified-test.log 一项零失败零跳过（13.202s，墙钟 13.203），practice-host-layout-verified-sample.txt 保留。主线程 3,248 个样本；初次 flush 的布局分支 872、输入后显式布局分支 540 均含下层调用，不相加或当成精确毫秒。存在 PracticeBackdrop、SwiftUI 图更新、原生字段测量等路径，没有据一个符号直接认定完整首键故障根因。

会话内决策审查的探索候选为 AnyView(lifecycleContent)，保持所有内容和任务，检查子树身份及布局成本。practice-lifecycle-boundary-probe.log 四项零失败零跳过（12.518s，墙钟 12.521），但首字符约 355–361ms、后续约 132–135ms，无显著收益；已撤回。practice-lifecycle-boundary-restored.log 一项零失败零跳过（11.659s，墙钟 11.661）。不是独立架构审计，也不排除所有组合成本。

源码核查发现更明确的资源边界问题：PracticeBackdrop 无条件创建动画 TimelineView，纯色、静态网格及减少动态效果时相位虽不使用／恒为零，调度仍存在。生产改为只有 halos 且应用／系统减少动态效果均关闭时创建时间线。正常光晕沿用帧率策略及 sin 相位公式；静态分支复用原 GeometryReader／颜色／网格／光晕绘制，主题和尺寸仍由 SwiftUI 更新，不缓存旧主题、不改计时阈值或删背景功能。

行为优先：backdrop-scheduling-red.log 因缺少策略接口编译失败。实现后的 verified.log 四项中像素参照有四次断言失败，原先直接 NSColor(Color) 的解析值与同窗口缓存绘制的语义色不一致；改为同窗口直接绘制 SwiftUI Color 的参照，保留 0.02 精度，并增加绿色与 alpha 通道比较，不扩大容差。render-oracle.log 13 项零失败但漏传参考导致一项跳过；final-pinned.log 补参考后又因漏传锁定 Anime.js 归档造成源码对照两次断言失败，均保留原日志。final-archive.log 补齐固定参考／归档后 39 项零失败零跳过（14.854s，墙钟 14.860）。

最终补入完整生产宿主运行中切换 solid／halos／grid 的输入 owner 保持断言；backdrop-scheduling-final-identity.log 39 项零失败零跳过（18.563s，墙钟 18.570），含十二种调度条件、实际主题／尺寸像素更新、四组连续输入及背景切换、统计观察、slow timer、帧率与主题相关回归。输入布局成本仍约原范围，不宣称修复实机计时失败；该修正只关闭明确无视觉用途的持续背景调度。原创性检查退出 0，1,151 项人工场景结构通过但不代表实际人工验收。

本轮零 Typebar 图形主程序启动，所有测试／采样／审计终态后才补文档。未跑新全量门禁或 Release GUI；动态光晕完整实机观感、输入性能与所有原版功能缺口仍开放，完整 goal active。下一步对本次生产变化做单实例 Release／更广门禁验证，而非提升整个项目完成状态。

## 连续输入与语言菜单候选反证（2026-10-10）

在已有完整生产宿主中，每个默认／空／空／默认尺寸组依次插入 a、b、c，三次均断言原生输入 owner 保留。practice-consecutive-input-probe.log 一项通过（11.584s，墙钟 11.585）：首字符布局 0.353408–0.362174s，后续布局 0.132993–0.138464s；第二字符交付约 100ms，第三字符约 231–240ms。因此并非只有首次进入状态才有布局开销，但不可直接据第三次交付归因到计时器，宿主不是可见窗口／真实按键／异步时钟调度的完全替代。

检验候选：将 Picker 的全部语言选项抽成只依赖语言目录的独立内容视图，保留父层 Binding／onChange 与筛选。language-options-red.log 因组件未实现而编译失败；候选实现后的 language-options-composition-probe.log 两项零失败零跳过（12.324s，墙钟 12.326），其中实际原生 NSPopUpButton 的全部标题、引语子集和当前 English 选中项与原目录精确一致。完整宿主首字符布局仍 0.358390–0.363478s，后续 0.133453–0.138283s，没有观察到局部收益。按根因调试流程撤回生产拆分、实验组件及其专项测试，不保留无收益抽象；原始实验日志仍在 work 目录。

最终仅保留连续输入宿主测试增强。practice-consecutive-final.log 与统计观察范围共两项零失败零跳过（12.055s，墙钟 12.057）；包含四组共十二次插入，首字符布局约 357–361ms、后续约 134–137ms。没有性能通过阈值，固定顺序／随机提示仍非公平性能基准；原有 owner 保持和不可见窗口断言未削弱。生产源码与上一已推送版本相同，本轮零 Typebar 主程序启动、无全量门禁／新实机验收。首键及共有布局路径仍需继续定位，不提升功能兼容结论，完整 goal active。

## 完整生产练习页的不可见宿主证据（2026-10-10）

应用 rootContent 与新测试共用 TypebarApp.practiceContent，原有 ContentView、依赖和生命周期不复制、不裁剪；应用外层恢复账户／公告任务与窗口配置仍留原处。新增 PracticeCompositionHostTests，以独立 UserDefaults suite、内存 SwiftData 容器及未显示窗口挂载实际生产练习页，直接调用原生 NSTextInputClient 插入首字符，断言原生输入 owner 仍为同一实例。不同于实际 macOS 键盘／IME／可见 WindowGroup，不将其当作实机验收。探索性机制排查无故意失败阶段；共用入口仅纯组合抽取，不改计时、配置或呈现规则。

practice-composition-host.log 一项通过（2.894s），首输入及布局 0.643120s。进一步按默认／空／空／默认 sizingOptions 顺序对照完整宿主，practice-composition-sizing-comparison.log 与光标、统计范围等 20 项零失败零跳过（10.455s，墙钟 10.458），四组分别 0.640804／0.644176／0.647548／0.652063s。关闭整页尺寸协商没有显著解除局部开销，维持生产尺寸选项不变。固定顺序和冷缓存仍非公平性能基准。

分段 practice-composition-phase-probe.log 一项通过（9.231s，墙钟 9.233）：输入回调 0.000528–0.000894s、首次同步布局 0.358303–0.364460s、要求至少 100ms 的事件交付阶段实际 0.282541–0.316829s、末次布局约 20–28 微秒。该分段将主要局部工作定位在布局／交付，而非输入回调；不能把交付阶段全部解释为 CPU 忙碌或推断具体控件责任。新增宿主可在不启动主程序的情况下继续做实际生产页对照。

格式化后 practice-composition-final-regression.log 六项零失败零跳过（13.818s，墙钟 13.821），涵盖生产页、统计依赖／范围、空闲观察与原生窗口焦点；首次布局仍约 0.357–0.364s。practice-composition-originality.log 固定参考原创性检查退出 0。所有编译／测试／审计终态后才补文档，本轮零 Typebar 主程序启动、无全量门禁或新 Release 验收。首键计时失败和完整功能兼容仍未关闭，goal active。

## 固定光标宿主尺寸协商局部反证（2026-10-10）

沿失败前布局采样检查 PromptCaretNativeView.paint：光标由原生 frame 定位，其内容是独立 NSHostingView。按源码驱动技能读取已安装 Xcode macOS SDK 的 SwiftUI.swiftinterface，确认 NSHostingView.sizingOptions 与 NSHostingSizingOptions 在 macOS 13 起可用，低于项目最低 macOS 14；接口仅证明签名和可用性，不据此推断框架内部耗时或默认行为。

新增探索性 CaretHostingSizingProbeTests，不先制造失败，因为目的为检验假设而非已知缺陷修复。真实不可见 NSWindow 中挂载生产 PromptCaretMarkerView 的 block 样式，分别保留默认 sizingOptions 和设为空；20 次替换尺寸／原生位置后逐项确认 frame 不被改写，并实际缓存绘制、确认中心红色非透明像素。caret-host-sizing-probe.log 一项通过（0.264s）：默认 invalidations=2、0.075282s，空选项 invalidations=3、0.064689s。计时含交付窗口及冷启动，固定顺序，不能当作公平性能提升证明。

caret-host-sizing-regression.log 与原生光标、pace 调度和统计观察范围共 33 项零失败零跳过（1.364s，墙钟 1.370）；再次局部记录为 0.061045／0.058450s。没有复现秒级停顿或尺寸失效显著减少，故不将空 sizingOptions 写入生产。局部小宿主不排除完整父页面约束传播，但目前不足以支持它是主要责任边界；后续继续检查完整练习图的更新范围和实际尺寸路径，不通过猜测性框架配置修改来宣称修复。本轮零 Typebar 主程序启动、无产品行为改变、无全量门禁，完整 goal 继续开放。

## 首键触发的失败前短采样（2026-10-10）

复用 80e090e Release QA 包，不重建／改产品；唯一 PID 46648、主会话 38242。首次尝试先启动一秒 sample 再通过工具按 planet 的 p，采样会话 6592 退出 0 后立即读取的运行日志还没有 input-started，故 stats-scope-pre-result-sample.txt 仅为输入前基线，不能声称覆盖首键。其主线程 854 样本、797 个事件等待样本。随后 stats-scope-short-sample-runtime.log 记录输入 0.000636s、首次 deliveryGap=1.273300、elapsed=1.229440、drift=0.229440、failed=0，提示三次合计 0.030217s；第二个迟交 0.659039s 后交付恢复约 100ms。活动状态 AX 实际显示 13s，后续日志到 23 秒仍 failed=0，再用 ⌘R 重置；不是完成或有效成绩，但新增生产倒计时能前进的实机证据。

第二轮 AX 确认新题首词 moss、未开始。先启动只读日志监听，发现第二个 input-started 才对同一 PID 执行一秒 sample；按 m 后不读 AX。采样会话 34063 退出 0，紧接着的日志快照只有 input-started（offset=44.887747）和 input-finished（44.888307），尚无本轮首次 timer 或 failed 记录。其后首次交付 offset=46.672746、deliveryGap=1.861920、preflight=0.000042、elapsed=1.784670、drift=0.784670、failed=1。三次提示渲染累计 0.032804s、最长 0.012044s，输入处理 0.000562s；之后 AX 确认计时失败／1/0/0/0。

stats-scope-input-triggered-sample.txt 主线程 806 样本；窗口布局分支 531，其下 NSHostingView.layout 的 450、render 375、flushTransactions 245 均嵌套，不相加。此窗口在首次失败交付之前，排除了“这些布局样本全部来自失败后结果页”的解释。实际包含 SwiftUI 图更新、尺寸约束、PromptFieldTextRun 比较及渲染，但不能由单一分支直接锁定特定控件，样本亦不是精确耗时或公平基准。下一步围绕练习页首键时的图更新／尺寸传播做可证伪的局部对照，而不是调整健康阈值或继续归因于统计秒刷新。

正常 ⌘Q 后主会话 38242 权威退出 0、pgrep 零 Typebar；本轮仅一个图形实例，退出后无界面查询。按根因调试技能保留错过输入的首次采样及成功对齐的第二次采样，未隐去反例。无产品修改、全量门禁或持续键入验收；完整 goal 与兼容缺口保持开放。

## 统计子树 Release 首键采样仍失败（2026-10-10）

冻结 80e090e 的生产代码，独立内存包 Typebar-Stats-Scope-20261010.app、bundle app.typebar.qa.statsscope20261010；stats-scope-qa-package.log 构建 453.67s、终态退出 0。只启动唯一 PID 46080／会话 38635，普通 30 秒模式，首词 signal。第一轮只按 s，随后等待五秒不读 AX；日志确认首次交付前已失败，之后 AX 确认计时健康失败、1/0/0/0。stats-scope-qa-runtime.log：输入处理 0.000772s，deliveryGap=1.680081、preflight=0.000048、elapsed=1.645473、drift=0.645473、failed=1；提示渲染三次合计 0.030948s，最长 0.010871s。统计观察隔离没有消除首键失败，不能当作完整性能修复。

同一实例点击重复本轮，AX 确认同一题目及未开始状态，然后启动 /usr/bin/sample 46080 8，在采样尚在运行时按同一 s；采样期间不读 AX。采样会话 16789 终态退出 0，stats-scope-first-input-sample.txt 保留。第二轮仍失败：输入 0.000291s、deliveryGap=1.786916、preflight=0.000044、elapsed=1.770983、drift=0.770983、failed=1；三次提示渲染合计 0.037335s，最长 0.014627s。采样完成后 AX 确认同样失败／1/0/0/0；采样本身会扰动性能，不把两轮数值差直接解释成产品差异。

不同于之前延迟结束后才开始的采样，此次覆盖首键前后。主线程共 6,179 个样本，其中事件等待 mach_msg2_trap 分支 2,874；NSRunLoop.addObserver 分支 1,351，其下 flushObservers 1,010、NSHostingView.beginTransaction 910 为嵌套计数，不能相加。另有显示事务／布局分支及 SwiftUI 图更新；样本包含失败后结果页布局，没有时间分段，不能把整个分支归为首键原因，亦不是耗时精确测量。下一步需把首键到首次交付的窗口与结果页阶段分开，定位父图更新／布局链，而非继续假设提示字符串组装或统计秒级读取是唯一原因。

按根因调试技能保留反证，没有降低健康阈值、删功能或再改产品来迎合结果。正常 ⌘Q 后主会话 38635 权威退出 0，pgrep 确认无 Typebar；无退出后 AX 查询、无第二实例。此轮仅新增实机诊断记录，无完整门禁／有效成绩／可见倒计时刷新验收，全部兼容缺口和完整 goal 继续开放。

## 生产统计子树观察隔离（2026-10-10）

将先前局部宿主对照接入生产：ContentView 拥有独立 LiveStatsClockSignal，LiveStatsClockContent 在自身 body 读取信号并执行最新统计闭包。统计不再直接读取父层 lastClockTickSecond；原始指标计算、整秒交付、计时健康阈值、声音、阈值判定和 Layout Fluid 消费者不变。两个重置入口同步清零。闭包随父视图重建更新，不缓存会话／设置或用 identity 强制重建。

行为优先：live-stats-production-scope-red.log 因尚未实现生产组件而编译失败，保留原始日志。实现后 verified.log 26 项零失败零跳过（9.430s，墙钟 9.435）。补入真实 TypingSession／外部时间源的生产子树对照后，live-stats-production-scope-final.log 42 项零失败零跳过（9.455s，墙钟 9.462）。无订阅倒计时保持 30s；父订阅及生产子树订阅均交付 29／20／10s。三个秒值交付时，父读取组求值 1→4，子树独读组 1→1；父 caption 改变及 20→0 重置仍正确显示。全部窗口不可见，不启动 Typebar 主程序。

补充时钟消费者首轮 44 项零失败但漏传参考导致一项跳过，不计完整对照；live-stats-production-clock-consumers-pinned.log 固定参考后 44 项零失败零跳过（0.776s，墙钟 0.781），覆盖单调时钟、pace、slow timer、计时健康、整秒补交、Layout Fluid 与实时阈值。定向筛选未命中的类名不算执行证据，以日志实际套件和方法为准。原创性脚本直接执行先退出 126（无执行权限）；改用 zsh 后 live-stats-production-scope-originality-zsh.log 退出 0。人工场景结构仍为 1,151 项通过，不代表人工验收。

会话内有界决策复核：生产组件的倒计时更新、父真实状态变化和重置反例已约束，但不是独立审查，也不证明完整 ContentView 输入／主题／布局耗时。Layout Fluid 仍可有意让父层观察秒值。此次零 GUI 启动、无全量门禁或新 Release 实机证据，之前普通计时失败仍未关闭；下一步以单实例 Release 验证此边界，完整兼容矩阵和 goal 维持未完成。

## 秒级观察范围宿主对照（2026-10-10）

按行为优先测试与会话内决策审查，先验证“统计子视图观察秒级数据能避免父页面重新求值”，而非直接大拆生产 ContentView。新增 LiveStatsClockScopeTests，使用现有平台 Observation、真实 NSHostingView 和不可见窗口：两种情况均让子视图显示每次秒值，只有一组父视图也读取该值。三个交付后父读取组 body 1→4，子视图独读组 1→1；两组真实父 caption 变化均重新求值并正确传到子视图，原有秒值保留。此为局部求值范围，不是布局或调度耗时基准。

首个 live-stats-clock-scope.log 因嵌套 private Observable 类型宏可见性编译失败，修正测试类型访问级别后 live-stats-clock-scope-verified.log 权威退出 0，与倒计时依赖测试共三项零失败，0.824s（墙钟 0.826）。探索性对照没有故意失败阶段，生产代码未改、零 Typebar 主程序启动。决策审查反例为子视图数据陈旧、父真实输入更新丢失、其他功能仍在父层读取时钟：前两个由本地 caption／秒值对照部分约束，生产输入、主题、重置和 layoutFluid／pace 依赖仍需实现时验证。不声称独立审查或根因修复；下一步建立生产统计子树观察边界，保留已有全局时钟语义。

## 统计秒级刷新 Release 验证未通过（2026-10-10）

50fbde4 独立内存 QA 包 Typebar-Stats-Clock-20261010.app 构建 447.15s，stats-clock-qa-package.log 权威退出 0。只启动一个实例／会话 7443；第一轮对首词 harbor 输入 h 并读取 AX，计时健康失败，1/0/0/0。stats-clock-qa-runtime.log 输入处理 0.000720s、deliveryGap=1.554999、preflight=0.000038、elapsed=1.535388、首秒 drift=0.535388、failed=1；提示渲染三次累计 0.028854s。未能在活动状态核实倒计时可见刷新。

在同一实例点重复本轮，仍输入 h，但输入后先等待五秒不读取 AX。首秒 deliveryGap=1.289072、drift=0.227002、failed=0；第二秒 deliveryGap=1.278197、preflight=0.000040、elapsed=2.505191、drift=0.505191、failed=1，对应窗口仅一次提示渲染 0.009688s。等待后的 AX 确认第二轮计时健康失败，1/0/0/0、约三秒。该轮否定“只有实时 AX 查询才会造成失败”，并提示每秒刷新引发的整页求值／布局范围需要定位；单次不同运行不能量化与旧包的回归差异，不能直接归因于新状态依赖。局部刷新机制仍有宿主证据，Release 接受性尚未通过，不将其视为已交付完整修复。正常 ⌘Q 后会话 7443 权威退出 0，pgrep 确认零 Typebar，无退出后 AX 查询、无第二实例。

## 实时统计秒级刷新依赖修正（2026-10-10）

针对上一轮 AX 倒计时滞后，源码核查 stats 用 Date.now 和 SessionElapsedClock 计算实时数值，却未直接读取 lastClockTickSecond；无布局流动等其他读取时，时钟写入该 State 不一定使统计子树重新求值。新增 LiveStatsClockDependencyTests，用真实 SwiftUI State、不可见 NSHostingView 窗口和独立可控 SessionElapsedClock 比较未读取／读取交付秒状态：无输入续写，时间依次推进 1、10、20 秒；未读取分支一直 30s，读取分支正确为 29s、20s、10s。此为宿主行为对照，不是对实际 AX 缓存行为的完全归因。

live-stats-clock-red.log 两项中一项失败：宿主对照通过，生产 stats 接线缺失断言失败。生产 stats 增加对已有 lastClockTickSecond 的显式读取，建立每秒求值依赖；仍使用当前真实时钟计算数值，不修改计分、健康阈值或采样，不增加定时器、不重建视图身份。live-stats-clock-verified.log 权威退出 0，统计依赖、空闲、实时指标和诊断共 25 项零失败零跳过，7.595s（墙钟 7.599）。本轮零 Typebar 主程序启动；未重新跑完整门禁或 Release GUI，新刷新会增加必要的每秒界面求值，其真实调度负载影响须实测。本修正不宣称解决普通计时健康失败，设备／视觉验收与完整 goal 继续开放。

## 单字符输入后无 AX 采样（2026-10-10）

复用累计诊断 Release 包，唯一实例 PID 40239／会话 71043，首词 thunder 只输入正确字符 t；随后先通过进程日志确认 started=1，再取五秒系统采样，期间不读取 AX。active-no-ax-sample.txt 采样权威退出 0，主线程 4212 个样本中事件等待分支 3896，不能解释为正在满负荷布局。采样开始前已经发生 1.258090s 交付间隔，三次提示渲染共 0.029751s、最长 0.010056s，首秒漂移 0.214364、failed=0；采样未覆盖最初延迟，因此不能据其等待分支否认首次布局问题。

active-no-ax-qa-runtime.log 后续交付约 100ms，终秒 elapsed=30.085863、drift=0.085863、failed=0。采样结束后 AX 仍读到 29s，而此前日志已到约 20 秒，提示倒计时呈现或 AX 状态滞后需单独核查；随后截图及完整 AX 确认最终闲置无效、1/0/0/0、30 秒，不当作持续键入验收或有效成绩。没有在采样中持续输入，没有验证该显示差异的视觉原因。正常 ⌘Q 后会话 71043 权威退出 0，pgrep 确认零 Typebar，无退出后界面查询、无第二实例、无产品改动。

## 空闲 AX 观察边界对照（2026-10-10）

复用 5f797f2 的同一个 Release QA 包，只启动一个实例（PID 40026，会话 99404），保持未输入、未开始状态。先用系统 /usr/bin/sample 采样五秒，无界面查询；然后另取五秒采样并在其中执行一次 getApp 的 AX 树读取。ax-boundary-quiet-sample.txt 和 ax-boundary-observed-sample.txt 的采样会话均退出 0。前者主线程 3715 个样本，其中事件等待 mach_msg2_trap 分支 3435；后者主线程 4197 个样本，对应等待分支 3526，并出现 208 个无障碍数组计数调用样本、其下 189 个 NSHostingView 无障碍节点生成样本。调用树有嵌套，不将这些数相加为耗时，也不将采样计数视作精确性能基准。

ax-boundary-qa-runtime.log 所有记录均 started=0，观察期有 0.347482s 延迟窗口且无提示渲染；退出阶段另有 0.810595s，不把它归因于活动输入。窗口焦点在两阶段并非严格受控，采样本身也可能扰动调度；该对照只证明读取 AX 会走额外框架路径，没有复现普通计时失败，更不证明 AX 是唯一根因。下一步需要活动输入期间的布局／观察边界证据。正常 ⌘Q 后会话 99404 权威退出 0，pgrep 确认零 Typebar，无退出后 AX 查询、无第二实例、无产品改动。

## 累计诊断 Release 单实例首轮（2026-10-10）

5f797f2 Release QA 包 Typebar-Render-Window-20261010.app 构建 451.75s，render-window-qa-package.log 权威退出 0；独立 bundle app.typebar.qa.renderwindow20261010、内存存储与显式诊断开关。只启动一次（会话 67743），普通 30 秒当前六词 copper paper orchard voyage summer orchard 全正确，43/0/0/0。输入及首次 AX 观察后停止输入、等待自然结束，最终界面为闲置无效而非计时健康失败，故不能当作有效成绩或持续键入验收。

render-window-qa-runtime.log 的交付间隔 1.320890s 对应提示渲染 3 次、累计 0.029202s、最长 0.010072s，首秒漂移 0.224819、severe=0、failed=0。另两个窗口 0.570532s／0.648672s 分别只有一次渲染 0.010384s／0.010532s。停止界面查询后，后续交付恢复约 100ms，终秒 elapsed=30.093403、drift=0.093403、failed=0；结果页面出现后仍有 1.787679s 窗口、四次渲染累计 0.025417s，不将终态布局当作活动输入的因果证据。该轮提示渲染同步计算不足以解释观测间隔，但没有证明 AppKit/SwiftUI 布局、自动化 AX、系统负载中的具体责任，也没有证明故障消失；下一步需区分这些边界而非继续盲改提示渲染。正常 ⌘Q 后会话权威退出 0，pgrep 确认零 Typebar，退出后无 AX 查询、无第二实例。

## QA 交付窗口累计渲染诊断（2026-10-10）

最新 Release 仍失败，而现有提示渲染诊断只输出超过 125ms 的单次调用，无法区分大量短调用与渲染之外的调度占用。新增 RenderWindow 数值累计器，记录 count/total/maximum，并在每次时钟交付时清零；仅交付间隔超过 250ms 时输出一行 typebar-render-window。统计明确标记 scope=process，多窗口共享累计量，不声称属于单一窗口；总耗时不代表全部布局或主线程工作，也不代替调用栈。累计与输出均受原有 QA 内存标记加环境变量双开关保护，在 MainActor 串行访问，不写 SwiftUI 状态、不缓存提示内容、不改变输入、评分、健康阈值或时钟调度。

按行为优先测试，render-window-red.log 因尚无 RenderWindow 类型编译失败；实现后 render-window-verified.log 七项零失败。测试计入 100 个 4ms 短调用和一个 20ms 调用，拒绝非有限或负时间，验证 drain 清空。补充生产接线顺序与启用保护检查后，render-window-final.log 权威退出 0，累计诊断和空闲探针共九项零失败，3.355s（墙钟 3.358）。本轮零 Typebar 主程序启动、未跑新的完整门禁或 Release 包；需新二进制实际运行才能得到累计数据，尚不能据此归因或宣称普通计时故障修复。

## 最新光标内容复用 Release 实例验证（2026-10-10）

在干净 7f99e8f 工作树打包 Typebar-Caret-Content-20261010.app，独立 bundle app.typebar.qa.caretcontent20261010，QA 内存存储与显式计时诊断双开关；复用当前 Release 构建 0.34s，包含 c5417e4 的光标本地内容复用生产代码。caret-content-qa-package.log 权威退出 0。启动前确认零 Typebar/xctest，只启动一个 QA 主程序（会话 28535）。普通时间 30 秒界面通过原生输入输入六个当前目标词 ripple orchard canyon quiet violet signal，结果明确显示计时健康失败、42/0/0/0、6/6 正确，不保存成绩。

caret-content-qa-runtime.log：首次输入处理 0.000711s；后续 deliveryGap=2.230042、preflight=0.000040、elapsed=2.201440、首个到期秒 1、drift=1.201440、severe=1、failed=1。输入前也记录 0.902941s 的调度间隔，说明不能将全部延迟直接归因于首次输入。没有超过 125ms 的单次提示渲染记录，不排除大量短调用或 SwiftUI/AppKit 布局；原生界面自动化仍可能扰动调度，此轮无调用栈采样。实测否定“现有光标内容复用已解决普通计时故障”，不作量化性能比较。正常 ⌘Q 后会话 28535 权威退出 0，pgrep 确认零 Typebar；退出后没有再次查询 AX 或截图，未启动第二实例。实际普通计时故障与完整功能验收继续开放。

## Caps Lock 同值写入局部对照（2026-10-10）

完整门禁后继续排查普通计时延迟。生产 advanceClock 每 100ms 写入 capsLockEnabled，先前 ClockIdleInvalidationTests 未覆盖 Bool 状态同值赋值。按根因调试及行为优先测试技能扩展探索性探针，不预设失败或修改生产代码：在真实 SwiftUI @State、NSHostingView 和不可见窗口中，比较规则同步／tick 四种组合与是否重复写入 Caps Lock 的八种组合；增加真实 Caps Lock 变化的正对照，保留真实输入正对照与窗口不可见检查。测试不读取或改变系统 Caps Lock，只使用确定性的 Bool 状态。

clock-caps-invalidation.log 与格式化后 clock-caps-invalidation-final.log 均权威退出 0；后者包含诊断记录测试共 7 项零失败，3.825s（墙钟 3.828）。八种组合的空闲 body 计数均 1→1、输入后均 2→2，真实 Caps Lock 变化仍更新。此局部证据不支持“同值 Bool 写入单独造成持续重绘”，不证明完整 ContentView 或主线程健康，也不构成实际计时故障修复。生产代码未变、零 Typebar 主程序启动；下一步仍需完整应用新二进制下的入口证据。

## 契约修正后的完整门禁（2026-10-10）

在已推送 bd4b30d 的干净工作树上重新执行 check-native-rewrite-readiness.sh，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41、Redis 6.2.6 与 Anime.js 4.2.2 归档。会话 11000 权威退出 0；完整日志 caret-contract-readiness.FOUyOi.gate.log，74 份分项日志保留在 work/caret-contract-readiness.FOUyOi/。原生 4170 项零失败、零跳过，889.727s（墙钟 890.213）；服务 501 项零失败，12.995s（墙钟 13.065）。两个历史契约冲突用例均在完整测试中通过，万词自定义文本用例 7.081s 通过。

Release 构建 425.42s 完成，未打开的应用包签名、资源边界及原创边界检查通过，最终输出 native rewrite readiness check passed。本轮从源码对照到打包全过程代码冻结、零 Typebar 主程序启动。此门禁验证固定源码行为探针、原生及自托管服务测试与包边界，不代替实机 GUI、设备 IME、视觉主题或完整人工验收。配置仍有四项部分覆盖，官方主题精确色彩覆盖仍为 0/187，普通计时实际应用延迟失败仍开放；完整重写 goal 保持 active。

## 完整门禁发现的历史断言契约冲突（2026-10-10）

c5417e4 完整门禁的原生测试权威退出 1：4170 项、4 次断言失败，885.437s（墙钟 885.911）。失败集中于两个用例；服务与打包阶段尚未执行。原始完整日志保留在 work 下 typebar-native-rewrite-readiness.rmWYxW/client-tests.log 对应系统临时目录，整体日志为 caret-content-readiness.YNiz6S.gate.log。CoreData 错误输出不是这四次断言失败的归因。

核查当前实现与独立回归后，旧 pace 用例配置 mainStyle.off，却要求主光标初始化额外读取一次文字；修正为两个逻辑 pace 请求，并新增主光标没有位置的断言，原有插值、目标位置和重复请求不重启断言保留。旧焦点集成用例要求不变快照重复送达；改为去重后的通知序列，仍验证真实返回及移除视图后不观察旧窗口。产品代码没有改动，未放宽计时或几何正确性。fullgate-contract-reconciliation.log 权威退出 0，相关三个测试组 21 项零失败，0.891s（墙钟 0.895）。本轮零 Typebar 主程序启动；这只是局部契约核对，不代表整轮门禁或完整功能等价通过，需重新运行完整门禁。

## 光标纯位移保留本地标记内容（2026-10-10）

基于 029285d 核查 PromptCaretNativeView.paint：旧判断只有原生 frame 与样式／颜色／尺寸全相同才跳过；平滑移动改变 frame 时仍赋值 NSHostingView.rootView。PromptCaretMarkerView.body 仅使用 rect.width／height、style、accent，所有本地形状均不读取文档原点，因此纯位移不需要替换 SwiftUI 标记内容。这个机制是已定位的冗余工作，不等于完整应用计时失败的根因。

按行为优先测试技能，caret-translation-content-red.log 一项七次预期断言失败：七种可见样式平移后 rootView.rect 被改为新文档坐标。修正将更新拆开：只在样式、颜色或尺寸变化时替换 rootView，只在 frame 变化时赋原生 frame；初建、隐藏／显示、alpha、文档定位、RTL 锚点公式、pace 请求和计时器均保持。局部内容保留上次构建原点是有意语义：文档位置属于 NSView.frame，不参与标记 body；没有缓存提示文字或输入状态，也没有跳过新的目标几何。

首项测试遍历七种可见样式，验证 frame 确实平移、内容保留、尺寸变化及主题颜色更新仍送达。补充主／pace 双标记在四个换行动画采样点的内容保留、frame 与各自 coordinator 文档位置一致、前后层顺序不变。caret-translation-content-verified.log 302 项零失败零跳过；补测后 caret-translation-content-final.log 权威退出 0，303 项零失败零跳过，18.169s（墙钟 18.201），带固定参考与归档，覆盖光标、blink、pace、组合投影、焦点及相关健康检查。

风险审查核对了 body 不使用文档原点、尺寸／样式／颜色失效键、主／pace 共用 paint、原生位置与插值、停止生命周期及既有 blink 断言；没有更改视觉选项、接受输入、计分、保护阈值或持久化。caret-translation-originality.log 原创边界通过，人工文档结构审计保持 1151 个唯一场景，git diff --check 通过。本轮零 Typebar 主程序启动，未测完整 GUI 帧率或首键计时表现；不宣称可量化加速或延迟故障已解决。全量 readiness、设备 IME、主题与完整人工功能验收仍开放，下一步完整入口实测须使用新二进制而非先前的 release 包，完整 goal 保持 active。

## 语言 Picker 禁用与专注动画局部对照（2026-10-10）

基于 47a19b2 核查首键之后的配置区：practiceLayout 对整个 configurationPanel 应用 opacity、allowsHitTesting、disabled、accessibilityHidden 及 125ms 动画；语言 Picker 的普通模式选项是 TypingLanguage.allCases，当前 448 项（包括合成目录项，不将该数改写为独立语言数量）。首键会由 TypingVisualFocus.inputDidUpdate／hasStarted 触发专注状态。先检验“该 Picker 的禁用／专注变更本身足以造成秒级工作”的局部机制，而非凭完整应用采样直接替换控件。

按行为优先测试技能建立探索性 LanguagePickerInvalidationTests，无故意失败阶段，产品源码未改。使用真实 SwiftUI @State、NSHostingView、从未显示的 NSWindow，比较两项与完整目录；分别只禁用和追加同类专注外观修饰，四次交替状态切换。probe 断言 body 确实更新、禁用状态已交付、英语选择保留及窗口不可见；回调在 defer 清除并卸载关闭窗口。耗时仅输出，不固定性能门槛、不固定框架内部 body 次数，且测试不是用户实际点击、无障碍选择或完整 ContentView 验收。

最初 language-picker-invalidation.log 一项通过，30ms 固定交付窗口内，两项切换约 38–40ms，448 项约 143–146ms；说明有目录相关开销，但未复现一秒以上阻塞。补充专注动画后统一使用 200ms 交付窗口，足以跨过声明的 125ms 动画时长；不可见窗口也可能不实际播放可见动画，不冒称实体帧验收。language-picker-focus-invalidation.log 17 项零失败但缺固定参考有一项跳过；补齐参考与 Anime.js 归档后 language-picker-focus-pinned.log 权威退出 0，17 项零失败零跳过，7.665s（墙钟 7.668）。

最终原始观察：只禁用的两项切换约 210–214ms、448 项约 318–324ms；专注外观两项约 210–214ms、448 项约 319–326ms，均包含固定 200ms 交付窗口。完整目录初次挂载约 475–485ms，两个选项约 222–249ms，含冷初始化及交付；固定顺序、单次本机观察，不作统计显著性推论。局部控件没有复现已观察到的秒级延迟，但不能因此排除完整配置区累计工作、可见布局／显示或 AX 扰动。保持原语言 Picker，不将减少选项或删除交互功能作为修复。

另核查 TimerHealthPolicy.monitors：custom、quote、zen 不监测失败，不能用“切换到没有语言 Picker 的 custom 后不失败”证明控件是根因或问题修复；如做跨模式对照，应比较实际交付间隔／drift，并明确不同模式语义。格式化后的 language-picker-focus-final.log 再次权威退出 0，17 项零失败零跳过，7.955s（墙钟 7.965）；language-picker-originality.log 原创边界通过，人工文档结构审计保持 1151 个唯一场景，git diff --check 通过。本轮零 Typebar 主程序启动，不重跑全量 readiness 或升级人工验收。下一步仍需定位完整入口在失败前的主线程交付工作，完整重写 goal 保持 active。

## 优化构建对照与显式打包配置（2026-10-10）

核查 bbd5e1f 的打包脚本，两次 swift build 都未传配置，此前 GUI 样本均来自默认 debug。新增 TYPEBAR_BUILD_CONFIGURATION，默认 release，显式 debug／release 均可；非法值在构建及创建应用前拒绝，构建和 --show-bin-path 使用同一个已校验值。保留既有输出拒绝覆盖、QA 内存容器、标识定制及 ad-hoc 签名，不改客户端计时／输入实现或保护阈值。README 补充调试配置及已知计时故障边界。

PackagingConfigurationTests 启动实际打包脚本，但以临时 swift／codesign 替身记录调用和提供占位二进制：默认、两种显式值、非法值四组，核查构建／查找参数一致、文件拷贝、非法值零构建／零应用目录。packaging-configuration-red.log 一项六次预期断言失败；修正后 packaging-configuration-verified.log 权威退出 0，一项零失败零跳过，1.488s（墙钟 1.490）。该测试不是优化器或真实签名证据。选择遵循行为优先测试技能；风险审查另查了包自检没有固定 debug 二进制路径。

实际 release-comparison-package.log 句柄 14001 持续轮询直到权威退出 0，未因日志暂未更新而重开；首次优化构建 474.36s，日志明确 Building for production。生成 Typebar-Release-20261010.app、bundle app.typebar.qa.release20261010；codesign --verify --deep --strict 退出 0，TypebarQAInMemoryStore=true。临时编译冻结期间未修改输入文件。

本轮只启动一个 release 主程序，句柄 39020，经 ⌘Q 正常退出 0，最终 pgrep -x Typebar 无匹配；退出后不再调用 GUI 观察。release-comparison-runtime.log 第一轮时间 30 秒输入 bright meadow tangent summer orchard planet，AX 确认 44/0/0/0 UTF-16、6/6 正确，但结果计时失败且不保存；首键处理 0.652ms，交付间隔 2.232127s、preflight 0.037ms、elapsed 2.207684、drift 1.207684、failed=1。同一实例重开，正确首键 s，AX 确认 1/0/0/0，处理 0.258ms，交付间隔 1.654356s、preflight 0.041ms、elapsed 1.544048、drift 0.544048、failed=1。Charts 固定尺寸诊断保留，不把环境提示算成测试断言失败。

两种输入在优化构建中仍失败，反驳“debug 配置是故障的唯一原因”；词序、时序不同，且 GUI 自动化／AX 仍存在，不能据此统计优化收益、断定优化无影响或排除观察扰动。release 打包是正常交付配置改进，不宣称计时根因已解决；普通计时人工验收不升级。release-package-boundary-check.log 权威退出 0，实际 release 包的签名、关键元数据、资源边界及固定参考原创检查通过（复用构建 0.35s）；人工文档结构审计保持 1151 个唯一场景，git diff --check 通过。未执行全量 readiness、release 全量 XCTest、设备 IME、所有配置／主题等完整功能验收，完整 goal 保持 active。

## 隐藏主光标延后几何与分时段采样（2026-10-10）

基于 e0dd241 的空定位探针修正已证实的隐藏主光标浪费：PromptCaretNativeView.present 先读取最新可见性，只在主样式绘制标记且可见时解析主光标几何。隐藏期间不消耗 input／needsPosition／needsSnap，恢复可见时仍读取最新输入、组合和字形定位；主光标关闭后重新启用也重新定位。pace 请求、插值、计时器及独立绘制继续执行，blink 时钟仍由同一个最新可见性快照更新。没有调整健康阈值、调度频率、输入规则或成绩处理，也没有持久跨帧缓存旧 rendering。

按行为优先测试技能先运行 caret-hidden-render-red.log：两项、七次预期断言失败，旧实现隐藏期间十一帧仍读取十一遍 rendering。修正后新增覆盖隐藏组合输入变化、布局 reset／invalidate、恢复新位置、隐藏主光标时独立 pace 步进，以及关闭／重新启用主标记。风险审查发现提前读取展示回调需保留最新输入回调后的退役守卫；caret-hidden-retirement-red.log 一项两次预期失败，证明同步 stop 后仍会读一次旧展示回调。现在在输入与展示 provider 返回后分别检查配置 attempt／coordinator，退役后不继续读取旧展示或解析几何。弱捕获退役测试覆盖两种回调，避免引入视图持有环。

中间 caret-hidden-render-pinned.log 321 项通过；补充关闭主标记测试后 caret-hidden-render-final.log 322 项通过。最后 caret-hidden-render-retirement-final.log 权威退出 0：323 项零失败零跳过，18.060s（墙钟 18.094），带固定参考与 Anime.js 归档，包含原生光标、blink、pace、组合投影、焦点、运行期规则及相关健康回归。caret-hidden-render-originality.log 原创边界通过，人工文档结构审计保持 1151 个唯一场景，git diff --check 通过。当前更改无新增依赖；代码风险审查未发现未处理的阻断项，但组件测试不是设备 IME 或浏览器视觉一致性验收。

本轮只启动一个隔离 Typebar-Hidden-Caret-20261010.app（bundle app.typebar.qa.hiddencaret20261010、内存成绩容器、诊断双门控），主句柄 62830 通过 ⌘Q 正常退出 0，最终无 Typebar 残留，退出后没有再观察 GUI。GUI 二进制包含可见性修正，但不含之后增加的 provider 退役守卫；最终守卫由上述组件回归验证，未为它再启动主程序。

caret-hidden-render-runtime.log 普通时间 30 秒首轮输入 window tangent canyon thunder copper planet，44/0/0/0 UTF-16、6/6 正确。首键处理 0.971ms，首个整秒交付间隔 1.405462s、drift 0.361439、failed=0；最终间隔 1.393809s、elapsed 7.678507、drift 0.678507、severe=3、failed=1，原生结果页仍显示保护停止、不保存。可见性修正不解决失败前的整个计时故障，普通计时人工验收仍未通过。

在失败结果页已经显示后单独 /usr/bin/sample 57321 8 1，caret-hidden-terminal-sample.txt 6404 个主线程样本，29 个进入光标定时器，未采到 ContentView.renderedPrompt 或 PromptRendering.make。然后同一实例点“再来一次”，保持尚未输入状态，caret-hidden-preinput-sample.txt 八秒采样 6785 个主线程样本，51 个进入光标定时器，也未采到上述整段重建。两个 sample 句柄 64180／34061 均正常退出 0。这比上轮混合终态的采样边界更清晰，但采样未命中不是“从未执行”的证明，也不能与旧混合采样比例作统计性能对比。

最后同一未开始轮次启动十秒 caret-hidden-input-sample.txt（句柄 7691 退出 0），按正确首键 d；输入处理 0.850ms，随后交付间隔 2.114539s、elapsed 2.070129、drift 1.070129、failed=1，AX 确认 1/0/0/0、计时失败。此采样跨输入及失败后，8272 个主线程样本含 AppKit／SwiftUI 布局、显示与无障碍路径，未采到上述整段 rendering 重建；不能直接将这些框架调用聚合归因于计时故障，也不能忽略 sample／AX 的观测扰动。下一步应限定失败前的窗口，区分 SwiftUI 布局／显示交付与其他主线程工作，不能继续用终态空定位热点作为唯一根因。未执行全量 readiness、设备 IME 或升级人工验收，完整重写 goal 保持 active。

## 焦点去重后的完整应用反例与空定位对照（2026-10-10）

实际运行 14e29a9，隔离应用 Typebar-Focus-Delivery-20261010.app、bundle app.typebar.qa.focusdelivery20261010、内存成绩容器，QA 计时诊断双门控开启。本轮仅启动一个主程序，句柄 96600 正常退出 0，未重启或强杀；退出后只检查进程，没有再调用可能拉起应用的 GUI 观察接口，最终 pgrep -x Typebar 无匹配。

window-focus-delivery-runtime.log 第一轮时间 30 秒：物理路径首键 v 的处理 0.850ms，首个整秒交付间隔 1.338037s、elapsed 1.284930、drift 0.284930、severe=1、failed=0；随后输入完整 violet thunder canyon，22/0/0/0 UTF-16、3/3 单词正确，但交付间隔 1.322272s、elapsed 6.741227、drift 0.741227、severe=2、failed=1。原生结果页明确显示计时调度持续延迟、停止且不保存成绩。因此焦点去重不是完整故障修复，不升级普通计时验收。

同一实例点“再来一次”，输入 orchard willow lantern，23/0/0/0、3/3 正确；首键处理 0.481ms，随后间隔 2.726640s、preflight 0.174ms、elapsed 2.703937、drift 1.703937、failed=1。此轮同时执行 /usr/bin/sample 53592 12 1，句柄 62793 退出 0，日志 window-focus-delivery-main-sample.txt；采样本身也可能扰动时序，不能把第二轮用于无扰动性能比较。

主线程 9456 个样本中，1769 个进入原生光标定时器，1717 个经 present → latestRendering → renderedPrompt。聚合样本包含失败前与失败后，不能将比例换算为失败前耗时或直接判定因果。源码 present 的重建条件是输入变化、needsPosition 或主光标位置为空；TypingSession.promptCaretGlyphIndex 在 isFinished 时直接返回 nil。这意味着终态也可能产生同一个采样热点，须先区分时段，不能把失败的后果误认为原因。

新增原生组件探针 testUnresolvedFreshGlyphRecoversWithoutConfigurationUpdate：固定输入身份，分别以 nil 与字形 ID 不在映射内作为无法定位条件，11 次 present 均观察到 11 次 rendering 读取；改为有效字形后无需配置更新即可恢复位置，之后 11 帧不再重建。探针只输出重试次数，不把当前逐帧重建冻结为必须保留的行为；断言保护空定位与后续恢复及稳定帧不重建。这是探索性对照而非已选定的产品修复，因此按行为优先测试技能不制造预期失败，产品源码未改。

首次聚焦回归 28 项零失败但一项因缺少固定参考跳过；补齐参考与锁定归档后 window-focus-caret-unresolved-pinned.log 权威退出 0，28 项零失败零跳过，0.489s（墙钟 0.493）。window-focus-caret-probe-originality.log 原创边界通过，人工文档结构审计保持 1151 个唯一场景。未重跑全量 readiness、设备 IME 或人工验收。下一步应对终态空定位及失败前重建触发条件分别建立有界观测，保留真实输入／组合变化时的新鲜几何语义；不能以禁用计时保护、放宽阈值或永久缓存替代根因修复。完整 goal 保持 active。

## 原生窗口焦点交付去重（2026-10-10）

基于 8bf86c5 核查完整入口：NativeTypingInput.updateNSView 每次刷新都会报告窗口焦点，ContentView.handleTypingWindowFocusChange 最后无条件调用 updateFocusWarningDelay，递增 @State focusWarningSequence。重复报告存在形成视图更新反馈的路径，但尚未证明这是既有普通计时故障的完整根因。window-focus-delivery-red.log 两项测试出现五次预期断言失败：初次挂载加二十次无变化刷新产生二十一次相同报告，通知与刷新也重复交付。

TypingInputView 现在按窗口身份、键窗口状态、是否附有 sheet 去重；回调前提交状态，防止同步 refresh 重入。真实窗口移动／卸载清除状态，重新挂载仍建立初始焦点。makeNSView 提前安装接收者，避免初次挂载报告被默认空回调消耗。保留既有观察者清退、输入解释、首响应者、计分、时钟及健康阈值；不将每次 SwiftUI 更新视为一次真实焦点变化。

四项原生组件测试覆盖重复刷新、键窗口通知、sheet 状态、同状态窗口迁移／重新挂载、同步回调重入和旧窗口通知清退。窗口从未显示；sheet／key 属性由测试窗口控制，并非系统实际弹窗或人工切换窗口验收。首次广泛回归漏配锁定 Anime.js 归档，251 项出现 24 次失败及两项跳过；补测新增测试时另有一次闭包参数编译错误，已修正，没有把上述运行记为通过。最终 window-focus-delivery-pinned-final.log 权威退出 0：253 项零失败零跳过，16.444 秒（墙钟 16.471），包含组合投影、原生输入、运行期规则、焦点、计时和结果退出组件回归。

按风险审查技能复核了初始接收者时机、迁移失效、回调重入和观察者生命周期；window-focus-delivery-originality.log 原创边界通过。此轮零 Typebar 主程序启动，未执行完整应用 GUI、设备 IME、全量 readiness，亦未升级人工验收状态。下一步须以一个隔离 QA 实例检查连续输入与普通计时；当前不宣称首次计时延迟已解决，完整重写 goal 保持 active。

## 无变化时钟操作的 SwiftUI 重算对照（2026-10-10）

基于 5380f87 核查实际 advanceClock：每次 100ms 交付先同步规则、读取 Caps Lock、核验挑战字体，再检查终态、整秒健康／阈值，最后 session.tick；tick 的单调计时采样只在操作内保存并清除，另推进 pace 状态及检查计时完成。方法是 mutating 不足以证明每次都使 SwiftUI 重算，不能据此擅自减少频率、跳过 pace 或 live rules。

新增 ClockIdleInvalidationTests，以真实 TypingSession.withElapsedClock(.system)、SwiftUI @State、NSHostingView 和从未显示的 NSWindow 组件记录 body 求值。四种组合为无操作、规则同步、tick、同步加 tick；分别执行四次操作并刷新布局／主循环，每次 30ms 刷新只是测试交付窗口，不是生产调度改动。初始 clock-idle-invalidation-baseline.log 一项通过：无操作 1→1、仅同步 1→2、仅 tick 1→1、组合 1→1；这是一次原始观察，不把一次初始化重算当作持续重绘，也不固定 OS 内部求值次数作为契约。

随后加入真实 insert("a") 的正向控制以及开始后四次操作，避免把未交付视图更新误判为没有 invalidation。clock-idle-invalidation-controlled.log 权威退出 0：69 项零失败零跳过，2.470 秒（墙钟 2.478），含运行期规则、单调时钟、pace clock、整秒及慢计时回归。四种组合未开始时均 1→1；真实输入均触发重算并显示 typed=a／hasStarted=true，开始后无额外输入的四次操作均 2→2。断言保证真实输入会触发更新、规则／输入状态正确、窗口不可见；无变化操作的次数只输出证据，不采用脆弱的框架内部次数硬断言。最初规则同步单独出现一次重算未在第二次运行复现，原始日志均保留。

这反驳最小组件中的“无变化同步／tick 必然持续重绘”假说，不证明完整 ContentView 的 Caps Lock、焦点、组合、视觉效果、原生计时器及物理输入回调也不重绘。没有故意失败测试：本轮是建立可证伪机制的探索性组件探针，产品实现未改。后续应继续核查完整输入事件与焦点／组合变化、主线程总工作和计时任务交付，不能凭该局部结果排除完整应用问题。

按风险审查技能复核，探针回调在 defer 清除、窗口卸载关闭，避免 State 捕获环与组件残留；不创建真实账户、成绩、偏好或可见窗口。clock-idle-invalidation-originality.log 原创边界通过，退出 0；本轮零 Typebar 主程序启动，最终无残留。未重跑全量 readiness、设备 IME 或人工验收，首次计时故障及完整 goal 仍 active。

## TextKit 范围排版实验未采用（2026-10-10）

基于 bf13df5 检查普通光标几何：两个 PromptCaretLayout.rect 入口都显式 ensureLayout(for: container)，再读取目标矩形。核验本机 macOS 26.2 SDK 主来源 `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSLayoutManager.h:168–174,278–291`：支持 ensureLayoutForCharacterRange，TextKit 仍可扩大生成／布局范围，连续布局会扩至文首；glyphRange 对连写／组合字符可扩张，boundingRect 返回容器坐标。这不承诺范围请求一定更快，编译面向最低 macOS 14 也不等于在 macOS 14 设备执行。

新增 PromptCaretRangeLayoutTests，使用独立 NSLayoutManager 全量布局 oracle 对比现有生产字符偏移及 UTF-16 范围入口，再在测试内部对比目标范围请求。三种宽度、双方向、每个目标字符覆盖普通词、换行／空行、Tab、组合附标、emoji／ZWJ／旗帜、阿拉伯／混合方向、CR/LF；另有 123／2403／12003 字符长题首部、中部、尾部及显式小字体、baseline、负 kern 提示，保留无效范围 nil 检查。它验证本机原生几何一致，不验证实体 IME 候选、浏览器像素或完整应用 FPS。

先前 caret-range-layout-red.log 两项有两次预期源码门禁失败，几何对照通过；随后短暂将两个产品入口改为请求目标范围，caret-range-layout-verified.log 148 项零失败但一项缺参考而跳过。补齐参考与动画归档并增加长题后，caret-range-layout-pinned.log 275 项零失败零跳过（26.260 秒，墙钟 26.298）。这些结果不能证明性能优势；初次耗时比较一侧还包含字符索引转换，不能直接作公平速度比。因此撤回全部产品改动及临时必须采用范围 API 的源码断言，保留实验在测试内，最终产品源码与 bf13df5 相同。

公平对照使用同一测试函数、相同已算好的 UTF-16 范围、相同存储／字体准备，仅切换 ensureLayout 请求：caret-range-layout-rejected-final.log 权威退出 0，274 项零失败零跳过（27.400 秒，墙钟 27.433）。12003 字符首部全量／范围约 5.70／6.11ms，中部 6.13／5.65ms，尾部 5.36／6.06ms；这是单次、固定先全量后范围的原始观察，不统计显著性或可靠提升。范围请求没有显示稳定优势，也未复现应用秒级交付问题，故不作为修复交付。后续应继续检查完整应用累计工作／任务交付，不能从这一局部反证排除所有 TextKit 或主线程问题。

caret-range-layout-originality.log 退出 0，固定参考 pin 的原创边界通过。风险复核的结论是保留现有产品路径、只增加几何与实验守卫；没有新依赖、缓存、阈值、输入、计分或持久化修改。原始实验日志保留，本轮零 Typebar 主程序启动、最终无残留；不重跑完整 readiness 或升级人工验收，首次延迟与完整重写 goal 仍 active。

## 同步面板渲染复用与后续输入反例（2026-10-10）

先建立独立组件基线而非猜测性改字符计数。新增 PromptRenderingAssemblyTests 对比逐段原生 AttributedString 前缀偏移 oracle，覆盖空段、组合附标、CR/LF 跨段合并、区域指示旗帜、ZWJ、阿拉伯及候选字符串，逐字属性、渲染顺序和空词身份不变。prompt-assembly-baseline.log 两项通过；100／500／2000 个简单双字符 ASCII 单元组装约 0.44／2.35／9.69ms，没有支持秒级组装假说。prompt-assembly-host-baseline.log 三项通过；离屏 NSHostingView 的 60／300／1200 字形首次布局约 108.13／0.80／0.99ms，颜色更新约 0.89／0.35／0.49ms。首次包含框架冷启动，不能直接作长度比值；简单固定文本、无窗口／完整 ContentView、无自动化输入／IME，不能代表实际应用性能。时间仅输出证据，无脆弱墙钟性能通过阈值。

源码发现一次普通 typingPanel 构建中 viewport 的 text、两个组合字段条件及 practicePrompt 各自调用 renderedPrompt。改为一次同步 let rendering，并显式传给 practicePrompt(rendering:)；无跨帧缓存、会话写入或规则变化。异步主光标 latestRendering、Tape／ASL／Choo 的最新会话投影仍按请求读取当前状态。字体 revision 依赖保留。panel-render-snapshot-red.log 源码门禁一项七个预期失败，不是实际计时行为红测。首轮 panel-render-snapshot-verified.log 348 项有四失败一跳过：两处旧变量名检查，以及缺 Anime.js 固定归档的参考探针。只更新同含义检查中的局部变量名，补 TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE，原始失败日志保留。panel-render-snapshot-pinned.log 权威退出 0：348 项零失败零跳过，31.285 秒（墙钟 31.325）。原创边界 panel-render-snapshot-originality.log 退出 0。同会话风险复核未发现跨异步复用；不是独立审计或全量验收。

构建新隔离包 ../../work/Typebar-Panel-Snapshot-20261010.app，独立域 app.typebar.qa.panelsnapshot20261010、内存记录，panel-render-snapshot-package.log 退出 0。原始运行句柄的日志 panel-render-snapshot-runtime.log：普通 30 秒题首次 l 处理 0.000819 秒，首次交付间隔 1.262959、elapsed=1.229689、drift=0.229689、severe=0、failed=0，之后到第 16 秒未失败。这比此前样本不同，但题文／环境不同，不给出确定性能提升比例。继续 typeText 输入 antern canyon voyage 后，第 17 秒 drift=0.430164、severe=1；第 18 秒交付间隔 1.254772、drift=0.684953、severe=2、failed=1。实际结果为计时失败、不保存、22/0/0/0、3/3 词正确。它明确证明同步复用未消除全部计时故障；不能只凭首次暂未失败宣称修复。没有单次慢重建记录。

退出操作原始主进程正常退出 0，但同一工具调用随后读取 AX 意外重新唤起应用，出现由 launchd 托管的 PID 39735（PPID 1）；原始日志不覆盖这个重启进程。立即只发 ⌘Q、不再读取 AX，随后 pgrep 无 Typebar。两次实例先后存在，无证据表明并发运行，但本轮不能写“总共只启动一个实例”。没有 TERM；记录并改进退出验证流程：主进程权威终态后只查进程，不调用可能唤起应用的 UI 状态读取。真实用户域未改，测试包数据仍隔离。未重跑完整 readiness／实际设备 IME，完整 goal active。

## 固定字数模式的题长反向对照（2026-10-10）

本轮仅启动一个已有隔离 QA 包 Typebar-Render-Duration-20261010.app，二进制对应 b7ca8d6；当前仓库 6cca172 仅增加文档，无产品差异。独立偏好域 app.typebar.qa.renderduration20261010、内存记录，屏幕键盘全程关闭，English／字数模式／正确首字母物理输入，按 10 → 200 → 10 词执行。每次通过同一自定义字数编辑器应用并重开，题文随机生成，不声称逐字相同；没有切换健康策略或模式。完整数值证据为 ../../work/word-length-timer-runtime.log。

第一轮 10 词：input duration=0.000703；首个迟到交付间隔 0.969600 秒（尚未到整秒），首次 due=1 时 elapsed=1.340192、drift=0.340192、severe=1、failed=0；之后第 2–8 秒 drift<0.1，没有失败。重开并设为 200 词：input duration=0.000689、首次交付间隔 1.990824、preflight=0.000064、elapsed=1.977275、drift=0.977275、severe=1、failed=1；AX 确认计时失败、不保存。该字数失败结果显示 0/0/0/6 而输入字符 1 UTF-16 单位，这是本次原始结果，不套用时间模式的 1/0/0/0。

第三轮回到 10 词：input duration=0.000463；首个迟到交付间隔 0.935228，首次 due=1 时 elapsed=1.189290、drift=0.189290、severe=0、failed=0；第 2–8 秒 drift<0.1，没有失败。两次短题都没有完成，仅说明所观察时间内未触发致命健康保护，不证明有效练习或保存通过。三轮都处于 0<wordLimit<250 的同一健康门禁；反向恢复加强了题长相关证据，减少单纯模式差异／启动顺序解释，但随机题文、窗口布局和自动化观测仍不能完全分离，不宣称题长已是唯一根因。

没有 prompt-render-finished 记录，单次完整重建超过 125ms 仍未观测到；下一步应定位长提示累计布局／更新与计时交付的关系，不用跨帧旧投影或放宽健康阈值掩盖故障。第三轮第 8 秒后 ⌘Q，唯一主进程权威退出 0，随后无 Typebar；无 TERM 或第二实例，保留末尾 Charts 尺寸回退诊断。没有改真实用户域或保存成绩，本轮只采证与补文档，未重跑全量测试，完整 goal active。

## 物理输入与屏幕键盘的同实例对照（2026-10-10）

被测 b7ca8d6，复用已签名 QA 包 Typebar-Render-Duration-20261010.app（独立偏好域、内存记录），本轮仅启动一个主进程。virtual-input-timer-runtime.log 保存完整数值记录。第一轮普通时间 30 秒，物理单键 m：input duration=0.000702、deliveryGap=1.809123、preflight=0.000077、drift=0.793643、failed=1。点击再来一次，展开屏幕键盘，在新题 orchard 首字上点击原生“输入 o”按钮：input duration=0.000535、deliveryGap=1.797622、preflight=0.000063、drift=0.782622、failed=1。两次 AX 结果均为失败且不保存、1/0/0/0。生产 VirtualKeyboard.onInsert 直接调用 handleInsertedText(origin: .virtualKeyboard)，不经过 NativeTypingInput.keyDown 的 interpretKeyEvents；因此该物理键盘解释路径不是复现的必要条件，但两次都使用自动化 UI 操作及 AX 观测，未排除其共同扰动。

同一实例再次重开，保留屏幕键盘，切换默认 50 词题并点击首字 m。input duration=0.000426，首次交付间隔 1.456375、elapsed=1.415457、drift=0.415457、severe=1、failed=0；随后第二次 drift=0.094222，从第三秒到第 21 秒 drift 均低于 0.1 秒，没有 failed=1。源码 TimerHealthPolicy.monitors 对 0<wordLimit<250 启用，同一 0.500 秒致命漂移阈值，因此不是字数模式关闭健康检查。首次严重漂移仍发生，且只输入一个字母，不能当作完整有效完成或性能通过。模式、提示长度及开始时可见控件同时变化，不能从一次对照推断长度是唯一原因；下一步需要固定模式与可见控件的长度对照或更精确的累计主线程证据。

此运行没有 prompt-render-finished，不能据此排除短重建累积。末尾保留 Charts 固定尺寸回退诊断。第 21 秒后直接 ⌘Q，唯一主进程权威退出 0，随后无 Typebar；没有 TERM、第二实例或真实用户数据改动。本轮只采证与补合同，没有实现猜测性修复，也没有重跑原生测试或全量 readiness。人工验收保持待验收，完整 goal active。

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
