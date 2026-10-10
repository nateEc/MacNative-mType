# 组合显示投影与完整固定源码证据

## TST-02：活动候选期间保存字体与字号更新（2026-10-10）

实际 TypebarApp.practiceContent 的四组不可见宿主在 below“中文”候选未提交时应用本机 Georgia／40pt，再恢复默认等宽／28pt。检查实际候选 NSTextField 的 fontName／pointSize 更新及恢复、候选／输入 owner 保留、hasMarkedText 仍真、候选与实际提示辅助功能内容不变，随后继续既有长候选、取消／接受／回删链路。只增加测试，补已有行为证据，无人为失败阶段；不安装／打包字体，不改产品、输入或持久化格式。

首轮 `work/font-composition-host.log` 十四项零失败但跳过一项固定源码测试（21.439s，墙钟 21.442），原因未传 TYPEBAR_REFERENCE_ROOT，保留日志且不计零跳过。补齐固定只读参考后，`font-composition-host-final.log` 十四项零失败零跳过（21.172s，墙钟 21.175），包含十一字体预览／解析／完整固定源轨迹、两个候选组件与新生产宿主（17.422s）。没有修改测试以隐藏跳过。

本次验证保存字体的实际生产更新，不将状态级预览测试扩大为命令面板临时预览的活动候选验证，也不证明 Georgia 的中文 fallback 像素、长文本全字体、文件异步、实体 IME 或全部字体资源等价。未做新完整门禁／Release，零主程序启动。fontFamily／compositionDisplay 继续部分，完整 goal active。

## TST-02：动态 CR 的零宽显示与强制换行修正（2026-10-10）

此前 innerText 字符串对照保留 CR，并不证明原生行高。增强同一本地 WebKit 探针，逐 UTF-16 单位使用 Range 测量 x／y／宽高；`work/below-cr-geometry-probe.log` 一项通过（0.794s，墙钟 0.796），观测动态 CR 宽度为零、与相邻字母同一 y，而原生 aCRLFb 标签高度为 66pt，普通 aLFb 为 33pt。此为探索证据，不将当时绿色测试误称已有布局断言通过。

加入独立 aCRb 案例，并对 CR 零宽／同一基线、原生一行高度及可见串作明确断言。`below-cr-geometry-red.log` 一项三处预期失败（1.469s，墙钟 1.471），包括实际 66pt 对 33pt 与两组仍包含 CR 的可见串。显示算法随后忽略 CR 的视觉占位，LF 仍按前轮折叠，原始候选及辅助功能标签不变；不向输入器、提交、回放或存储写入变换。

`below-cr-geometry-green.log` 六项零失败零跳过（53.229s，墙钟 53.231），含七组 WebKit／原生对照、两项组件与三项生产宿主。CR 的浏览器原始 innerText 仍严格检查，再以实测零宽规则比较可见串，不把原始候选删除。`below-cr-originality.log` 固定参考边界通过，非全面原创性证明。会话内风险复核未发现新增可落实问题，非独立审计；未重跑完整门禁／Release，零 Typebar 主程序启动。

该修正只证明本机 WebKit 及当前字体下短候选的 CR 非强制换行边界，不证明全部控制字符字形、所有浏览器／字体、软换行像素或真实 IME。此前 CR 未验收记录保留历史范围；完整 compositionDisplay 与 goal 继续部分／active。

## TST-02：LF 候选显示与本地 WebKit 对照（2026-10-10）

完整读取固定参考 CompositionDisplay、mount.tsx 与 test.html，候选位于 wordsWrapper 外的独立挂载点，直接输出动态文本；网页根为 lang=en。新增 QA-only WebKit 测试，以自有最小 HTML 的动态 textContent、计算样式 normal 和 innerText 测量英文 LF、动态 CRLF、中文 LF、混合 RTL LF、连续 LF 与 ZWSP+LF。使用非持久数据存储、禁止外部加载的 CSP、无 baseURL，不加载原版网站／代码／资源；WebKit 仅存在测试目标，产品没有网页运行时。

探索 `work/below-break-webkit-probe.log` 一项通过（0.696s，墙钟 0.697）：输出依次为 a空格b、aCR空格b、首行空格次行、سلام空格שלום、a空格b、aZWSP空格b。动态 CR 不被 HTML 解析器预处理，不能先把全部换行规范化再冒称等价。此输出不是完整网页／Chrome／全部 Unicode 或像素证据。

`below-break-red.log` 两项四处预期失败（2.213s，墙钟 2.215）：原生两组 LF 原文仍显示多行，实际 99pt 而非空候选的一行 33pt；独立 WebKit 输出测试通过。独立原生显示算法随后把 LF 与 ASCII 空格／Tab 一同折叠，保留 CR 及其他字符，原始辅助功能候选不变。测试将短 LF 候选的显示串与一行高度同时检查，另把六组原生实际 NSTextField.stringValue 的 UTF-16 与 WebKit innerText 逐组对照，不仅对照静态常量。

最终 `below-break-green.log` 六项零失败零跳过（52.279s，墙钟 52.281），包含两个组件、WebKit 对照（0.624s）与三个生产宿主（48.427s）。`below-break-originality.log` 固定参考源码／资源边界通过，非全面原创性证明。会话内有界风险复核无新增可落实问题，非独立评审；未重跑完整门禁或 Release，零 Typebar 主程序启动。

此前“换行转换尚未实现”是历史范围；本轮只补上述实测 LF 显示。动态 CR 的实际字形／布局、软换行边缘裁切、浏览器差异、全字体与真实系统 IME 仍开放；innerText 相同不等于像素完全一致。compositionDisplay 保持部分，完整 goal active。

## TST-02：below 横向空白显示修正（2026-10-10）

