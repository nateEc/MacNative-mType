# 组合显示投影与完整固定源码证据

## Pace 往返方向及跳过前驱的实际 marker 验证（2026-10-10）

扩展既有原生字段回归，验证 Hebrew→Latin→Hebrew：每次方向变更立即检查实际 NSHostingView marker 的边缘连续，再采样到完整时长检查终点。随后从 Hebrew 状态跳到 sequence 5，明确指定 Latin after 为零时长 predecessor，通过 fromDeadline 请求验证动画从 Latin 的右边缘开始，结束于 Hebrew 左边缘。这覆盖上一轮前驱方向同步修复尚未直接验证的路径。

本轮只补既有实现的行为证据，不新增产品逻辑，因此未人为制造红灯。pace-direction-roundtrip.log 135 项零失败零跳过（4.930s，墙钟 4.945）；pace-direction-predecessor.log 151 项零失败零跳过（5.664s，墙钟 5.681），包含字段、光标与配速调度。两次测试均确认进程正常退出后才编辑，未启动 Typebar 主程序。

这些边界已获定向证据，但不关闭整个双向布局、真实 IME、性能或全功能兼容缺口；未运行新完整门禁／Release GUI，goal 仍 active。

## Pace 跨方向动画坐标连续性（2026-10-10）

实际原生 marker 回归先复现 Hebrew 到 Latin 的方向切换跳动：pace-direction-continuity-red.log 一项一处失败，marker 从 16.802734375 跳到 0（0.703s，墙钟 0.704）。端点方向正确并不意味着动画起点连续。

非全字宽 Pace 在方向切换时按字形宽度转换已呈现位置与已有 tween 的两端坐标，保留 started、duration、curve，不提前采样，不修改 margin／tapeMargin。零 deadline predecessor 成功解析后同时记录该端点自己的方向，随后向目标方向转换；全字宽样式不做边缘坐标转换。

新增不同字形宽度的 channel 回归，在 0、0.25、0.5、1 秒检查边缘对应、尺寸和滚动通道保持不变。pace-direction-continuity-green.log 154 项零失败零跳过（5.167s，墙钟 5.184）；最终 pace-direction-continuity-final.log 163 项零失败零跳过（54.783s，墙钟 54.801），含完整宿主、组合、字段、光标与 Tape 回归。独立原创性检查退出 0，参考 pin 不变。

本轮零 Typebar 主程序启动。未运行新完整门禁或 Release GUI；这些测试不证明全部双向文字、跨行插值、实体 IME 或首键性能已解决。compositionDisplay 部分覆盖与完整 goal active 不变。

## Pace canonical 端点独立方向接线（2026-10-10）

新增实际原生 Pace 回归：LTR 外流内从 Hebrew after 目标切换到 Latin after 目标，检查 coordinator 几何与 NSHostingView marker.frame.midX。field-pace-direction-red.log 一项两处预期失败（0.712s，墙钟 0.713），Hebrew after 错向右偏移，marker 同样采用全局 LTR 边缘。

PromptFieldTextLayout 将共享字段方向解析提取为按实际 cell 的方法，canonicalDirection 对 before／after 分别选择 alias 首／尾槽，缺失返回 nil。原生字段新增 fieldPaceDirection resolver，使用与主光标一致的词级／字母级设置。PromptCaretNativeView 在初始位置、单个 endpoint（包括零时长 predecessor）和目标绘制方向均按各自 canonical ID／after 解析，不将一个目标的方向套到其他端点；缺失几何仍沿用既有保留位置政策，未改 deadline／插值／计时阈值。

field-pace-direction-green.log 152 项零失败零跳过（5.160s，墙钟 5.177）。补 canonical alias 从 Hebrew 首槽映射到 Latin 尾槽的独立方向／对应几何与缺失目标反例后，field-pace-direction-final.log 174 项零失败零跳过（50.291s，墙钟 50.310），含完整宿主、原生光标、字段布局、组合和 Tape 前进等回归。原创性 field-pace-direction-originality.log 退出 0。中断前仅只读检查，恢复后确认无遗留测试或主程序，未重复启动。