固定源码 CompositionDisplay 直接输出文本节点，没有保留空白样式。依据 [CSS Text 3 空白处理规则](https://www.w3.org/TR/css-text-3/#white-space-processing)，独立原生显示层折叠 ASCII 空格／Tab，去除行首尾横向空白，纯横向空白使用既有一行占位；不使用宽泛 Unicode whitespace 集合，NBSP、双向控制符、分解重音与 emoji 保留。原始候选仍进入辅助功能标签，输入器／会话／计分未修改。此前“原生 stringValue 原文完整”是历史补证；当前显示串与原始候选分开检查，不把显示规范化写回输入。

`work/below-horizontal-space-red.log` 一项三处预期失败（1.971s，墙钟 1.972），明确覆盖 Tab、连续横向空白与纯空白。首次实现后 `below-horizontal-space-green.log` 五项四处失败（51.884s，墙钟 51.887），均为窄页四组宿主仍断言末尾空格显示；保留失败日志。明确将窄页显示预期改为去掉 fixture 唯一尾空格，同时新增完整原文辅助功能标签断言；不采用宽松比较。最终 `below-horizontal-space-final.log` 五项零失败零跳过（50.827s，墙钟 50.829），含两项组件与三项生产宿主，状态避让／窄页／缩放 owner 回归通过。

`below-horizontal-space-originality.log` 固定参考源码／资源边界通过，非全面原创性证明。会话内风险复核无新增可落实问题，非独立审计。未重跑完整门禁或 Release；零主程序启动。换行转空格／删除的浏览器上下文规则仍未实现，软换行边缘空白、ZWSP、双向视觉与真实 IME 也不由本次检查证明；不将横向修正描述为完整 CSS 等价。compositionDisplay 继续部分，完整 goal active。

## TST-02：候选控制字符与主题更新的原生边界（2026-10-10）

新增组件回归，在同一不可见 NSWindow／NSHostingView 内更新含三行文本、Tab、RTL isolate 控制符、分解重音与 emoji 的候选，按 UTF-16 序列验证原文不被规范化或截断，辅助功能标签同步；红→蓝→红文字色更新、字体与原生 owner 保留，取消回到同一空白行高度。三行候选确实增加原生布局高度，完整组件保持在宿主边界内。此为已有行为补证，无故意失败阶段、无产品修改。

`work/below-control-theme-tests.log` 两项零失败零跳过（2.650s，墙钟 2.652）；`work/below-control-theme-regression.log` 五项零失败零跳过（51.686s，墙钟 51.688），含三项生产 below 宿主的状态避让、窄页混排与活动组合缩放。没有重跑完整门禁，零 Typebar 主程序启动，终态进程检查无残留。

完整读取固定参考 `components/pages/test/CompositionDisplay.tsx` 后确认其直接输出网页文本节点；本轮只检查原生内容完整性，不证明网页 whitespace 折叠与原生显式换行相同，也不证明双向控制符的视觉顺序、真实 IME、主题切换的实际整页像素或焦点模糊。相关视觉对照仍开放，compositionDisplay 保持部分，goal active。

## TST-02：单实例真实窗口有限观察（2026-10-10）

复用上述冻结门禁的 Release 构建，打包独立 `app.typebar.qa.below-ime-0ff635b`，启用 `TypebarQAInMemoryStore`，不使用日常成绩库。在独立 QA 偏好中选择下方显示，仅打开一次；`pgrep -x Typebar` 确认唯一进程 23919。实际窗口滚动至练习区，观察空候选占位与下方 30s／错误状态区没有覆盖提示；打开设置再关闭后，AX 焦点回到 Typing input，below 选择保留。返回时提示内容重新生成，未把此次窗口往返认作活动会话保留验证。

没有切换系统输入源、粘贴中文或执行真实 IME 候选输入，因而本次不证明 marked 候选、取消／接受、失焦模糊或系统候选窗口位置。观察后使用正常 ⌘Q 退出，再以进程检查确认零 Typebar；退出后不再查询应用以免重新启动。此记录仅为已有行为的有限人工观察，不改产品代码，不重跑已完成的全量门禁，不提升 compositionDisplay 分类，完整 goal 仍 active。

## TST-02：below 实现与宿主增量的冻结完整门禁（2026-10-10）

冻结提交 0ff635bb959bf214ce18f1d00d4347a6fbff7262，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。证据目录 work/frozen-readiness-below-fixed.lkZpDd 保存 revision.txt、inputs.sha256、gate.log、freeze-verification.log 与 74 份阶段日志。单次修正环境后的顺序门禁终态 gate_exit=0、hash_exit=0，849 个跟踪文件 SHA-256 全部一致，运行期间未编辑源码或重启。参考仓库保持干净，零 Typebar 主程序启动。

客户端 4,256 项零失败零跳过（1814.151s，墙钟 1814.619），服务端 501 项零失败零跳过（11.371s，墙钟 11.430）。全部 37 实际组合宿主通过（896.885s，墙钟 896.890），包括独立候选行、标签／Pace 避让、640pt 混合候选与活动组合期间宽→窄→宽恢复；原生组件回归及此前混排增量同轮覆盖。十万词耐久通过（155.698s）。两次短采样分别确认日志缓冲后的 Gujarati、Sindhi 宿主执行位置，仅用于进度，不作性能结论。

Release 优化构建 397.57s，未打开应用包的资源边界、签名与固定参考原创性边界检查通过；边界检查不是全面原创性证明。首轮 work/frozen-readiness-below.0fmrn0 保留失败：默认系统 Redis 8.6.1 不满足源码探针锁定 6.2.6，gate_exit=1、hash_exit=0，非产品故障。只读确认本地 QA Redis 6.2.6 后明确 TYPEBAR_SOURCE_REDIS_SERVER 与支持 JSON 的 cli，才启动本轮完整门禁；没有放宽断言或跳过检查。

本次仅记录完整验证，不改产品、存储、迁移或网络行为。此前各阶段“未做新完整门禁／Release”保留当时范围，本轮补足上述冻结提交的自动检查与未打开包验证，不补足真实 GUI／系统 IME。实际聚焦视觉、连续拖窗、全字体／正字法、Pace／ASL／Choo 可见组合、最低系统、首键残余抖动及其他功能差异仍开放。配置 89 映射／4 部分／1 不适用、187 主题无精确映射、待执行人工场景和完整 goal 均不因门禁绿色而关闭；compositionDisplay 继续部分。

## TST-02：活动组合期间实际宿主收窄与恢复（2026-10-10）

仅增强测试，将同一生产内容的外层 frame 独立出来，新增宿主在长中文候选尚未提交时 1000→640→1000pt 切换，同时调整实际不可见窗口 contentSize。四组尺寸配置逐次检查宿主实际宽度、候选文本、marked 状态、输入／候选／字段 owner 保持、左右边界、窄宽高度增加与恢复后高度一致，再继续既有取消／接受／回删链路。没有重建简化输入器或改动生产行为。

below-production-resize.log 一项零失败（17.160s，墙钟 17.161）；below-production-resize-final.log 五项零失败零跳过（71.041s，墙钟 71.046），含组件及四个生产宿主（69.092s，墙钟 69.093）：缩放、宽页／窄页状态候选和普通组合取消。已有行为补覆盖，无人为失败阶段；运行期间未修改或重启。会话内风险审查无可落实发现，非独立评审。零 Typebar 主程序启动，未新增网络、存储或迁移行为。

此证据是离散宽度切换，不能说成真实可见窗口拖动、连续缩放帧率或系统 IME 事件验收；候选为中文，不扩大为 RTL 缩放及全部字体。未重跑全部混排宿主、Release 或完整门禁，compositionDisplay 继续部分，完整 goal active。

## TST-02：640pt 实际练习页 below 候选布局（2026-10-10）

仅增强 PracticeCompositionHostTests，共享生产宿主增加默认仍为 1000 的宽度参数。新增 640×720 场景经四组尺寸配置和三种组合模式，启用自有标签与 80 WPM Pace，below 输入八次重复的“سلام שלום mixed 候选 ”，检查原文、长候选换行、左右边界、候选／输入 owner，以及原有取消／接受／回删链路。不是简化组件替代生产页。

below-narrow-production.log 一项零失败（16.379s，墙钟 16.381）。补拍复验 below-narrow-production-final.log 三项零失败零跳过（34.427s，墙钟 34.428），含窄页、原宽页和组件回归；生产宿主两项 32.498s，组件 1.929s。证据目录 work/below-narrow-page.J1XA3g，640pt 的 below-status-640-0 至 3.png 均人工查看；滚动到候选后完整候选、标签和 Pace 可见，无相互覆盖。快照文件名加入宿主宽度，避免宽／窄组互相覆盖。已有行为补覆盖，无人为失败阶段，运行期间未编辑或重启，零 Typebar 主程序启动。

本次同会话风险审查无其他可落实发现，非独立审查。未改生产、存储或网络；未重跑全部宿主或完整门禁。失焦快照只证明该几何与状态避让，不证明整个页面其他区域、RTL 字形次序／候选溢出正文 shaping、实际窗口连续缩放、实体键盘／系统 IME、全部字体或其他特殊呈现。上述边界保持开放；compositionDisplay 仍部分，完整 goal active。

## TST-02：below 窄宽与 RTL 原生组件回归（2026-10-10）

仅增加 BelowCompositionPromptTests，不改变生产行为。实际 NSHostingView／不可见 NSWindow 挂载生产组件，以 system 28pt、monospaced 40pt 和三组独立构造的 Arabic／Hebrew、中文／LTR／Hebrew、组合长音符／重音／韩文候选，逐组 1000→180pt 收窄、取消、恢复宽度并切换字体。检查原文、字号、居中、原生对齐宽度、长文本高度增加、实际 cell 所需高度、宿主容纳、取消占位与行高收缩，以及同一原生 owner。

初始 below-narrow-rtl.log 仅编译歧义；明确 CGFloat 后 fixed.log 一项 13 处失败，12 处来自把 bounds 当作布局宽度，一处短文本本来可在 180pt 放入一行。alignment.log 改用三次重复的长文本后仅剩 12 处宽度失败；有界诊断确认 bounds=184、alignment=180、左右 inset 各 2pt。测试改为实际 alignmentRect 宽度断言，未扩大容差；保留换行、完整容纳和 owner 要求，不把这些测试假设错误归为产品故障。新增既有行为回归，无人为制造产品失败阶段。

below-narrow-rtl-final.log 三项零失败零跳过（41.664s，墙钟 41.666）：组件一项（1.908s）和两个实际生产宿主（39.756s，墙钟 39.757）。同会话风险复核无可落实发现，非独立审查；零 Typebar 主程序启动。此回归不证明文字双向视觉顺序、每个字形未截断、实际系统 IME／聚焦、全部字体或生产页窄窗布局；组件证据不能扩大为整页验收。前一 356 项证据仅覆盖 da07c18 的生产实现，不冒称重跑全量，compositionDisplay 继续部分，完整 goal active。

## TST-02：below 独立候选行与状态避让增量（2026-10-10）

基于下方固定源码差异独立实现 BelowCompositionPrompt：原生 wrapping NSTextField 全宽居中，使用实际练习字体、字号与次要文字色；空候选保留一行，更新／取消保持同一视图，off／replace 不挂载。失焦透明度 0.25、模糊半径 4，0.25s 进入、聚焦即时恢复，尊重减少动态效果。固定参考未覆盖模糊变量；其锁定 Tailwind 4.3.2 的 [版本主题源码](https://raw.githubusercontent.com/tailwindlabs/tailwindcss/v4.3.2/packages/tailwindcss/theme.css) 明确 blur-xs 为 4px，参考 tailwind.css 未覆盖该值。参数一致不等于两平台像素完全一致。

实际生产宿主增加原生候选文字、位置、字号、全宽、占位、模式卸载及 owner 断言。新增长中文候选同时启用自有标签和 80 WPM Pace，覆盖四组尺寸配置。初始截图复现旧 bottomLeading 状态浮层盖住第二行候选；改为 below 模式下候选之后的正常布局，off／replace 保留原状态浮层。below-status-after-visible.log 一项零失败（18.195s，墙钟 18.196），below-status-after/below-status-0 至 3.png 均人工查看，滚动后的完整候选、标签及 Pace 无重叠。窗口从未显示，失焦截图不证明实际聚焦切换、系统 IME 或全部字体／窄窗／RTL。自动断言验证长候选换行，标签避让当前由人工截图证明，不冒充完整自动视觉回归。

保留探索失败：最初 SwiftUI AX 枚举未发现候选，不算产品视觉失败；一次增强测试误比完整滚动内容，改为 visibleRect。该轮还出现字段 owner 消失，原因未证实；保留诊断与原 owner 断言，随后专项及完整宿主未复现，不声称已定位或修复。早先 below-candidate-regression.log 的 349 项有两项因缺少锁定 Anime archive 失败，不能记成绿色；补齐依赖的两项 source-scroll-recheck 通过（0.760s，墙钟 0.762）。

最终冻结当前源码，固定参考及锁定 Anime archive 环境下 below-candidate-final-regression.log 356 项零失败零跳过（929.490s，墙钟 929.531），含全部 35 实际生产宿主（890.299s，墙钟 890.303）、源投影、字段、ASL／Choo 和两个退休测试集。同一轮运行未改源码或重启；短采样仅确认缓冲日志之后实际已到 Malayalam，不作性能基准。below-candidate-originality.log 边界检查退出 0，参考保持干净，不扩称全面原创性证明。会话内差异审查未发现其他可落实缺陷，非独立评审。

没有新增输入 owner、定时器、网络或存储迁移，零 Typebar 主程序启动。下方“未修复”为此前差异记录；本轮解决独立行和状态避让，但真实 IME、焦点切换视觉、窄窗／RTL／全部字体、Pace／ASL／Choo 组合、最低系统、新 Release 与完整冻结门禁仍待验，compositionDisplay 继续部分，完整 goal active。

## TST-02：below 候选行源码差异与下一验收契约（2026-10-10，未修复）

完整门禁之后对固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 只读复核：frontend/src/ts/components/pages/test/CompositionDisplay.tsx 的 below 分支使用全宽、居中、练习字号的独立候选行；非 focused 状态弱化并模糊，重新聚焦即时恢复。input/listeners/composition.ts 在组合更新时设置候选文本，结束时清空；test/test-ui.ts 在 below 重置／切换时设置空白占位。未复制实现或资源。

当前原生 TypebarApp.typingPanel 的候选分支仍在 bottomLeading 浮层内，字号为 max(14, fontSize * 0.58)，带小背景面板，仅非空时出现；它不是上述独立居中行。现有 PracticeCompositionHostTests 验证正文投影、原生 owner 和组合取消，但未独立断言 below 候选行的几何、字号、失焦与占位，故此前自动门禁通过不能关闭此差异。这是静态源码可定位的产品差异，尚无新增运行时复现，不把它写成已修复。

后续独立宿主验收必须覆盖：below 空候选仍保留行高；候选从短到长再取消只更新该行，正文不被替换，候选行不覆盖正文／标签／Pace；候选行位于正文后方并全宽居中，采用所选练习字体和字号；模式切到 off／replace 不保留候选行；失焦弱化、聚焦即时恢复；窄宽换行与 RTL 候选不越界。测试应进入实际生产宿主，并同时检查文字、几何和输入 owner，不能只检查新建策略对象。真实 IME 与全字体视觉仍独立待验。

本次仅记录可核查差异与行为契约，不改变产品、存储、迁移、离线／网络或运行权限，无需为文档制造失败测试。零主程序启动。compositionDisplay 与完整 goal 继续部分／未完成。

## TST-02：全部当前混排增量的冻结完整验证（2026-10-10）

冻结提交 0c317e1d54b2666f05e2aae3973491942cff2d7d，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。单次顺序门禁终态 gate_exit=0、hash_exit=0，847 个跟踪文件 SHA-256 一致。证据目录 work/frozen-readiness-all-mixed.Nr4pws 保留 revision.txt、inputs.sha256、gate.log、freeze-verification.log 与 74 份阶段日志。运行中未修改代码、未重启门禁，零 Typebar 主程序启动，参考工作区干净。

客户端 4,252 项零失败零跳过（1749.178s，墙钟 1749.663），服务端 501 项零失败零跳过（11.604s，墙钟 11.665）。全部三十四实际生产宿主通过（817.509s，墙钟 817.514），覆盖此前完整门禁之后的 Kannada、Khmer、Korean、Malayalam、Sinhala、Telugu、Tibetan、Myanmar Burmese、Likanu 增量；当前目录准入、原生语言菜单、退休与十万词耐久检查同轮执行。自定义混排 446 组件逐一完成检查通过（24.975s）。短进程采样仅用于辨认缓冲日志后的实际执行用例，不作为性能基准。

Release 优化构建 396.18s，未打开应用包的资源、签名和固定参考原创性边界检查通过；边界检查不是全面原创性证明。此记录不改变数据格式、迁移、离线或网络行为，也不新增运行权限。下方各阶段“未做完整门禁／新 Release”保留为历史范围，本轮补足上述冻结版本的自动门禁和未打开包验证，不补足真实 GUI／IME 验收。

人工仍需用唯一隔离实例逐样式检查真实输入法候选更新／取消／部分提交、below 位置、窄窗跨行恢复、全部字体与 Pace／ASL／Choo 可见组合，结束正常退出并确认零实例。全正字法、真实 IME、最低系统、完整视觉、长期组合耐久及首键残余抖动仍未证明；compositionDisplay 等部分项、主题差异和完整 goal 保持未完成，不以本轮绿色替代全功能等价验收。

## TST-02：Arabic／Likanu 混排生产入口与目录准入检查（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制代码或资产。独立构造字符夹具“ab سلام x̄ʌʃ cd”进入实际 practiceContent 宿主，不读取参考词值或转换实现。arabic-likanu-host-red.log 一项预期失败于原生字段缺失（2.060s，墙钟 2.062）。生产仅增加 Likanu 共享准入，光标与组合显示保持同一策略，未改输入提交、转换器或计分。默认未验证连写语言回退分支保留，但当前目录已无该准入缺口。

四组尺寸策略覆盖三样式活动字段候选差异、Arabic 连字与 Likanu LTR 两端几何、精确辅助文本、“x̄”→“x̄ʌʃ”更新／取消、接受“x̄”后标记“ʌʃ”、逐 UTF-16 单位回删和输入／字段 owner 保持。跨行专项覆盖三样式、两字体、90pt 宽度、长→短→取消、缓存／新建一致、每槽几何、后词不重叠及 canonical 恢复。组合长音符夹具不证明全部 Likanu 正字法、专用字体或真实输入法事件。新增测试逐当前连写语言 ID 检查 Arabic／Hebrew 混排准入，仅证明策略覆盖，不扩称每个目录均有独立实际宿主或全部视觉验收。

arabic-likanu-focused.log 31 项零失败零跳过（33.519s，墙钟 33.524）。随后仅将旧策略测试名称改为反映当前覆盖，固定参考及锁定 Anime 环境下 arabic-likanu-regression.log 355 项零失败零跳过（857.339s，墙钟 857.381），含全部三十四宿主（813.736s，墙钟 813.741）、布局／投影／方向、两个退休测试集与既有 Korean／ASL／Choo 组件。arabic-likanu-originality.log 固定参考边界退出 0，不扩大为全面原创性证明。一次短进程采样确认日志缓冲期间运行到 Malayalam 宿主，不作性能结论。会话内风险审查核对完整差异、共享入口、候选隔离与默认回退，无剩余可落实发现，非独立评审。

所有运行终态后写记录，零 Typebar 主程序启动。无存储格式、迁移或新网络行为。人工步骤待执行：选择 English／Arabic／Likanu 自定义夹具，逐样式实际输入组合符、更新／取消／部分提交，检查 below 独立候选位置、窄窗恢复、专用及全部字体和 Pace／ASL／Choo 可见组合。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Myanmar Burmese 混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制代码或资产。自有 Unicode 夹具“ab سلام မြန်မာ cd”进入实际 practiceContent 宿主；arabic-myanmar-host-red.log 一项预期失败于原生字段缺失（1.985s，墙钟 1.987）。生产仅增加 Myanmar Burmese 的共享准入，光标与组合显示继续共用策略；Likanu 未验证混排仍回退，未改输入提交或计分。

四组尺寸策略覆盖三样式活动字段候选差异、Arabic 连字与 Myanmar LTR 两端几何、精确辅助文本、“မြန်”→“မြန်မာ”更新／取消、接受“မြန်”后标记“မာ”、逐 UTF-16 单位回删及输入／字段 owner 保持。跨行专项覆盖三样式、两字体、90pt 宽度、长→短→取消、缓存／新建一致、每槽几何、后词不重叠与 canonical 恢复。夹具包含组合字符，但不证明全部缅文正字法／连字、词库或真实系统输入法事件。

arabic-myanmar-focused.log 30 项零失败零跳过（35.018s，墙钟 35.023）。固定参考及锁定 Anime 环境下 arabic-myanmar-regression.log 352 项零失败零跳过（839.606s，墙钟 839.651），含全部三十三宿主（792.861s，墙钟 792.865）、布局／投影／方向、两个退休测试集及既有 Korean／ASL／Choo 组件。arabic-myanmar-originality.log 固定参考边界退出 0，不扩大为全面原创性证明。一次短进程采样确认日志缓冲期间已运行新增宿主，不作性能结论。会话内风险审查核对完整差异、两个共享入口、候选隔离与保留回退，无剩余可落实发现，非独立评审。

所有运行终态后写记录，零 Typebar 主程序启动。无存储格式、迁移或新网络行为。人工步骤待执行：选择 English／Arabic／Myanmar Burmese 自定义夹具，以真实 IME 逐样式更新／取消／部分提交，检查 below 独立候选位置、窄窗恢复、全部连字／字体及 Pace／ASL／Choo 可见组合。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Tibetan 两目录混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制源码或资产。自有 Unicode 夹具“ab سلام བོད་སྐད་ cd”分别进入 Tibetan／Tibetan 1k 实际 practiceContent 宿主；arabic-tibetan-host-red.log 两项预期失败于原生字段缺失（2.643s，墙钟 2.644）。生产仅增加两身份的共享准入，光标与组合显示继续共用策略；Myanmar Burmese／Likanu 未验证混排仍回退，未改输入提交或计分。

每目录四组尺寸策略覆盖三样式活动字段候选差异、Arabic 连字与 Tibetan LTR 两端几何、精确辅助文本、“བོད་”→“བོད་སྐད་”更新／取消、接受“བོད་”后标记“སྐད་”、逐 UTF-16 单位回删以及输入／字段 owner 保持。跨行测试覆盖两目录、三样式、两字体、90pt 宽度、长→短→取消、缓存／新建一致、每槽几何、后词不重叠与 canonical 恢复。夹具包含元音和叠字，不证明全部藏文正字法、词库或真实系统输入法事件。

arabic-tibetan-focused.log 31 项零失败零跳过（60.873s，墙钟 60.878）。固定参考与锁定 Anime 环境下 arabic-tibetan-regression.log 350 项零失败零跳过（798.056s，墙钟 798.096），含全部三十二宿主（755.840s，墙钟 755.844）、布局／投影／方向、两个退休测试集及既有 Korean／ASL／Choo 组件。arabic-tibetan-originality.log 固定参考边界退出 0，不扩称全面原创性证明。一次短进程采样确认缓冲期间运行到 Sinhala 宿主，不作性能结论。会话内风险审查核对完整差异、共享入口、候选隔离和保留回退，无剩余可落实发现，非独立评审。

所有运行终态后写记录，零 Typebar 主程序启动。无数据格式、迁移或新网络行为。人工步骤待执行：逐目录选择 English／Arabic／Tibetan 自定义夹具，以真实 IME 逐样式更新／取消／部分提交，检查 below 独立候选位置、窄窗恢复、全部叠字／字体及 Pace／ASL／Choo 可见组合。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Telugu 两目录混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制源码或资产。自有 Unicode 夹具“ab سلام కిరణం cd”分别进入 Telugu／Telugu 1k 实际 practiceContent 宿主；arabic-telugu-host-red.log 两项预期失败于原生字段缺失（2.555s，墙钟 2.556）。生产仅增加两个身份的共享准入，光标与组合显示继续共用策略；Tibetan 等未验证混排仍回退，未改输入提交或计分。

每目录四组尺寸策略覆盖三样式活动字段候选差异、Arabic 连字与 Telugu LTR 两端几何、精确辅助文本、“కి”→“కిరణం”更新／取消、接受“కి”后标记“రణం”、逐 UTF-16 单位回删和输入／字段 owner 保持。跨行测试覆盖两目录、三样式、两字体、90pt 宽度、长→短→取消、缓存／新建一致、每槽几何、后词不重叠及 canonical 恢复；这些带组合元音夹具不证明全部 Telugu 连字／正字法或词库。

arabic-telugu-focused.log 31 项零失败零跳过（59.914s，墙钟 59.919）。固定参考及锁定 Anime 环境下 arabic-telugu-regression.log 347 项零失败零跳过（735.752s，墙钟 735.792），含全部三十宿主（694.711s，墙钟 694.715）、布局／投影／方向、两个退休测试集及既有 Korean／ASL／Choo 组件。arabic-telugu-originality.log 固定参考边界退出 0，不扩大为全面原创性证明。会话内风险审查核对完整差异、共享入口、候选隔离与保留回退，无剩余可落实发现，非独立评审。

全部运行终态后写记录，零 Typebar 主程序启动。无存储格式、数据迁移或新网络行为。人工步骤待执行：逐目录选择 English／Arabic／Telugu 自定义夹具，以真实 IME 逐样式更新／取消／部分提交，检查 below 独立候选位置、窄窗恢复、全部连字／字体及 Pace／ASL／Choo 可见组合。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Sinhala 混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制代码或资产。自有 Unicode 夹具“ab سلام කිරණ cd”进入实际 practiceContent 宿主，arabic-sinhala-host-red.log 一项预期失败于原生字段未挂载（1.898s，墙钟 1.899）。生产仅增加 Sinhala 的共享准入，光标与组合显示两个入口保持共用；Telugu 等未验证混排继续回退。

四组尺寸策略覆盖初始与后段活动字段三样式差异、Arabic 连字与 Sinhala LTR 两端几何，检查“කි”→“කිරණ”更新／取消、接受“කි”后标记“රණ”、逐 UTF-16 单位回删、精确辅助文本和输入／字段 owner 保持。带组合元音夹具不证明全部 Sinhala 正字法／连字或词库。跨行专项覆盖三样式、两字体、90pt 宽度、长→短→取消、缓存与新建一致、每槽几何、后词不重叠和 canonical 恢复。

arabic-sinhala-focused.log 30 项零失败零跳过（32.818s，墙钟 32.822）。固定参考与锁定 Anime 环境下 arabic-sinhala-regression.log 344 项零失败零跳过（679.526s，墙钟 679.565），含全部二十八宿主（638.526s，墙钟 638.530）、布局／投影／方向、两个退休测试集及既有 Korean／ASL／Choo 组件。arabic-sinhala-originality.log 固定参考边界退出 0，不扩称全面原创性证明。会话内风险审查核对完整差异、两个入口、候选隔离与保留回退，无剩余可落实发现，非独立评审。

所有运行终态后写记录，零 Typebar 主程序启动。无数据格式、迁移或新网络行为。人工步骤待执行：选择 English／Arabic／Sinhala 自定义夹具，真实 IME 逐样式更新／取消／部分提交，检查 below 独立候选位置、窄窗恢复、全部连字／字体和 Pace／ASL／Choo 可见组合。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Malayalam 混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制源码或资产。自有 Unicode 夹具“ab سلام കിരണം cd”进入实际 practiceContent 宿主，arabic-malayalam-host-red.log 一项预期失败于原生字段缺失（1.929s，墙钟 1.931）。生产仅增加 Malayalam 共享准入，光标与组合显示保持共用策略；Sinhala 等未验证混排继续回退。

四组尺寸策略覆盖初始和后段活动字段三样式，以不匹配候选区分替换与保留原文，检查“കി”→“കിരണം”更新／取消、接受“കി”后标记“രണം”、逐 UTF-16 单位回删、精确辅助文本、Arabic RTL／Malayalam LTR 两端几何和输入／字段 owner 保持。该带组合元音夹具不证明全部 Malayalam 连字／正字法或词库。跨行专项另覆盖三样式、两字体、90pt 宽度、长→短→取消、复用／新建一致、每槽几何、后词不重叠与 canonical 恢复。

arabic-malayalam-focused.log 30 项零失败零跳过（33.398s，墙钟 33.403）。固定参考及锁定 Anime 环境下 arabic-malayalam-regression.log 342 项零失败零跳过（656.097s，墙钟 656.137），含全部二十七生产宿主（613.354s，墙钟 613.357）、布局／投影／方向、两个退休测试集、既有 Korean 和 ASL／Choo 组件。arabic-malayalam-originality.log 固定参考边界退出 0，不扩称全面原创性证明。会话内风险审查核对完整差异、两个消费入口、候选隔离及回退，无剩余可落实发现，非独立评审。

所有运行终态后写记录，零 Typebar 主程序启动。无存储格式、数据迁移或新网络行为。人工步骤待执行：选择 English／Arabic／Malayalam 自定义夹具，用真实 IME 逐样式检查更新／取消／部分提交、below 独立候选位置、窄窗跨行、特有连字和全字体，再验 Pace／ASL／Choo 可见组合。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Korean 三目录混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制代码或资产。自有 Unicode 夹具“ab سلام 한글 cd”分别进入 Korean／Korean 1k／Korean 5k 的实际 practiceContent 宿主；arabic-korean-host-red.log 三项均预期失败于原生字段缺失（3.388s，墙钟 3.390）。生产仅增加三个身份的共享准入，光标与组合显示保持同一策略，Malayalam 等未验证混排继续回退；未改韩文计分或输入提交规则。

每个宿主四组尺寸策略覆盖三样式候选差异、Arabic 连字、Korean LTR 两端几何、精确辅助文本、更新／取消、接受“한”后标记“글”、逐单位回删及输入／字段 owner 保持。首轮 arabic-korean-focused.log 32 项零失败零跳过（87.534s，墙钟 87.539）。另补每样式“ㅎ”→“하”→“한”连续候选更新，检查 replace 精确替换当前音节而 off／below 保留目标、取消恢复；arabic-korean-jamo-focused.log 32 项零失败零跳过（106.295s，墙钟 106.301）。这是手动调用原生输入协议的兼容 Jamo／合成音节场景，不是系统输入法真实事件、完整现代／古 Jamo 或全部韩文词库验收。

三目录跨行测试覆盖三样式、两字体、90pt 宽度、长→短→取消、缓存与新建布局一致、每槽几何、后词不重叠和 canonical 恢复。固定参考及锁定 Anime 环境下 arabic-korean-regression.log 340 项零失败零跳过（631.039s，墙钟 631.086），含全部二十六生产宿主（589.228s，墙钟 589.231）、既有 Korean 路径、布局／投影／方向、两个退休测试集及 ASL／Choo 既有组件。arabic-korean-originality.log 固定参考边界退出 0，不扩大为全面原创性证明。

会话内风险审查核对完整差异、两个消费入口、候选隔离与保留回退，无剩余可落实发现，非独立评审。所有运行终态后写记录，零 Typebar 主程序启动。无数据格式／迁移或新网络行为。人工步骤待执行：逐目录选择 English／Arabic／Korean 自定义夹具，使用真实韩文输入法组合、退格拆分、取消和部分提交，逐样式检查候选窗／below 位置、窄窗跨行、全部字体及 Pace／ASL／Choo。未做新 Release、最低系统或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Khmer 混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，不复制源码或资产。自有 Unicode 夹具“ab سلام ខ្មែរ cd”进入实际 practiceContent 宿主，先复现字段未挂载：arabic-khmer-host-red.log 一项预期失败，1.907s／墙钟 1.908。生产仅增加 Khmer 共享投影准入，光标与组合显示两个入口共用该策略；Korean 等未验证混排保持回退。

四组尺寸策略覆盖初始与后段活动字段三样式，使用不匹配候选区分替换和保留原文，检查“ខ្មែ”→“ខ្មែរ”更新、取消、部分接受后标记“រ”、逐 UTF-16 单位回删、精确辅助文本、Arabic RTL／Khmer LTR 两端几何与原生输入／字段 owner 保持。夹具包含下标辅音与元音，但不代表全正字法／词库。另有三样式、两字体、90pt 宽度长→短→取消跨行回归，检查缓存／新建一致、每槽几何、后词不重叠和 canonical 恢复。

arabic-khmer-focused.log 30 项零失败零跳过（33.506s，墙钟 33.511）。固定参考及锁定 Anime 环境下 arabic-khmer-regression.log 297 项零失败零跳过（540.207s，墙钟 540.249），含全部二十三宿主（498.667s，墙钟 498.670）、布局／投影／方向、TapePromptRetirementTests／PromptWordRetirementTests 和 ASL／Choo 既有组件。arabic-khmer-originality.log 固定参考原创性边界退出 0，不扩大为全面原创性证明。会话内风险审查核对完整差异、两个消费入口、候选隔离和回退，无剩余可落实发现，非独立评审。

所有测试／审计终态后写记录，零 Typebar 主程序启动。无存储格式、数据迁移或新网络行为。人工步骤待执行：选择 English／Arabic／Khmer 自定义夹具，以真实 IME 逐一检查三样式更新／取消／部分提交、below 候选位置、窄窗恢复和全部字体，再验 Pace／ASL／Choo 可见组合。未做新 Release、完整冻结门禁或最低系统验证；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Kannada 混排生产入口（2026-10-10）

退休专项补充：实际测试集名称为 TapePromptRetirementTests 与 PromptWordRetirementTests（下文 TapeRetirementTests 为记录时的简称错误）。补跑 arabic-kannada-retirement.log 22 项零失败但一项因未传参考路径跳过，保留该日志。补齐固定参考和锁定 Anime 环境后 arabic-kannada-retirement-fixed-reference.log 22 项零失败零跳过（7.636s，墙钟 7.640）。未改测试断言或产品代码。

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的 test-ui.ts 候选显示分支只读复核，未复制代码或资产。新增实际 practiceContent 宿主使用自有 Unicode 夹具“ab سلام ಕಿರಣ cd”，先复现原生字段缺失：arabic-kannada-host-red.log 一项预期失败，1.923s／墙钟 1.924。生产仅增加 Kannada 的共享投影准入，原生光标与组合显示两个消费入口保持共用策略；Khmer 等未验证混排仍回退。

宿主覆盖默认／空／空／默认四组尺寸策略、Arabic 连字及 Kannada LTR 两端方向、初始和后段字段三种候选显示；以不匹配候选区分 replace 与 off／below，检查“ಕಿ”→“ಕಿರಣ”更新、取消、部分提交后标记“ರಣ”、逐 UTF-16 单位回删及输入／字段 owner 保持。该夹具不是完整 Kannada 正字法或词库证明。跨行测试另覆盖三样式、两字体、90pt 宽度、长→短→取消时复用／新建一致、每槽几何、下一字段不重叠与 canonical 恢复。

arabic-kannada-focused.log 30 项零失败零跳过（33.971s，墙钟 33.976）；固定参考与锁定 Anime 环境下 arabic-kannada-regression.log 273 项零失败零跳过（498.648s，墙钟 498.681），含全部二十二生产宿主（465.529s，墙钟 465.532）、布局／投影／方向和 ASL／Choo 既有组件。注意过滤器 PromptTapeRetirementTests 未匹配实际 TapeRetirementTests，不能将此次称为 Tape 退休专门回归。arabic-kannada-originality.log 固定参考边界退出 0，不扩称全面原创性证明。一次短进程采样确认缓冲期间运行到新增宿主，不作性能结论。

会话内风险审查核对完整差异、共享准入两入口、候选隔离和保留回退，无剩余可落实发现，非独立评审。所有运行终态后写记录，零 Typebar 主程序启动。无存储格式、迁移或网络变化，本机离线行为保持。人工步骤待执行：选择 English／Arabic／Kannada 自定义夹具，以真实 IME 在三样式更新／取消／部分提交，检查 below 独立候选位置、窄窗跨行与全部字体，并另验 Pace／ASL／Choo 可见组合。此次未做新 Release 或完整冻结门禁；TST-02／compositionDisplay 仍部分，完整 goal active。

## TST-02：原生菜单与 Indic 三样式增量完整冻结复验（2026-10-10）

冻结提交 3bad00958caf39beef3b19fa0fb5dec2a00d00c9，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。单次顺序门禁会话正常结束，gate_exit=0、hash_exit=0；847 个跟踪文件 SHA-256 终态一致。证据目录为 work/frozen-readiness.boLoNO，保留 revision.txt、inputs.sha256、gate.log、freeze-verification.log 和 logs/ 下 74 份分阶段日志。运行期间未修改源码、未重启门禁或启动 Typebar 主程序。

客户端 4,229 项零失败（1346.893s，墙钟 1347.363），服务端 501 项零失败（11.479s，墙钟 11.538）。此次包括新增原生语言菜单、Hindi／Tamil／Gujarati／Nepali／Sanskrit 生产入口及十一 Indic 活动字段三样式验证；全部二十一生产宿主和十万词耐久检查通过。Release 优化构建 397.07s，未打开应用包的资源边界、签名及固定参考原创性边界检查通过；边界审计不是全面原创性证明。

本次只记录验证，无产品、存储格式、数据迁移或网络行为变化。人工复验仍需单实例检查真实 IME 更新／取消／部分提交、below 候选位置、窄窗跨行及全部字体，再单独衡量首键性能；本门禁不替代这些可见行为，也不证明全部语言词库、精确主题、全部挑战或最低系统。TST-02／compositionDisplay 仍部分，完整 goal active。下方“新完整门禁未验”是历史阶段说明。

## TST-02：后段 Indic 活动字段的三样式生产验证（2026-10-10）

本轮只增强验证，不改产品。此前后段活动字段主要以 replace 检查，三样式宿主检查只在初始 Latin 字段。本次将 Bangla、Hindi 两目录、Tamil 三目录、Gujarati 两目录、Nepali 两目录与 Sanskrit 共十一目录的后段活动字段都按 off／below／replace 更新、取消、部分提交和回删。仍使用各自自有 Unicode 夹具及四组尺寸策略，不复制参考资产。

先标记不匹配的“X”：replace 要精确显示替换后的字段及剩余原文，off／below 要保留原目标字段；取消后精确恢复。之后运行短→整词候选、取消、接受首段再标记尾段，保留方向／输入和字段 owner 断言。每种样式结束按已提交的 UTF-16 单位数回删，再检查恢复与下一模式；不以相同目标候选的相同文字输出冒充样式区别。此处只验证目标字段文本，不证明 below 的独立候选视觉位置或 off 的系统候选窗行为。

indic-active-styles-focused.log 单项二十处失败（28.406s，墙钟 28.408）：新循环最初按首段 Character 数量回删，留下组合元音之前的已接受单位，污染后续样式。根因核对 NativeTypingInput 的 onDelete 链及 TypingEngine.removeLastTypedCharacter／removeAcceptedUnit，不能据此认定产品取消失败。仅清理循环改为 firstPart.utf16，原模式差异／精确文本／owner 断言未改，indic-active-styles-unit-isolation.log 同项零失败（27.899s，墙钟 27.900）。没有生产修复、重试或删除失败证据。

最终固定参考／锁定 Anime 环境下 indic-active-styles-final.log 109 项零失败零跳过（299.646s，墙钟 299.657），含十一完整宿主（296.819s，墙钟 296.820）、布局／候选投影及 Tape 退休；这是受影响路径专项，不是全部二十一宿主或全量门禁。indic-active-styles-originality.log 固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 边界退出 0。会话内风险审查核对样式分支、循环状态隔离与原有断言，无剩余可落实发现，非独立评审。

所有测试／审计终态后写记录，零 Typebar 主程序启动。无数据格式／迁移、网络或输入产品行为变化。人工步骤：以此前各目录自定义混排夹具进入 Arabic 后的 Indic 活动词，逐一切换三样式，真实 IME 输入不匹配候选、更新／取消和部分提交，检查候选窗／下方候选位置、方向与窄窗恢复；仍未执行。全字体、真实 IME、可见布局、最低系统与新完整冻结门禁保持待验；TST-02 和 compositionDisplay 仍部分，完整 goal active。下方“后半段只测 replace”为历史范围，本段补齐的仅是所列宿主专项。

## TST-02：Nepali／Nepali 1k／Sanskrit 混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 保持干净，只读复核 test-ui.ts 候选显示分支，未复制代码或资源。没有以既有 Hindi 验证代替其他目录：三个新实际 practiceContent 宿主分别复现字段缺失，arabic-devanagari-host-red.log 三项三处预期失败（3.003s，墙钟 3.005）。生产共享准入增加 Nepali、Nepali 1k、Sanskrit，Kannada 等未验证连写混排仍回退。

自有短文本“ab سلام किरण cd”作为 Unicode 输入夹具，不是参考词表或这三个语言完整正字法样本。PracticeCompositionHostTests 的四种尺寸策略保留三种初始候选显示更新／取消、提交／回删与 Arabic 连字检查；后续 replace 字段中的“कि”→“किरण”、取消、接受“कि”后标记“रण”，检查精确源辅助文本、两端方向及原生输入／字段 owner 保持。共享测试变量改称 Devanagari，Hindi 两项原行为与断言保持。

PromptFieldLayoutTests 对三个身份运行 Arabic 和天城文各自活动字段的长候选→短词→取消，覆盖三样式、两字体、90pt 宽度，保留复用／新建一致、每槽几何、实际多行、下一字段不重叠、canonical 前后方向和取消恢复。PolyglotDirectionTests 与 OrdinaryTapePracticeTests 检查三目录准入及 Kannada 的保留回退。

arabic-devanagari-focused.log 32 项零失败零跳过（58.210s，墙钟 58.215）。固定参考与锁定 Anime 环境下 arabic-devanagari-regression.log 172 项零失败零跳过（335.825s，墙钟 335.844），含全部二十一项生产宿主 326.330s／墙钟 326.333，以及方向／字段／投影、Tape 退休及 ASL／Choo 既有组件。arabic-devanagari-originality.log 固定参考边界退出 0，不扩大为全面原创性证明。

会话内风险审查核对完整差异、策略两入口、共享候选分段和旧覆盖，无剩余可落实发现，非独立评审。人工步骤待执行：自定义选择 English／Arabic／上述每个目录，使用该夹具检查真实系统输入法在三样式的更新／取消、Arabic 后天城文部分提交及窄窗跨行恢复；随后另验语言特有连字、字体、Pace／ASL／Choo。无存储变化，无数据迁移或新网络行为，本机离线练习保持。所有运行终态后写记录，零 Typebar 主程序启动；未做新 Release、最低系统、实体 IME 或完整冻结门禁。TST-02、compositionDisplay 仍部分，完整 goal active。

## TST-02：Arabic／Gujarati 两目录混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 保持干净，只读复核 test-ui.ts 的候选显示分支，未复制代码或资源。自有文本“ab سلام કિરણ cd”，Gujarati／Gujarati 1k 两个实际生产宿主先复现原生字段缺失：arabic-gujarati-host-red.log 两项两处预期失败（2.454s，墙钟 2.455）。生产只在共享投影准入增加两个目录；Nepali 等尚未验证的混排继续回退。

PracticeCompositionHostTests 在四种尺寸策略中保留初始字段三样式更新／取消、提交／回删及 Arabic lam-alef 检查，再以 replace 进入 Gujarati 字段，标记“કિ”→“કિરણ”、取消、接受“કિ”后标记“રણ”。断言精确源辅助文本、Arabic RTL／Gujarati LTR 两端物理顺序及字段／原生输入 owner 保持。带前置元音的夹具并不证明全部连字、所有样式在后段候选或真实系统输入法均已验收。

PromptFieldLayoutTests 的两目录跨行测试包含 Arabic 和 Gujarati 活动字段，三种样式、两种字体、90pt 宽度；长候选→短词→取消的复用与新建布局一致，每槽几何、实际多行、下一字段不重叠、canonical 前后方向和取消恢复断言保留。PolyglotDirectionTests 与 OrdinaryTapePracticeTests 验证两个目录准入、Nepali 保留回退；已有 Hindi／Tamil／Bangla 场景及断言没有删除。

arabic-gujarati-focused.log 31 项零失败零跳过（40.686s，墙钟 40.690）。固定参考及锁定 Anime 环境下 arabic-gujarati-regression.log 168 项零失败零跳过（286.463s，墙钟 286.481），其中全部十八项生产宿主 274.112s／墙钟 274.114；涵盖布局／投影／方向、Tape 退休、ASL／Choo 既有组件，不等于新 Gujarati 组合的全部可见效果验收。arabic-gujarati-originality.log 固定参考边界退出 0，只证明该审计范围。

会话内风险审查核对完整差异、共享准入两入口、候选分段与旧覆盖，未见剩余可落实缺陷，非独立评审。人工步骤仍待执行：在自定义练习选择 English／Arabic／Gujarati（另复验 Gujarati 1k），输入上述自有文本，逐一检查三样式的真实输入法更新／取消、Arabic 后 Gujarati 部分提交、方向及窄窗跨行恢复；全字体、Pace／ASL／Choo、最低系统与新完整冻结门禁均未验。无存储格式变化，不需迁移；本机离线输入，不增加网络或收集数据。所有测试／审计终态后写记录，零 Typebar 主程序启动。TST-02、compositionDisplay 仍部分，完整 goal active。

## Arabic／Tamil 三目录混排生产入口（2026-10-10）

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 保持干净，只读复核 test-ui.ts 组合候选显示分支，不复制代码／资源。Arabic／Tamil、Tamil 1k、Tamil Old 三个真实 practiceContent 宿主均先复现原生字段缺失：arabic-tamil-host-red.log 三项三处预期失败（2.997s，墙钟 2.998）。生产只增加这三个目录的共享投影准入；Gujarati 等未验证混排仍回退，既有语言、计时、存储与 shaping 实现不变。

自有文本“ab سلام கொடி cd”，默认／空／空／默认四组宿主尺寸策略保持。三种候选样式在初始字段更新／取消、提交／回删断言保留；随后进入 Arabic 字段验证 lam-alef 连接，再以 replace 进入 Tamil 字段验证带组合元音候选“கொ”→“கொடி”→取消，以及接受“கொ”后标记“டி”。精确辅助文本、Arabic RTL／Tamil LTR 两端顺序和原生输入／字段 owner 保持均检查。此处后半段不是三种样式下逐一实测，亦不代表全部 Tamil 连字／实体 IME。

三个目录另运行跨行长候选→短候选→取消，覆盖三种显示、两种字体、90pt 宽度、Arabic 与 Tamil 各自活动字段，检查复用／全新布局一致、每槽几何、实际多行、下一字段不重叠、canonical 前后方向及取消恢复。既有 Hindi／Bangla 场景未删除，广回归继续通过。

arabic-tamil-focused.log 32 项零失败零跳过（58.182s，墙钟 58.187）；固定参考及锁定 Anime 环境下 arabic-tamil-regression.log 165 项零失败零跳过（250.205s，墙钟 250.222），含全部十六项生产宿主（241.505s，墙钟 241.507）、方向、布局、候选投影、Tape 退休和 ASL／Choo 既有组件检查。后两者只是共享组件回归，不是新增 Tamil 场景的可见验收。arabic-tamil-originality.log 固定源边界退出 0，不冒称全面原创性证明。

会话内风险审查核对完整差异、共享准入两消费入口、回退与原有断言，没有剩余可落实发现，非独立评审。全部测试／审计终态后写记录，零 Typebar 主程序启动。没有新的 Release 构建、完整冻结门禁、最低系统、实体 IME 或全字体视觉验收；compositionDisplay 仍部分，94 配置分类与完整 goal active 不变。

## Arabic／Hindi 两目录混排生产入口与跨行候选（2026-10-10）

固定参考仍为 91bd24bb8513785c7364cbea29296ff7adafac41，工作树干净；只读复核 insert-text.ts 的组合结束输入边界，不复制源码或资产。新增实际 practiceContent 宿主以自有文本“ab سلام किरण cd”、English／Arabic／Hindi 选择复现原生字段未挂载：arabic-hindi-host-red.log 一项一处预期失败（1.809s，墙钟 1.810）。生产只把 Hindi／Hindi 1k 加入共享准入策略，不改变 shaping、计时或布局实现；Tamil 等未验证连写混排继续回退。

宿主沿用默认／空／空／默认四组 sizingOptions、内存 SwiftData 与隔离偏好；覆盖三种候选显示、更新／取消、提交／回删与输入 owner 保持。进入 Arabic 字段保留 lam-alef 连接，再进入 Hindi 字段，候选“कि”→“किरण”→取消；接受“कि”后标记“रण”，检查源辅助文本精确对应、原生字段／输入 owner 保持、Arabic RTL 与 Hindi LTR 两端物理顺序。Hindi 1k 独立宿主复验同样边界。该夹具覆盖带前置元音的多 UTF-16 单位，不代表全部天城文连字／实体 IME 验收。

跨行回归复用既有 Bangla 场景，在 Hindi 两目录分别验证 Arabic 与 Hindi 活动字段；三种显示、两种字体、90pt 宽度，十二次重复长候选→短词→取消。保留每槽几何、实际多行、后续字段不重叠、canonical 前后方向、主光标及复用与全新布局一致，取消恢复原 slots／aliases；没有删除 Bangla 断言。

arabic-hindi-host-focused.log 29 项零失败、一项因首次未提供参考环境跳过（22.376s，墙钟 22.380），不当作零跳过证据。补齐固定参考和锁定 Anime 归档后 arabic-hindi-regression.log 135 项零失败零跳过（179.134s，墙钟 179.148），含十二项完整宿主、布局／投影／方向／普通 Tape／退休回调；新增 Hindi 跨行 0.305s。随后补 Hindi 1k 宿主并整理共享测试变量，arabic-hindi-identities-final.log 四项零失败零跳过（52.970s，墙钟 52.972），包含 Hindi／Hindi 1k／Bangla 三宿主及 Hindi 跨行；之前广回归并不包含最后新增的宿主方法。

固定参考原创性边界退出 0；会话内风险审查检查两个策略消费入口、准入范围、测试保留及退休，不是独立评审。所有测试／审计终态后才写记录，零 Typebar 主程序启动。真实 IME、全部字体、RTL 基准段落与其他语言混排、Pace／ASL／Choo 组合实机及新完整冻结门禁仍待验；模型与不可见宿主不证明这些范围，compositionDisplay 部分与完整 goal active 不变。

## RTL 与 Bangla 增量完整冻结门禁通过（2026-10-10）

冻结已推送提交 2ca44a81659f8b1d713b301e19e8d1ed80681f7a，运行完整 check-native-rewrite-readiness.sh；固定参考 91bd24bb8513785c7364cbea29296ff7adafac41、隔离 Redis 6.2.6、锁定 Anime 归档保持。主会话 39486 权威退出 0 后才编辑本记录。845 个跟踪文件运行前 SHA-256 快照在终态全部核对通过；没有中途源码编辑、并行第二轮或因输出缓冲重启。

current-readiness.0Dztkm.gate.log、同名目录 74 份日志、.sha256 与 .hash-verification.log 保留。客户端 4,211 项零失败零跳过（1,061.620s，墙钟 1,062.074），服务 501 项零失败零跳过（11.198s，墙钟 11.255）。十一项完整生产宿主通过（178.169s，墙钟 178.171），包含新增 RTL／Arabic-Bangla 路径；十万词耐久 151.392s，官方脚本挑战完整原生会话 80.110s。跨行复用／取消、字体延迟目录访问、Tape 前缀退休异步回调检查均在完整套件中通过。

Release 构建 374.72s，未打开的应用包签名、资源边界与固定参考原创性边界通过；整个门禁零 Typebar 主程序启动。输出缓冲期间的一秒系统采样保留为 .client-sample.txt，确认实际已推进到 Hebrew／Persian／Urdu 词库检查；不作为性能基准。运行终态后已确认该客户端与编译进程结束。

此证据覆盖下方先前专项所缺的全量自动化复验，但不替代真实 IME、首键性能、可见窗口、全部字体／文字系统组合或人工验收；四项部分配置、精确主题 0／187、挑战剩余一项等仍开放。配置 89／4／1、compositionDisplay 部分和完整 goal active 不变。后文 ed098bf 等全量记录仅为此前冻结版本历史。

## 相反方向连写候选跨行、缓存复用与取消（2026-10-10）

本轮仅增强测试，不改变生产行为。新增布局回归在 English／Arabic／Bangla 自有文本上分别进入 Arabic 和 Bangla 活动字段，覆盖三种组合显示、monospaced／system 两种本机字体，固定 90pt 宽度，以十二次重复的长候选→原词短候选→取消运行。断言长候选实际多行、下一词不覆盖多行字段、每个当前槽有几何、canonical 前后目标及方向和主光标与全新布局一致；取消后 aliases 与原始布局恢复，旧扩展槽不残留。mixed-joining-wrap-focused.log 一项零失败（0.224s，墙钟 0.226），已有行为验证无故意失败阶段。

mixed-joining-wrap-final.log 205 项一失败（13.426s，墙钟 13.448）：新增跨行检查通过，旧 Tape 前缀退休测试在固定 10ms RunLoop 等待后未收到异步回调。mixed-wrap-retirement-reproduction.log 单项独立通过（0.631s，墙钟 0.632），故仅确认间歇性，不能据此认定无生产竞态。源码 deliverRetirement 明确使用主队列异步通知；测试改为等待实际回调，确认前缀与通知次数，再以主队列哨兵排空已排队的重复通知，保留光标、margin、累计修正和重复交付断言。1s 只作缺失回调的失败超时，不新增生产重试或放宽计时健康阈值。

mixed-joining-wrap-callback-final.log 同组 205 项零失败零跳过（10.871s，墙钟 10.891），固定参考原创性边界退出 0。全部运行终态后才编辑记录，零 Typebar 主程序启动。本轮没有新的完整宿主、全量门禁或 Release GUI；几何回归不等于实体 IME／全部字体／视觉检查，异步测试改进不证明排除所有退休竞态，compositionDisplay 部分与完整 goal active 不变。

## Arabic／Bangla 相反方向连写混排生产入口（2026-10-10）

固定参考仍为 91bd24bb8513785c7364cbea29296ff7adafac41，重新只读核对 test-ui.ts 候选槽循环及 below 初始化；未复制代码或资源。新增完整宿主场景选择 English／Arabic／Bangla，自有短文本“ab سلام বাংলা cd”，精确检查 AX 原文、Arabic RTL 与 Bangla LTR 的原生槽几何，并保留三种组合显示的既有更新／取消／提交回删检查。

arabic-bangla-mixed-red.log 一项一处预期失败：缺少 PromptFieldNativeView（2.181s，墙钟 2.182）。共享入口策略仅新增 Bangla 三个语言身份，其余未验证连写家族继续回退；方向和 Tape 入口测试增加正例并保留 Hindi 反例，未改变 shaping 标记、候选规则或计时健康阈值。arabic-bangla-mixed-focused.log 29 项零失败零跳过（21.899s，墙钟 21.904）。

随后增强活动 Bangla 字段：完成 Arabic 后候选由“বাং”更新为“বাংলা”，验证 LTR 槽顺序、取消不消耗原文，提交“বাং”后继续标记“লা”，AX 仍精确保持原文，输入及字段 owner 保留。arabic-bangla-mixed-active.log 29 项零失败零跳过（24.231s，墙钟 24.235）；最终 arabic-bangla-mixed-final.log 215 项零失败零跳过（195.043s，墙钟 195.066），涵盖全部十一项完整宿主、字段／光标、方向、组合、普通 Tape 和 Tape 前进。固定参考原创性边界退出 0，所有运行终态后才编辑记录，零 Typebar 主程序启动。

三身份策略覆盖不等于逐词库或实体 Bangla IME 验收；活动字段增强不代替全部样式、跨行和字体组合。Hindi 等混排仍回退，真实 IME、可见窗口与首键问题仍开放，compositionDisplay 部分及完整 goal active 不变。本轮无新全量门禁／Release GUI；下方 Bangla 回退说明为历史快照。

## 其余 RTL 家族混排入口与全身份策略检查（2026-10-10）

新增 Pashto、Sindhi、Central Kurdish、Yiddish 四项完整生产宿主测试，使用自有短文本中特有文字 run，检查原始 AX 文本、RTL 几何、三种候选显示、更新／取消／提交回删和输入及字段 owner 保留；前三种同时验证活动候选的 lam-alef 连字与部分提交后继续连写。四组隔离尺寸配置不变，无可见窗口。

remaining-rtl-mixed-red.log 四项四处缺少原生字段的预期失败（5.080s，墙钟 5.082）。扩展共享策略后 remaining-rtl-mixed-final.log 214 项两处失败（175.481s，墙钟 175.504）：新增十项宿主全部通过，但遍历所有 RTL 身份发现原策略遗漏 Urdu 5k。保留检查并补齐该身份后，remaining-rtl-mixed-corrected.log 同组 214 项零失败零跳过（175.190s，墙钟 175.213）。固定参考原创性边界检查退出 0；全部测试与审计终态后才编辑本记录，零 Typebar 主程序启动。

所有 RTL 语言身份的策略覆盖不等于逐词库、逐字体或实体 IME 验收；完整宿主仅十项代表路径。RTL 与 Bangla／Hindi 等未验证连写混排继续回退。真实 IME、跨行／字体、可见窗口及首键性能仍开放，compositionDisplay 仍部分，goal active。本轮未重跑完整门禁或 Release GUI，下方 ed098bf 全量证据不覆盖这些新增策略。后文“Pashto 等仍回退”为历史快照。

## Persian／Urdu 混排生产入口与特有字形（2026-10-10）

新增 Persian、Urdu 各自的完整生产宿主测试，隔离选择／存储和四组尺寸配置不变。persian-urdu-mixed-host-red.log 两项两处预期失败（3.349s，墙钟 3.350），两种配置均缺少 PromptFieldNativeView。共享策略加入 Persian 四个词库与 Urdu 两个词库，未改变原生整词 shaping、输入规范化或计时器；策略与 Tape 入口测试同步验证新增家族及 English／Arabic／Persian／Urdu 共存，Pashto 作为仍未验证家族保留回退反例。

persian-urdu-mixed-host-final.log 210 项零失败零跳过（116.048s，墙钟 116.072），含全部六项完整宿主、字段／光标、方向、组合、普通 Tape 和 Tape 前进。随后强化自有文本：Persian“ab سلام پیام cd”、Urdu“ab سلام ٹماٹر cd”，精确检查源文本和两种特有文字 run 的 RTL 几何，在 replace 候选更新后重复验证；活动字段仍检查非空 lam-alef 连字、取消不消耗源槽、部分提交后继续候选、输入及字段 owner 保留。

persian-urdu-mixed-specific-letters.log 30 项零失败但漏传参考导致一项源码测试跳过（36.377s，墙钟 36.381），不算完整专项通过。终态后补固定参考／归档重跑，persian-urdu-mixed-specific-pinned.log 30 项零失败零跳过（37.582s，墙钟 37.587）。固定参考原创性检查退出 0，全部测试与审计终态后才编辑文档，零 Typebar 主程序启动。

新增特有字形证据针对提示中未改动的 run，不等同所有 Persian／Urdu 实体 IME 候选、字体或跨行组合。其他 mixed shaping 家族、真实键盘／IME、可见窗口和首键性能仍开放；compositionDisplay 仍部分，完整 goal active。未重跑本次新策略之后的完整门禁／Release GUI，下方 ed098bf 全量证据仅覆盖此前冻结版本。

## 混排入口完整冻结门禁复验通过（2026-10-10）

冻结已推送 ed098bf988109dab51331e90546f19cbbcc2ad55，完整重跑 check-native-rewrite-readiness.sh；固定参考 91bd24bb8513785c7364cbea29296ff7adafac41、Redis 6.2.6 和锁定 Anime 归档不变。主会话 17756 权威退出 0 后才编辑记录。845 个跟踪文件运行前 SHA-256 快照在结束后全部核对通过；期间无源码编辑、并行第二轮或因日志缓冲重启。

mixed-readiness-retry.kwidkd.gate.log 及同名目录的 74 个日志保留。客户端 4,202 项零失败（996.969s，墙钟 997.476），服务 501 项零失败（13.397s，墙钟 13.464）；客户端无跳过记录。旧 Tape 入口检查在完整套件中通过，Hebrew／Arabic 混排及原有完整宿主四项均通过，十万词耐久通过（156.082s）。历史磁盘模型、固定源码行为及各项元数据／身份审计完成。

Release 生产构建 443.44s，未打开的 macOS 应用包签名、资源边界、原创性及包检查通过。该轮结束后无 Typebar、测试或编译残留进程，零图形主程序启动。系统 CoreData／只读存储告警保留在日志中，不替代 XCTest 及门禁退出结果。

本记录只证明上述冻结版本自动化门禁通过，不证明真实键盘／IME、可见 WindowGroup、首键性能或所有混排 shaping／字体／跨行／队列已完成。配置仍 89 映射／4 部分／1 不适用，主题精确映射 0／187、平台挑战一项及人工验收仍开放，完整 goal active。首轮失败证据继续保留，不以复验覆盖旧日志。

## 混排入口完整冻结门禁首轮与旧断言更新（2026-10-10）

冻结 ab53dcb754d8b602f41610569336247a310c4bcc 的 845 个跟踪文件，运行完整 check-native-rewrite-readiness.sh，固定参考、Redis 6.2.6 和 Anime 归档不变。mixed-readiness.K4qccV.gate.log 保留主日志；会话 66062 权威退出 1 后才编辑，源码 SHA-256 核对完成。客户端 4,202 项一处失败（992.841s，墙钟 993.320），失败为 OrdinaryTapePracticeTests 要求入口源码直接包含旧 RTL 回退条件的字符串，而生产已改为共享 PromptFieldProjectionPolicy。

此轮十万词耐久通过（159.098s），官方脚本完整原生会话通过（82.432s），新增 Arabic／Hebrew 完整宿主及原有两种宿主均通过。元数据、页面／服务表面、布局／主题／挑战身份、固定源码行为和历史磁盘模型准备完成；客户端失败后没有继续服务测试或 Release 打包，不将此轮写成全量通过。临时目录未自动清理或归档，终态后将其 72 个日志复制到上述保留目录，未覆盖其他证据。

更新旧测试而非生产逻辑：仍检查 gate 不排除 Tape、composition 非 nil 条件，以及实际接线共享策略；增加 English、Hebrew／Arabic 混排允许与 Persian 混排保留回退的执行断言。失败日志保留，没有删除测试、恢复旧功能限制或跳过失败。shared-projection-gate-final.log 为专项复验，完整门禁仍需在新冻结版本重跑。零 Typebar 主程序启动，真实 IME、首键性能和完整兼容 goal 仍开放。

## Arabic／LTR 混排整词候选入口（2026-10-10）

继续基于固定版本候选逐槽显示规则推进 production gate。新增完整宿主以隔离选择恢复自有“ab سلام cd”与 English／Arabic 自定义配置，三种组合模式复用既有更新／取消／提交／回删检查。arabic-mixed-projection-red.log 两项四处失败（2.382s，墙钟 2.383）：生产宿主缺少字段渲染器为真实入口缺口；模型另三处来自复用了 noSpaces 辅助函数，使源槽编号不再对应原文，不算产品 shaping 故障。

模型改为保留空格的直接会话后 arabic-mixed-field-identity.log 通过。检查整词宽度小于孤立字形之和、Arabic 两端实际物理顺序、lam-alef 同一连字几何但 canonical 槽各自保留、各槽方向及相邻字段不重叠。未为获得绿色修改原生 TextKit shaping 或方向实现。

入口共享策略扩展 Arabic、Arabic 10k、Egypt／Egypt 1k、Morocco 家族，Hebrew 保持；其他尚未验证的混排 shaping 继续回退。策略测试包含 English／Hebrew／Arabic 共存以及 Persian 的保留回退，单一 Arabic 的原支持不变。arabic-mixed-projection-green.log 16 项零失败零跳过（16.212s，墙钟 16.215）。

完整宿主进一步进入 Arabic 活动字段，标记“سلا”时检查 lam／alef 非空测量框相等；取消后源文本不变；提交“س”再标记“لا”，原生输入及字段 owner 保留、辅助文本仍精确对应源文。新 marked 几何断言明确 XCTUnwrap 双端，不接受 nil==nil 的伪通过。arabic-mixed-projection-final.log 194 项零失败零跳过（79.676s，墙钟 79.700），包含四种完整宿主、字段、光标、方向、组合与 Tape 前进。固定参考原创性检查退出 0；所有测试／审计终态后才写本记录。

零 Typebar 主程序启动，无新全量门禁／Release GUI。当前证据不覆盖全部 Arabic 内容、字体、显式 bidi 控制、跨行候选、真实键盘／IME或长期队列，也不证明首键性能解决；Persian 等混排仍开放，compositionDisplay 仍部分，完整 goal active。

## Hebrew／LTR 混排组合生产入口（2026-10-10）

只读核对官方 test-ui.ts 的候选循环：组合候选逐槽参与显示，replace 改为候选文本，off／below 保留对应目标，超出目标的候选仍显示。参考仓库干净且 HEAD 为 91bd24bb8513785c7364cbea29296ff7adafac41；未复制源码或资产。原生模型已有独立槽与方向几何，但生产 mixed RTL gate 仍拒绝该模型。

新增完整生产宿主测试，从隔离 active selection 恢复自有文本“ab אב cd”、English／Hebrew 混排自定义配置；mixed-composition-host-red.log 一项一处失败（2.406s，墙钟 2.408），组合时找不到 PromptFieldNativeView。第一版按 usesJoiningScriptPrompt 分类后 green 日志仍失败（2.666s，墙钟 2.667）：该项目标志包括 Hebrew 的整词排版，并非严格的连接字形分类。保留既有 shaping 参数，不改变全局语言排版定义，改为明确允许 Hebrew 四个词库及其非 shaping 混排伙伴，其他混排 shaping 家族保持原回退。

统一 PromptFieldProjectionPolicy 同时用于投影入口和独立光标条件，防止原生字段与 inline 光标同时生成。方向策略测试覆盖 Hebrew 四库、English、单一 Arabic 的既有支持，以及 English／Arabic 和 English／Hebrew／Arabic 混排的保留回退。mixed-composition-host-shaping.log 15 项零失败零跳过（14.523s，墙钟 14.526）。

最终完整宿主增加恢复文本精确相等断言，测量 Hebrew 两槽物理顺序，并在 replace 候选更新后再次核对未改动 Hebrew run；三种组合模式、候选更新、取消不提交、提交后推进及回删还原继续使用完整生产页。mixed-composition-host-final.log 192 项零失败零跳过（63.295s，墙钟 63.315），包括完整宿主、字段／光标、方向、组合与 Tape 前进。固定参考原创性检查退出 0，所有进程终态后才编辑文档。

零 Typebar 主程序启动。不可见宿主不是系统键盘／IME或可见窗口验收；本次只证明该 Hebrew 混排接线及明确场景，不证明全部 bidi 控制／标点／跨行、Arabic 等混排、Pace 长期退休队列或首键性能。没有新全量门禁／Release GUI，compositionDisplay 仍部分，完整 goal active。

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