本次两个新测试证明实际端点方向与 alias 首尾边界，不单独证明全部跨行／混合方向插值、显式 bidi 控制、所有字体／标点／控制符或系统 IME。混排生产入口回退仍保留，真实设备、首键性能与完整兼容缺口不关闭；零 Typebar 图形主程序启动，无新完整门禁／Release GUI，compositionDisplay 部分与完整 goal active 不变。

## 字段主光标方向与原生 marker 接线（2026-10-10）

固定 caret 源码的 custom／Zen／Polyglot 按字母规则及 strings.isWordRightToLeft 的标点裁剪／基准回退用于确定本次合同。PromptFieldTextLayout.mainDirection 从当前 projection anchor 所属实际 cell 读取主文字；词级读取同字段所有主文字，不含 hint。mainRect 接受明确方向模式，旧未指定模式的几何调用保留原行为。原生字段同时提供几何 resolver 与 fieldMainDirection，PromptCaretNativeView 在最新 rendering provider 更新后读取该方向，用于最终 marker 的左右边缘；不能只改矩形、不改 bar 绘制方向。

新增 fieldDirectionPerGlyph 配置；生产特殊提示光标工厂在 custom／Zen／mixedLanguages 时启用，其他模式用词级方向。配置模式或 resolver 存在性变化使位置失效，不伪造文字 geometryRevision。首次 field-main-direction-red.log 为新接口缺失的编译失败，不算行为红测。首轮 green.log 50 项一处断言失败（1.744s，墙钟 1.750）：测试把 bar 所属字形矩形 minX 误认为最终边缘，改为实际 PromptCaretPlacementPolicy 锚点；方向要求不放宽。最终再通过真正原生 NSHostingView marker.frame.midX 验证换边，模式切换时保持同一测量几何代次。

field-main-direction-regression.log 111 项零失败零跳过（3.339s，墙钟 3.353），涵盖字段、组合、ASL／Choo／Tape。field-main-direction-native-final.log 133 项零失败零跳过（51.690s，墙钟 51.705），含两个模型方向新例、实际 marker 模式切换、完整生产宿主及光标相关回归。原创性 field-main-direction-originality.log 退出 0。默认 time 宿主不能替代 custom／Zen／mixedLanguages 全模式实机验证，工厂条件仍需更广验收。

此增量只接主光标，不改变 pace 方向规则；未取消混排入口回退。逐字 pace 两端方向、明确 bidi 控制跨行继承、全部候选／Unicode／控制符／RTL joining／真实 IME 仍开放。零 Typebar 图形主程序启动，无新完整门禁／Release GUI；compositionDisplay 仍部分，完整 goal active。

## 独立字形视觉顺序接入字段分配（2026-10-10）

PromptFieldTextLayout 现在消费 PromptFieldVisualOrder，但没有合并独立字形的绘制／TextKit 盒子。先沿用既有逻辑词分组、逐字尺寸、结构 Return 与 ASL 行分配，再按字段 group 与已分配 y 聚合非 gap 单字盒子；仅对 RTL 基准或含 RTL 字形的行解析物理顺序，从原行最左边界按各盒子原宽度重新放置。连写分支不变，提交空格不跨字段重排，canonical alias 与逻辑 followingCell 仍按原身份建立。仅可见位置变化，不改输入、计分、原词或回放。

行为优先：field-visual-allocation-red.log 两项两处预期失败（0.769s，墙钟 0.771），分别为 LTR 外流的 Hebrew 与 RTL 外流的 Latin 字母顺序；修正后 green.log 51 项零失败零跳过（1.062s，墙钟 1.069），包括上一失败候选破坏的 Arabic 连写／非连写宽度对照。再补内部数字顺序、canonicalRect 身份和实际窄视口多行 RTL 检查，field-visual-allocation-regression.log 109 项零失败零跳过（3.342s，墙钟 3.355），含原生字段、组合、ASL／Choo／Tape 相关回归。完整生产宿主及原生光标 field-visual-allocation-host.log 85 项零失败零跳过（49.701s，墙钟 49.710），原创性 field-visual-allocation-originality.log 退出 0。

会话内决策审查（非独立审计）以连写开关、字段边界、逐行分配和 canonical 身份为反例约束，没有放宽旧测试或使用整字段塑形替代独立绘制。该增量尚不包括逐字主／pace 边缘、段落级显式 bidi 控制跨行继承、完整 Unicode／复杂控制／视觉实机与系统 IME 验收；按已分配行重新解析方向不等同于浏览器完整段落 bidi 等价。混排生产入口回退仍保留，compositionDisplay 部分分类不提升。零 Typebar 主程序启动，无新全量门禁／Release GUI，完整 goal active。

## 独立字段视觉顺序解析组件（2026-10-10）

为解决上轮“整字段塑形会破坏关闭连写”冲突，新增独立 PromptFieldVisualOrder：只返回单个未换行字段的物理 cell ID 顺序，不改输入、原 cells、绘制盒子或连写开关。自有 TextKit 分析上下文使用去除 hint 的主文字、明确基准方向和实际 UTF-16 范围；普通位置按行／x 排序，连字共用位置按双向嵌入级别处理独立 ID；空显示槽保留原位置，避免空槽源序与坐标比较形成非传递排序。坐标／级别／源 ID 构成稳定顺序，不以方向布尔值简单翻转全部混合字符。

源码驱动技能核对已安装 Xcode macOS SDK NSLayoutManager.h，getGlyphsInRange:glyphs:properties:characterIndexes:bidiLevels: 在 macOS 10.5 起可用，低于项目 macOS 14 最低版本。组件通过实际 TextKit 输出验证，不复制上游算法或资产。会话内决策审查（非独立评审）要求视觉顺序与连写塑形分开，保留当前生产回退；本轮是独立组件探索，最初三项无故意失败阶段。

field-visual-order-first.log 三项零失败（0.064s，墙钟 0.066）；补空显示槽后 field-visual-order-final.log 48 项零失败零跳过（1.054s，墙钟 1.060）。Arabic سلام 反例 field-visual-order-ligature-red.log 一项一处预期失败（0.731s，墙钟 0.732）：分析塑形使 lam／alef 共用几何，原坐标排序为 [3,1,2,0] 而独立绘制身份应为 [3,2,1,0]。接入 SDK 双向嵌入级别后 ligature-green.log 49 项零失败（1.072s，墙钟 1.078）。最终修正同位置不同级别的全序边界，field-visual-order-regression.log 105 项零失败零跳过（3.239s，墙钟 3.251），原创性 field-visual-order-originality.log 退出 0。

五项新测试覆盖 Hebrew 的两种外方向、内部 Latin／数字顺序、空输入／身份不变、空显示槽和 Arabic 连字分析冲突。它不是布局分配、换行后逐行 bidi、控制符、主／pace 边缘或生产入口接线，不能用这五项证明全部 Unicode 等价。组件尚未由生产布局消费；下一步必须连同字段分配和光标方向一起验证，再考虑取消混排回退。本轮零 Typebar 主程序启动，无新全量门禁／真实 IME 验收，部分分类与完整 goal active 保持。

## 混排回退的实际布局反例（2026-10-10）

固定参考 elements/caret.ts 的 getTargetPositionAndWidth 明确在 Zen／custom／Polyglot 按字母判断 RTL；因此不能仅以全局语言方向推导混排光标。当前生产门控仍保留，未取消回退。

用既有 PromptFieldLayoutTests.rendering("אב cd", marked: "א") 得到实际 compositionTextMap，构造 PromptFieldTextLayout(map: map, width: 400, font: font, rightToLeft: false, joinsLetters: false)。分别读取首字段 cells[0]／cells[1] 的 cellFrames，应满足第二个希伯来字母 minX 小于第一个，同时 fieldFrames[0].maxX 不超过 fieldFrames[1].minX，保持独立词的 LTR 流。临时反例测试 field-mixed-direction-red.log 一项一处预期失败（0.741s，墙钟 0.743），实际第二字母 x=16.802734375、第一字母 x=0，说明逐字盒子未保留字段内部 RTL 顺序。此反例针对候选字段组件，不将它说成当前有回退保护的生产混排路径已暴露同样错误。

候选让含 RTL 字形的字段共享 TextKit 塑形上下文，独立词与提交空格身份不合并。新反例通过，但 field-mixed-direction-green.log 45 项一处失败（1.736s，墙钟 1.742）：既有 testJoiningScriptShapesWithinItsFieldButNeverAcrossFields 的非连写 Arabic 对照宽度也被塑形，与 joinsLetters=false 的独立字形合同冲突。没有删除／放宽旧断言，候选生产变更与临时失败测试全部撤回，日志保留用于重现；恢复后 field-mixed-direction-restored.log 44 项零失败零跳过（1.093s，墙钟 1.099）。

下一实现须分开字段内双向视觉排序与连写塑形开关，并接通按字母的主／pace 边缘、混合标点／数字、控制符和取消后恢复，不能用扩大塑形范围或只改全局方向替代。此轮仅新增诊断记录，生产／测试代码与之前提交相同，零 Typebar 主程序启动，无新完整门禁／真实 IME 验收。compositionDisplay 仍部分、完整 goal active。

## 当前生产入口补证（2026-10-10）

提交链路增量：四组实际生产宿主先设置候选，再经 insertText 接受一个 ASCII 字符；确认 marked range 清空，重新组合的原生可访问内容包含候选但不再从首槽开始。随后通过真实 responder deleteBackward 命令删除接受字符，重新组合恢复首槽前缀。此检查通过后续实际呈现观察会话推进／回删，不读取私有会话，也不将取消链路的内容相同当成提交证明。practice-production-composition-commit.log 与组合完成／Return 回归共 20 项零失败零跳过（44.807s，墙钟 44.809），含两个完整宿主用例。该验证补已有行为覆盖，无故意失败阶段；仍不是真实系统 IME／候选窗口／多字符接受／混合 RTL／成绩验收。本轮生产代码未改、零 GUI 主程序启动、未重跑全量门禁，部分分类与完整 goal active 保持。

下方为模型建立时的历史证据，不能将“尚未替换生产渲染”当作当前状态。当前 ContentView.renderedPrompt 已在非混合 RTL 门控下调用 PromptCompositionPresentation，原生字段呈现已消费 compositionTextMap；完整功能仍未验收。

PracticeCompositionHostTests 新增独立生产入口测试，共用实际 TypebarApp.practiceContent、隔离设置／内存 SwiftData 与不可见窗口，不复制简化渲染。四组宿主逐一选择 off／below／replace，通过真实 TypingInputView.setMarkedText 更新候选；检查 PromptFieldNativeView 的实际可访问值是否按 replace 显示候选、更新时字段 owner 保留，取消后重组同一候选的内容精确相同，输入 owner 保留且窗口未显示。直接 NSTextInputClient 调用不是实体键盘或系统 IME，未证明 below 浮层的视觉位置。原连续输入测试独立运行，不用组合预热污染原始诊断。

首次合并探索 practice-production-marked-modes.log 一项零失败（25.487s，墙钟 25.489）；随后拆分并补取消未误提交断言，practice-production-marked-modes-final.log 与模型渲染共 21 项零失败零跳过（40.025s，墙钟 40.029），格式化后再次通过，日志 practice-production-marked-modes-formatted.log。补已有行为的生产接线证据，没有故意失败阶段；生产代码未变、零主程序启动、无新全量门禁。混合 RTL 门控、Unicode 源单位差异、全部呈现组合和真实 IME 仍开放，compositionDisplay 部分及完整 goal active 不变。

固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`；独立 Swift 实现，不复制原版产品代码或资产。本增量是组合显示重写的模型／证据阶段，**尚未替换生产渲染**，不声称已修复实际 IME 界面。完整 goal active。

## 原版行为与现有缺口

读取完整 `frontend/src/ts/test/test-ui.ts` 的 `updateWordLetters`、`test/caret.ts`、`input/listeners/composition.ts` 和 CSS dead 样式。普通活动词中，组合串占据多个目标槽；off／below 显示对应目标文字，replace 显示候选（普通空格为下划线）。超出词尾的候选仍属于该活动词，后续目标不重复。marked 槽独立下划线且逐槽匹配正确色；Zen 始终显示候选，组合存在时不保留空词占位。主光标跟随整段候选，不等于接受输入或推进 pace。原版 below 的另行候选 UI、实际排版与调度不由本探针证明。

现有 `ContentView.renderedPrompt(for:)` 仍只在 `index == caretIndex` 时把整个组合串塞进一个字形，后面目标未按候选长度消耗；主光标仍读会话 canonical caret。直接把显示字符串变长无法同时修复普通、Tape、ASL 与 Choo 的词身份／几何／滚动。这是已核实的生产缺口，不把本次模型当作已接线。

配置盘点因此将 `compositionDisplay` 从已映射更正为部分，生成器、生成 JSON 及分区测试同步变为 94 项中的 89 映射／4 部分／1 不适用。原 `tapeMode` 行关于普通 LF／Zen 仍未接线的陈旧描述依据此前已提交合同纠正，仍为部分；没有新增配置或提升状态。

## 原生模型与 Unicode 边界

`PromptCompositionPlan` 只接收一个活动词的 target／input／composition 和显示模式，输出未提交尾部 cells、目标相对身份、组合身份、逐格匹配、消耗目标范围、空 Zen 占位及 target／afterComposition／afterInput 三类 caret 锚点。词尾候选没有伪造下一词 target ID，caret 在候选末端也不借用无关目标。输入、计分、计时、归档与服务协议不改动。实际颜色、控制符结构行、hint 和跨呈现几何仍由下一阶段适配。

原生 target ID 是完整 grapheme；模型保留该坐标，同时单独保存原版 `input.utf16.count + composition.utf16.count` 坐标。固定源的普通候选按 UTF-16 下标迭代、目标按 code point 分割，Zen 候选按 code point 迭代，而 caret 始终按 UTF-16：例如普通 😀 候选产生两个孤立 surrogate 槽；Zen 一个 emoji 槽的 caret 索引仍加二。探针保留这些原始单位，测试明确承认差异，不能把 132 组常规相同扩展为所有 Unicode 等价。是否及如何在实际 renderer 适配这些源坐标尚未完成；不改变既有原始单位输入／计分／回放来迎合显示。

## 完整源码对照与行为证据

QA-only `Scripts/check-source-composition-projection.mjs` 从干净固定 checkout 读取完整 word-update span、完整 caret 模块及真实 Words／Strings，执行 132 组 off／below／replace、普通／Zen、空／取消、错误前缀、溢出、空间／Tab／Return、中文／RTL 案例，以及 36 组显式 Unicode 案例（含预组合／分解重音互换）。DOM／RAF 与 caret 几何是明确自有适配，不执行真实浏览器布局、完整输入监听器或系统 IME；不复制网页字体／资产，也不进入产品运行时。探针已接入完整门禁。

九项 `PromptCompositionPlanTests` 覆盖跨度／身份、三种模式、词尾溢出、控制字符、Zen 空占位、取消、完整 grapheme／RTL 及严格原始字符身份；其中实际 `TypingInputView.setMarkedText` 多次更新、取消及随后接受输入证明组合不被误提交。两项 `CompositionProjectionSourceTests` 直接对照 132 组完整源输出及 caret，另对 Unicode 原始单位／原生差异作明确断言。并非完整 ContentView、实体键盘或全呈现证明。

先写模型测试时 `/tmp/typebar-composition-plan-initial.log` 因类型尚未实现编译失败，不称为生产行为红测。首个七项模型测试通过，日志 `plan-first.log`（0.002 秒）。`plan-regression.log` 因新缓存未隔离触发 Swift 6 编译检查；与既有对照测试一致改为 MainActor，不关闭并发检查，`plan-verified-regression.log` 33 项零失败零跳过（0.545 秒）。最终 `plan-final-regression.log` 94 项零失败零跳过（3.440 秒），含十项新增及相关光标／Tape／ASL；本段简写文件均为 `/tmp/typebar-composition-` 前缀。

首次分类测试筛选名错误跑零项，保留 `/tmp/typebar-composition-classification-red.log`，不计成功；准确筛选 `classification-behavior-red.log` 一项四个预期失败（0.617 秒），旧矩阵确实仍错误声称映射。修正唯一表格源并正常生成 fixture 后，`classification-green.log` 一项通过（0.008 秒），元数据重生成无漂移。

同会话有界决策／风险复核（非独立审计）检查词尾候选误跨词、Zen 空占位、控制结构、UTF-16／scalar 混用及取消／接受边界。模型不解决真实 session 词字段到 canonical ID 的映射，也不冒称普通／Tape／ASL／Choo 接线；这些是必须继续的工作，不缩减完整重写范围。工具链为 Swift 6.2.4／macOS SDK 26.2、最低 macOS 14，QA Node 22.22.1；本轮零 Typebar 主程序启动。

第二轮有界复核发现 Swift Character 默认 canonical equivalence 会把预组合／分解重音误判正确，与既有 `InputTextIdentity` 原始身份及固定源码都不同。首轮十四文件冻结在 `/tmp/typebar-composition-final-frozen.sha256`，中途仍逐项一致；明确确认自有门禁 84550 → swift-test 98715 → xctest 98856 后仅向该测试进程发送 INT，门禁 session 90580 终态退出 1，随后确认无残留才改文件。不计作成功，服务／包未运行；`/tmp/typebar-composition-final-readiness.log` 保留中止状态，终态后从确认属于该轮的 `typebar-native-rewrite-readiness.V2GgRh` 临时目录以不覆盖方式保留 72 日志至 `/tmp/typebar-composition-final-logs.IbuULK`。

`/tmp/typebar-composition-identity-red.log` 一项两处预期失败（0.607 秒），改为复用既有严格 `InputTextIdentity.matches` 后 `identity-green-regression.log` 96 项零失败零跳过（3.372 秒）。扩充源夹具后 `expanded-source-regression.log` 十一新增项零失败零跳过（0.550 秒）。不把新模型的规范等价误色留给生产接线解决，也不改变 Unicode 原始输入或计分政策。

## 下一阶段与冻结验收

下一阶段必须从会话的真实活动字段建立全局 ID 映射，统一所有呈现分支的候选 cells 与 after 锚点，保留主／pace 独立、词归属、连续控制结构、退休／回删／重建和新尝试取消；随后完成真实系统 IME／模式／设备验证。不能只让普通 Text 看起来正确，或把重复 offsets 当作多槽字形。字体／主题资源、性能、任意队列及其他功能缺口仍开放。

最终重新冻结十四文件于 `/tmp/typebar-composition-verified-frozen.sha256`；启动前、中途及门禁终态均逐项一致。唯一重新运行门禁 session 10912 最终退出 0，主日志 `/tmp/typebar-composition-verified-readiness.log`；前述中止轮不计成功。原生 3,970 项零失败零跳过（890.671 秒，All tests 墙钟 891.103 秒），服务 501 项零失败零跳过（11.435 秒，墙钟 11.492 秒）；十一新增分别为模型九项 0.002 秒、完整源码对照两项 0.490 秒。十万词耐久 152.114 秒、十六磁盘迁移 4.669 秒通过，耗时不作为优化结论。

最终门禁同时通过元数据再生成无漂移、53 表面、1,130 唯一人工场景结构、94 配置分区 89／4／1、固定完整源码探针、未启动应用包的构建／签名／资源与原创性边界检查。结构审计通过不等于 1,130 场景人工执行。保留 74 日志于 `/tmp/typebar-composition-verified-logs.CAKu7v`，210 既有组件图于 `/tmp/typebar-composition-verified-images.xkJLGp`；本轮查看 `ordinary-tape-corrected-return.png` 和 `zen-tape-rtl-emoji.png`，仅作现有组件输出复查，非新组合模型接线或系统 IME 的图像证据。日志中的 CoreData 故障夹具及系统诊断保留，不把 XCTest 后独立 Swift Testing 的零项摘要误当完整套件结果。

终态再次确认固定参考 pin 未变且干净，无 Typebar 主程序、门禁、编译器或测试进程残留；本轮零主程序启动。第三次同会话有界风险复核（非独立审计）检查严格字符身份、词尾溢出、双坐标、源探针适配边界与部分分类，没有发现需再次改动的代码问题。终态后仅本合同及 README／规范／功能盘点补充验证结果，其余十个冻结输入保持一致。只证明模型与有界源码证据，不宣称生产组合功能完成；四呈现接线与实际 IME 继续开放，goal 保持 active。
