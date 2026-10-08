# 原生奖励收件箱与周任务交付

## Tape 横向旧词退休增量

最终冻结门禁 `/tmp/typebar-tape-retirement-final-readiness.log` 终态退出 0：原生 3,865 项零失败零跳过（835.952 秒），服务 501 项（12.147 秒）；十万词耐久 154.005 秒、16 项隔离磁盘冷读 4.514 秒、53 表面、1,107 唯一人工场景结构、90／3／1 配置元数据和未启动应用包资源／URL scheme／严格签名／原创边界通过。12 新增在全量中 0.318 秒，128 原有轨迹／32 新增退休轨迹／28 方向案例通过。13 文件 `/tmp/typebar-tape-retirement-final-frozen.sha256` 门禁前中后完全一致，64 原始日志 `/tmp/typebar-tape-retirement-final-logs.RbJf6z` 和 163 图 `/tmp/typebar-tape-retirement-final-images.1fYhpi` 保留；最终四张 tape-retirement-{ltr,rtl}-{before,after}.png 已再次逐张检查。既有 CoreData／AddressBook XPC、隔离只读 SwiftData 513、编译／Node 警告保留，不宣称修复。终态后仅补交付文档，没有运行中编辑或并行验收；零主程序启动，无残留测试／编译／主程序进程，参考仍干净，未操作真实账户、Keychain、成绩库或部署。完整 goal active，下方为阶段证据。

2026-10-09，固定干净参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整 `scrollTape` 在请求新滚动之前，以既有呈现位置检查先前词：LTR 的 floor(left) 严格小于负 floor(width)，RTL 的 floor(left) 严格大于 wrapperWidth。删除后立即修正 words margin，并以反向符号修正 RTL 主／pace 累计补偿；这不是等待动画结束的普通换行退休。完整 `before-delete.ts` 在 freedom 前检查前一节点存在，hard 恢复也依赖节点仍存在。

原生复用 canonical 词 ID、`PromptLineScrollContext` 和会话单调退休边界，读取同一 TextKit 词框及最后呈现横向位移。通知推迟到主队列，避免在 SwiftUI 更新中发布会话变更；代次／尝试身份使重开、拆卸、布局和较新输入失效旧回调。确认裁前缀时从旧布局测量位移，立即重定 words 原点并修正两个 marker owner，再请求剩余提示的滚动。纯确认和无变化重绘不再次退休；合并真实新输入仍重新计算。缺失 pace 目标保留既有位置／折叠状态，保留目标重测而不跳动。没有增加定时器、持久字段、依赖或官方产品代码／资产；完整提示、输入、统计与归档仍保留。

QA 执行完整固定 `scrollTape`／`Caret`／RAF 和校验完整性后的 Anime.js 4.2.2，保留原 128 条轨迹／28 个方向案例，增加 32 条 LTR／RTL × letter／word × 四类 marker × 即时／平滑的实际删除轨迹。词节点真正从自有 DOM 边界中移除，逐帧对照 words、两个 marker 的位置／margin／累计修正／完成标记；不是浏览器 CSS、换行、反向模式或任意调度证明。

先行 `/tmp/typebar-tape-retirement-red.log` 四项 9 个有效失败，接口仅接收未使用的 context，不提前实现行为。`first-focused.log` 43 项中两项缺环境跳过及一处测试错误（RTL 流中的英文仍 LTR），不是最终证据。`source.log` 保留新删除分支首次触及自有 DOM style 缺失的失败；补齐该边界。`expanded.log` 保留测试误访问私有 replay 的编译错误，改为副本 bailout 后的真实 result 回放，不拓宽产品可见性。`expanded-built.log` 49 项 18 处失败定位到重复重绘二次退休、确认再次退休，以及 563ms 终点的一 ULP 舍入。前两者分开真实请求与确认；共享 tween 只允许终点的一个可表示邻点，不放宽实际较早帧。`fixed.log` 77 项仅剩确认反例，修复后 `final-focused.log` 119 项通过。以上短日志名均使用 `/tmp/typebar-tape-retirement-` 前缀。

最终 `/tmp/typebar-tape-retirement-handoff-focused.log` 120 项零失败零跳过（40.321 秒），其中 12 新增 0.313 秒。覆盖阈值、前一呈现帧、平滑中退休、重复确认、重开／停止／回退取消、真实 freedom 删除边界／回放、丢失及保留 pace 目标和生产接线。`/tmp/typebar-tape-retirement-images.6Hlpk5/tape-retirement-{ltr,rtl}-{before,after}.png` 四张已逐张复查；两方向各自裁前后可见 PNG 完全相同。窗口从不显示且关闭，零主程序启动；透明留白／边缘裁剪为实际组件，不是完整应用或实机验收。

同会话风险／决策复核检查了重复请求、确认与新输入合并、取消身份、前缀几何、反向符号、共享动画终点、pace 缺失和原始数据保留，不是独立评审。`tapeMode` 保持部分、配置 90／3／1 和 53 表面分类不升级。明确换行／afterNewline、复杂控制／hint／no-space／全部 joining 与混排、任意异步设备顺序和视口虚拟化仍开放；完整重写 goal active，未以定向结果替代全量。

## Tape RTL 与独立词方向增量

最终完整冻结门禁 `/tmp/typebar-tape-direction-final-readiness.log` 终态退出 0：原生 3,853 项零失败零跳过（851.233 秒），服务 501 项（12.327 秒）；十万词耐久 153.047 秒、16 项隔离磁盘冷读 5.216 秒、53 表面、1,105 唯一人工场景结构、90／3／1 配置元数据及未启动应用包资源／URL scheme／严格签名／原创边界通过。十二新增在全量中 0.314 秒，128 条完整源码轨迹和 28 方向案例通过。13 文件 `/tmp/typebar-tape-direction-final-frozen.sha256` 门禁前中后完全一致；64 原始日志 `/tmp/typebar-tape-direction-final-logs.EhiXHn`、159 图 `/tmp/typebar-tape-direction-final-images.rvafDV` 保留，最终三张 rtl-tape-{initial,moving,word}.png 已逐张复查，是实际原生文字／独立 marker 组件而非完整应用窗口。既有 CoreData／AddressBook XPC、隔离只读 SwiftData 513、编译／Node 警告保留，不宣称修复；无断言失败或跳过。终态后才更新交付文档，无运行中编辑或并行验收；零主程序启动，无残留测试／编译／主程序进程，参考仍干净，未操作真实账户、Keychain、成绩库或部署。完整 goal active，以下为阶段证据。

审计分区更新后 `/tmp/typebar-tape-direction-audit-focused.log` 为相关 140 项零失败零跳过（20.964 秒）；缓存固定行起点避免每帧 TextKit 测量后 `frozen-focused.log` 为 140 项（21.153 秒）。随后将 RTL 参数限制到实际 Tape 调用，ASL／Choo 继续默认 false，生产接线断言同步；最终 `handoff-focused.log` 的 140 项零失败零跳过（20.420 秒），十二新项 0.302 秒及完整原版对照通过。实际完整门禁已冻结源、测试、元数据生成器／总账、配置审计和人工清单，终态之前没有修改，结果见首段。

2026-10-09，固定干净参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整 scrollTape 按测试全局方向反转文字／pace 横向补偿；完整 Caret.getTargetPositionAndWidth 则按词方向选择锁定边缘，custom／Zen／Polyglot 改按当前字母判断，不能整体镜像。完整 strings 的检测／裁边／缓存模块也执行。既有实际 Anime.js 4.2.2、RAF 与完整 Caret／scrollTape QA 扩为 128 条测试方向 × 词方向 × letter／word × 四类 marker × 即时／平滑／重叠／折叠轨迹，另对照 28 个方向案例；数字、标点、符号和 U+200B 有覆盖。所有词框、CSS margin、时钟、页面状态均为自有边界，不是浏览器 CSS／真实字体数值、reverse-direction、换行／裁词或任意调度证明。

原生 Tape 不再因 RTL 回退普通提示，仍对明确换行保留未完成回退。TextKit 保留有界自然原点和测试基方向，以逐词 writingDirection embedding 模拟独立 inline 词框，不向显示字符串／原文／输入／回放插入控制字符；使用同一布局管理器的占位框而非含字形外伸的墨迹包围框。文字滚动读取测试方向和实测词／词内宽度；主 marker 按词／字符方向选左右 margin，word 模式保留词内位置，pace after 和 marker 绘制按自己的目标方向。自定义／Zen／混合语言接通逐字符策略。共用光标缓存已解析的方向，不每帧额外调用 fresh glyph provider；普通／ASL／Choo 未指定 resolver 时沿用旧逻辑。方向切换、新尝试、停止／拆卸沿用既有 coordinator 与计时器，没有新依赖／Timer／持久字段或存储迁移。

红测 `/tmp/typebar-tape-direction-red.log` 四项 17 处真实失败（0.852 秒）；`first-green.log` 九项仅剩一处前进距离失败。`glyph-diagnostic.log`／`enclosing-diagnostic.log` 证明 Hebrew 首字墨迹宽 33.38671875 而占位宽 17.74609375；按 SDK 26.2 NSLayoutManager／NSAttributedString 头文件的 enclosingRects 与 writingDirection 契约修正。`focused.log` 28 项两处失败另抓出 Foundation 空白集吞掉 U+200B，以及测试错把上下文 kerning 宽当独字宽；用原版 Unicode 裁边规则和实际 glyph 位置差／总 advance 回归，不放宽容差。`focused-green.log` 28 项零失败零跳过（1.550 秒）。`expanded.log` 132 项两处失败抓出新增方向绘制重复读取原生 glyph provider，已缓存解析方向；`word-order-red.log` 两项两处真实失败（0.679 秒），相邻反向词第二词进度为负，普通 provider 回归已绿；逐词嵌入后 `final-focused.log` 133 项零失败零跳过（5.942 秒），其中十二新增 0.296 秒。三图 `/tmp/typebar-tape-direction-images.otedHz/rtl-tape-{initial,moving,word}.png` 已逐张检查，实际文字／锁定 marker 与词内 marker 可见，是隔离原生组件而非完整窗口；所有组件窗口从不显示并逐一关闭，零主程序启动。

行为优先、源码驱动、最小改动、根因调试及同会话有界决策／风险审查影响上述反例，不是独立评审。frontend-design 保留既有字体、配色、间距和 marker 设计，仅纠正方向／文字测量。Swift 6.2.4／SDK 26.2／最低 macOS 14，新增使用的原生接口由已安装 SDK 头文件核实，兼容最低版本。审计发现 tapeMode 原先只按可保存配置标为映射，但换行／横向退休尚缺，现下调部分覆盖；94 配置变为 90 映射／3 部分／1 不适用，生成器、固定总账与原生分区断言同步。53 表面和 Funbox 分类不升级，两新增人工项仍待验。Tape 换行／afterNewline／前缀退休、全部混排与 joining／hint／零宽组合、真实逐帧／键盘／IME、字体资源及视口虚拟化继续开放；完整 goal active。最终冻结结果见本节首段，以下为历史阶段。

## 字体命令临时预览与清除生命周期增量

最终完整冻结门禁 `/tmp/typebar-font-command-preview-final-readiness.log` 终态退出 0：原生 3,841 项零失败零跳过（828.316 秒），服务 501 项（11.414 秒）；十万词耐久 155.429 秒、16 项隔离磁盘冷读 4.740 秒、53 表面、1,103 唯一人工场景结构、元数据及未启动应用包资源／URL scheme／严格签名／原创边界通过。11 新增在全量中 0.686 秒；12 条完整字体预览轨迹及既有配置／居中回归通过。九文件 `/tmp/typebar-font-command-preview-final-frozen.sha256` 门禁前中后完全一致，64 原始日志 `/tmp/typebar-font-command-preview-final-logs.5dzdLf`、156 图 `/tmp/typebar-font-command-preview-final-images.7Vdg73` 保留；最终三张 font-command-preview-{initial,active,restored}.png 已逐张复查，显示实际文字宽度／换行变化和恢复，透明留白不是完整应用窗口。无断言失败／跳过，既有 CoreData／AddressBook XPC、隔离只读 SwiftData 513、编译／Node 警告原样保留，不宣称修复。终态后才更新交付文档，没有运行中编辑或并行验收；零 Typebar 主程序启动，无残留测试／编译／主程序进程。未操作真实账户、Keychain、成绩库或部署；完整 goal active，以下为阶段证据。

2026-10-09，固定干净参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。原版 fontFamily subgroup 的 hover 回调调用 previewFontFamily；完整 updateActiveCommand 先清旧预览，再执行新命令 hover，空结果／非字体／hide 也清除。完整 preview／apply／clear 有重要差异：preview 不读本地字体文件，clear 以当前 Config.fontFamily 重设 CSS，不重新执行本地文件及语言 preferred-font 的 apply；apply 本身不清 isPreviewingFont。新 QA 脚本执行完整上述函数、完整 active-command／hide 和实际 hover 回调，12 条含 store／chain／legacy、local／preferred、空与非字体、期间改保存名、重复清除的轨迹通过。DOM、modal、文件／语言读取与保存名变更是自有边界，不是实际浏览器、完整 setter／异步文件调度或字体像素对照。

原生新增独立临时预览状态，复用命令面板既有鼠标／键盘活动项回调和关闭生命周期。固定 43 项与系统设计可预览，文件／导航动作不预览；共用 practicePromptNSFont 同时服务提示文字、视口、普通／ASL／Tape／Choo 与光标测量，预览和按名称恢复都绕过本地文件覆盖／preferred 级联，不停用、删除或注册字体。恢复读取当前保存名而非旧快照；真正应用字体清临时覆盖，但保留原版 preview flag 至后续 clear。新增不持久化的字体应用代次，使同值和归一化名称事件不被 onChange 值相等吞掉，与 wrapper revision 分开，不引发强制旧词清理。语言／本地文件应用及挑战切换清覆盖，Wingdings 挑战的保存名取挑战有效名，不误用普通设置或离开后残留。

红测 `/tmp/typebar-font-command-preview-red.log` 四项 52 处真实失败（0.701 秒），验证缺预览／解析／生产接线；首绿 `first-green.log` 相关八项零失败 0.141 秒。扩大轮 `focused.log` 保留测试里值类型 session 误用 let 与嵌套 Model actor 编译错误，不当作行为红测；修正测试声明后 `focused-built.log` 相关 54 项零失败零跳过（10.310 秒）。收尾补挑战离开时清覆盖，最终 `final-focused.log` 54 项零失败零跳过（10.309 秒），其中 11 新增 0.758 秒；source.log 的 12 条完整函数轨迹通过。真实 CommandPaletteView 出现／消失回调、保存状态不变、原始输入／会话／回放、同值／归一化、当前名恢复、本地 resolver 不被读取、挑战有效名及生产共用字体接线有回归。三图 `/tmp/typebar-font-command-preview-images.upjeVS/font-command-preview-{initial,active,restored}.png` 已逐张检查，是带透明留白的隔离组件位图而非完整应用窗口；窗口从不显示并逐一关闭，零主程序启动。

行为优先／源码驱动／最小改动、根因调试及同会话有界决策／风险审查影响上述边界，不是独立评审。frontend-design 保持已有原生面板配色、字号层级和布局，只补字体交互；Swift 6.2.4／SDK 26.2／最低 macOS 14，无新依赖／Timer／持久化字段或存储迁移。SettingsPage nativeTestSymbols 与两人工待验项补证，94 配置仍 91 映射／2 部分／1 不适用，字体和其他分类不升级。全部周边页面字体、真实 hover／键盘、文件异步／字体加载与排版竞态、全部字体资产／joining／IME、Tape RTL／换行／退休、长预览与视口虚拟化、设备仍开放；完整 goal active。最终冻结结果见本节首段，以下为历史阶段。

## Wrapper 配置事件与 fontFamily 例外增量

最终完整冻结门禁 `/tmp/typebar-wrapper-config-final-readiness.log` 终态退出 0：原生 3,830 项零失败零跳过（823.735 秒），服务 501 项（12.613 秒）；十万词耐久 153.530 秒、16 项隔离磁盘冷读 4.890 秒、53 表面、1,101 唯一人工场景结构、元数据及未启动应用包资源／URL scheme／严格签名／原创边界通过。十新增在全量中 4.560 秒，64 源码链路及既有 56 center／退休路径通过；四张最终组件图已再次逐张检查。10 文件 `/tmp/typebar-wrapper-config-final-frozen.sha256` 门禁前中后完全一致；63 原始日志 `/tmp/typebar-wrapper-config-final-logs.lCodvg`、153 图 `/tmp/typebar-wrapper-config-final-images.rW5apb` 保留。无断言失败／跳过，既有 CoreData／AddressBook XPC、隔离只读 SwiftData 513、编译／Node 警告保留，不宣称修复。终态后才更新交付文档，没有运行中编辑或并行验收；零主程序启动，无残留测试／编译／主程序进程，没有操作真实账户、Keychain、成绩库或部署。完整 goal active，下方记录阶段证据。

2026-10-09，继续基于干净固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整 setConfig 在成功时即使值未变也派发；test-ui EOF 订阅有 12 个 wrapper 键，fontFamily 明确例外，只更新 hints／joining。元数据另为 tapeMode、tapeMargin、maxLineWidth、fontSize、keymapSize 触发 resize；完整 UI 250ms debounce 在非 Tape 测试页调用 center，raw showAllLines 仍抑制退休。QA 新脚本执行完整 setter 模块、createEvent 模块、完整订阅／wrapper／center／lineJump／removal、resize 回调与 triggerResize，并读取实际选定元数据对象。64 组含 raw gate／nosave、四次重复同值／ABA 和拒绝设置通过；validation、DOM 整数尺寸与 debounce drain 是自有边界，Joining 模块仅非 joining 路径，不冒充浏览器、CSS、实际 250ms 调度或专业文字排版。

原生 AppSettings 增加不持久化的 wrapper revision，映射 12 类 wrapper 设置及 keymapSize resize，宽度预设和自定义值共用事件；同值／ABA 不丢事件，字体家族、主题和滚动平滑开关不虚构 wrapper。生产 factory 和普通／ASL 两桥接层传递 revision，滚动 owner 区分字体重测与强制居中，沿用既有动画、raw gate 和退休回调，不新增 Timer 或存储字段。现有 funbox UI 恢复流程的拒绝选择／恢复均不派发；原始输入、prompt、退格边界、结果与 replay 不删。

行为红测 `/tmp/typebar-wrapper-config-red.log` 为三项 15 处真实失败（0.786 秒），复现漏配置事件、fontFamily 误退休及后续纯配置不居中；首绿四项 0.157 秒。拒绝设置补测 `rejection-red.log` 一项三处真实失败（0.659 秒），补保护后通过。扩大轮 `focused.log` 保留嵌套函数 actor 编译失败；`focused-built.log` 的普通标点夹具失败不是产品丢事件：TextKit 允许感叹号内部断行，没有所声称的第三词行，ASL 同夹具通过。普通改用字母词并增加实测行高断言，ASL 保留标点 fallback，不放宽边界断言。`focused-green.log` 的 121 项七处失败来自调用方漏传既有 Anime.js QA 归档，十项中的当时九项新测试已通过；最终带归档的 `final-focused.log` 为 122 项零失败零跳过（36.558 秒），十新增 4.617 秒。`normalization-red.log` 名虽为 red，实际一项首次即绿（0.014 秒），仅补归一化／持久化回归，不作为红测证据。

四张 `/tmp/typebar-wrapper-config-images.idihoo/wrapper-{text,asl}-{font,event}.png` 已逐张检查；组件窗口从不显示且逐一关闭，零 Typebar 主程序启动。行为优先、源码驱动、最小改动、根因调试与同会话有界决策／风险审查用于上述反例，不是独立评审。保留既有原创颜色、手形和原生间距，无视觉改版；Swift 6.2.4／SDK 26.2／最低 macOS 14，无新版本敏感 API、依赖或存储迁移。新增 nativeTestSymbols 与两个人工待验项；配置 showAllLines／fontFamily 和 ASL 部分分类不升级。原生交互对照 32 组；nosave 的另外 32 组仅原版探针，预览／导入／全部 UI 入口、真实 resize 调度／回流交错、joining、全量预览／视口虚拟化与设备／IME 继续开放，完整 goal active。完整冻结门禁待本轮终态记录；以下为历史阶段。

## 活动行重新居中与强制退休增量

2026-10-09，固定只读源码 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整 `centerActiveLine` 从活动词向前扫描词容器，找到较早行后调用 `lineJump(previousLineTop, true)`，即使首跳也可退休；窗口 resize 的 250ms debounce 与 wrapper 配置更新分别调用它。原始 `Config.showAllLines` 为 true 就直接返回，与计时模式仍使用有限视口的有效高度策略不同。本轮只重写原生重新布局／全行返回有限行的行为，不复制函数或资产。既有 QA 脚本新增执行完整 center 函数、完整 lineJump／removal 的 48 组自有整数词框／缺失词／长词／首跳／平滑组合，原有 12 序列／60 行、32 before-delete、八 hard-recovery 不变；DOM 和 promise 完成由适配器提供，不是浏览器数值或真实 resize 调度证据。

共用 PromptAutoScrollView 在重新布局时测量旧词，按前一个词容器而非长词内物理行确定清理边界；强制首跳沿用现有动画、光标协调器和退休回调，平滑完成才裁前缀，减少动态立即完成，无新 Timer。全行关闭后的新有限行 owner 同样生效；普通与 ASL 桥接层必须保留原始开关。前缀重建不再强制重复退休，原文、已接受输入、纠正边界、结果和 replay 不删；无可清理前缀的强制调用仍计跳行。原始开关抑制布局居中与退休，正常逐词跳行、输入回流策略和原生长词光标可达边界仍分别处理。

红测 `/tmp/typebar-line-recenter-red.log` 两项四处失败（0.744 秒）复现漏退休及跳到远行；第一次修复日志 `first-green.log` 留下一项失败，固定 135 点夹具没有随 40 点字体增加到三行高度。只修夹具尺寸、不改容限后 `second-green.log` 两项零失败 0.084 秒。扩大轮 `focused.log`／`focused-runtime.log`／`focused-compiled.log` 保留 Observation 私有嵌套类及 timed 构造名／标签编译错误；`focused-built.log` 随后抓出两桥接层漏传开关，以及旧 overlap／reflow 测试没有区分布局强制调用。修复桥接；overlap 保留旧回调必须取消的断言，另测新的 resize 回调；reflow 首跳夹具显式隔离没有 wrapper／resize center 调用的函数路径，不删结果断言。`raw-gate-red.log` 为测试回调变量误放作用域的编译失败，修正后 `raw-gate-red-runtime.log` 初次绿只是文档高度不能滚动的弱夹具；增加可滚动高度后 `raw-gate-red-scrollable.log` 一项两处真实失败（90／118 而非 0），再修原始开关的定位路径。所有日志保留，不把编译失败或弱夹具算行为红测。

最终 `focused-green.log` 相关 90 项零失败零跳过（29.829 秒），其中 15 新增为 4.063 秒；包括首强制平滑、减少动态、字号／宽度、原始开关、无前缀首跳、长词词框、重开／拆卸、48 源码对照、生产接线，普通与 ASL 的 finite／timed 实际 SwiftUI 会话、裁前缀坐标、退格及完整回放。四图 `/tmp/typebar-line-recenter-focused-images.nlqgID/recenter-{text,asl}-{finite,timed}.png` 逐张检查，组件窗口始终不显示并逐一关闭，零 Typebar 主程序启动。源码单测日志 `/tmp/typebar-line-recenter-source.log` 亦通过。行为优先／源码驱动／最小改动与根因调试约束实施；同会话决策／风险审查重点为强制首跳、桥接开关、旧回调替换、长词边界和原文不变，不是独立人工评审。既有原创手形／颜色／原生间距不改，Swift 6.2.4／SDK 26.2／最低 macOS 14，无新版本敏感 API 或依赖。

首轮完整门禁 `/tmp/typebar-line-recenter-complete-readiness.log` 终态退出 0：原生 3,819 项零失败零跳过（837.516 秒），服务 501 项（11.264 秒）；实际十万词耐久 159.283 秒、53 表面／1,099 唯一人工结构、元数据和未启动应用包资源／签名／原创边界通过。10 文件 `/tmp/typebar-line-recenter-frozen.sha256` 在该轮前中后完全一致；62 日志 `/tmp/typebar-line-recenter-complete-logs.ywIi2g`、149 图 `/tmp/typebar-line-recenter-complete-images.GDLfMp` 保留。该轮尚不含下面的最后长词修复，不能冒充最终代码的完整验收。

只读审查进一步发现：无可退休前缀时，前一个长词的内部行仍被当作居中目标。首轮门禁终态后才补测，`/tmp/typebar-line-recenter-long-prefix-red.log` 两项四处真实失败（1.791 秒），TextKit 实测及自定义几何 × 立即／平滑都移到 180 而非 0；56 组扩展源码对照本身通过。修复为无可移除词时只计跳行并保持原目标，不新建动画。最终相关 `/tmp/typebar-line-recenter-final-focused.log` 91 项零失败零跳过（30.812 秒），其中 16 新增为 4.844 秒；原 90 项／48 组是阶段证据，最终增为 16 项／56 组。四张组件图重新生成后仍需在最终完整轮复查。该反例完成本轮同会话审查闭环，不宣称覆盖任意布局交错。

配置 showAllLines／fontFamily 仍部分覆盖；十万以上全量预览、全部未来词／视口虚拟化、fontFamily 独立订阅例外与所有 wrapper 配置触发、resize 调度／回流交错、浏览器精确尺寸、专业 ASL／真实键盘／IME／设备等未完成。本轮验证字号／窗口宽度／全行开关，不声称所有字体家族与配置生命周期已等价。六部分／42 历史有界分类不升级，两新增人工场景待验收，完整 goal active。

最终完整冻结门禁 `/tmp/typebar-line-recenter-final-readiness.log` 终态退出 0：原生 3,820 项零失败零跳过（816.292 秒），服务 501 项（11.553 秒）；实际十万词耐久 151.922 秒、16 项隔离磁盘冷读 4.677 秒、53 表面、1,099 唯一人工结构、元数据与未启动应用包资源／URL scheme／严格签名／原创边界全部通过。16 项新回归为 4.828 秒，56 组 center／forced source 与原有退休／退格检查通过；四张新组件图已再次逐张检查，仍不代替实机验收。10 文件 `/tmp/typebar-line-recenter-final-frozen.sha256` 门禁前中后完全一致；62 原始日志 `/tmp/typebar-line-recenter-final-logs.kyWfFq`、149 图 `/tmp/typebar-line-recenter-final-images.lvzflO` 完整保留。全量测试无断言失败／跳过；CoreData／AddressBook XPC、隔离只读 SwiftData 513、既有编译／Node 警告保留，不宣称修复。无并行编译／验收或残留测试进程，零 Typebar 主程序启动，没有操作真实账户、Keychain、成绩库或部署。以下是历史阶段。

## ASL 退休前缀渲染物化与稳定字形 ID 增量

2026-10-09，固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整 `lineJump`／`removeTestElements` 在跳行动画完成后物理移除旧 DOM 词格，但不删除原始词目录或输入；完整 before-delete／hard-recovery 另根据词元素是否存在限制回退。既有 QA 探针重新执行 12 序列／60 行转移、32 before-delete 与八 hard-recovery，全部通过；DOM 尺寸、动画完成和输入状态仍为自有适配，不冒充浏览器。未读取／提取任何字体或官方产品资产。

红测两项一处失败（1.493 秒）：给 ASLWordPlan 四个保留 ID，仍为两万个历史格分配归属。真实 never-visible 组件已有正确三格画面，却仍在字形内容与 SwiftUI ForEach 前遍历／物化全部历史位置；基线两万退休／三格保留 mounted 0.489033 秒。新 ASLPromptCellPlan 先筛共用渲染的保留 ID，再构建 attributed 格与 SwiftUI 子节点；ForEach 使用 canonical Identifiable，而非会随前缀改变的数组位置。词归属只为实际保留 ID 分配，并夹住可见目标范围；所有框、word union 和独立光标都使用保留格数据。隐藏墨迹不是缺失；显式空渲染不走 legacy 恢复，nil 渲染仍保留既有 fallback；Zen 占位和 Unicode／hint 不变。没有新增未来词数量上限或提前退休，没有修改输入、计分、存储、回放、服务或 Timer。

首绿两项零失败 0.164 秒，mounted 0.071479 秒；最终相关 154 项零失败零跳过 19.771 秒，mounted 0.058089 秒。时间只属同机夹具观测，包含系统／字体／编译缓存影响，不作跨机器倍数或帧率保证。九项新增覆盖：两万退休仅三格物化、真实 extras 重排／归属和 Unicode hint、隐藏与缺失、空与 nil／ID fallback、Zen 占位、五千未来格无新截断、生产接线、归属表边界、实际二次裁前缀保持同一 caret owner。失败与通过日志保留 `/tmp/typebar-asl-retained-render-{red,first-green,focused,source}.log`，两张新组件图 `/tmp/typebar-asl-retained-render-focused-images.dQAGfz/asl-retained-{long-prefix,next-prefix}.png` 已逐张检查。组件窗口从不显示并逐一关闭，零主程序启动。

Swift 6.2.4／SDK 26.2／最低 macOS 14；安装 SDK 的 ForEach Identifiable initializer 明确支持 macOS 10.15，不引入仅新版系统 API。行为优先、源码驱动、最小改动及同会话决策／风险复核限定实现，非独立评审；frontend-design 保持既有原创线描、颜色和原生间距，不改视觉设计。该增量只界定**退休前缀不再物化为字形与列表节点**：仍扫描入参 canonical IDs／词目录，输入引擎及共用渲染快照的全历史扫描、所有未来／show-all 视口虚拟化、长会话真实逐帧性能均未证明有界。严格空格空词、所有混排／回流、专业手形、浏览器精确数值、真实设备／IME／VoiceOver 等差距继续开放；ASL 六部分／42 历史有界分类不升级，完整 goal active。

最终完整冻结门禁 `/tmp/typebar-asl-retained-render-complete-readiness.log` 终态退出 0：原生 3,804 项零失败零跳过（837.183 秒），服务 501 项零失败零跳过（11.971 秒）；实际十万词耐久 155.101 秒、16 项隔离磁盘迁移冷读 4.842 秒、53 表面、1,097 唯一人工结构、固定元数据／原创边界与未启动应用包资源／URL scheme／严格签名检查全部通过。九新增测试为 0.237 秒，当前完整轮两万退休／三格 mounted 观测为 0.057617 秒，仍不作为跨机器性能承诺。八文件清单 `/tmp/typebar-asl-retained-render-frozen.sha256` 门禁前中后完全一致；62 份原始日志保留 `/tmp/typebar-asl-retained-render-complete-logs.dJOMY0`，145 张组件图保留 `/tmp/typebar-asl-retained-render-complete-images.u29hYh`，两张新图已再次逐张检查。测试日志全文无失败／跳过；CoreData／AddressBook XPC、只读 SwiftData 513 及既有编译／Node 警告原样保留，不宣称修复。零 Typebar 主程序启动，无残留测试／编译进程，没有操作真实账户／成绩库或部署。下面是历史阶段证据。

## Zen 空活动词占位与 ASL 实测词框增量

2026-10-09，固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整 `appendEmptyWordElement`／`updateWordLetters` 都为 Zen 空活动词生成不可见 `_` 格；`index.scss` 明确 opacity 0／visibility hidden，不是 display none。ASL CSS 仅换字体。本轮 QA 执行完整 append 函数及完整建词／更新与真实 Words／Strings，共 44 组自有输入，不再跳过 Zen 空输入 sentinel。DOM、hint、RAF 与 CSS 数值仍是适配边界，不声称浏览器字体／尺寸或真实输入链路已执行。

真实 `TypingSession` mounted 红测一项两处失败（0.926 秒），证明初始与 Return 后活动空词无词框；首绿 0.248 秒。新增呈现-only 占位 ID，由共用渲染生成隐藏下划线并交给 ASL 词框／布局，不把它当尾部分隔空格。占位文字不写入接受输入、结果、回放或存储；完成后消失，组合 replacement 优先，裁掉的 ID 不恢复。普通分隔空格不变；无新 timer 或依赖。当前／pace 都使用实际框，空活动词连续滚动退休后仍保留原文。Swift 6.2.4、macOS 14；本轮没有引入新的版本敏感 API，既有安装 SDK 的 AttributedString／SwiftUI 布局路径不变。

净增八项：五个会话／共用策略／缺失格测试、两个实际 Zen 滚动会话和一个隐藏占位／双光标／字号组件测试。最初扩大测试因新测试错误引用 `CompletedTestResult.typed` 编译失败，核对实际模型后改查真实会话输入与已保存 replayEvents；第二轮 134 项只有一处命令遗漏固定 Anime 归档环境的源码对照失败，补齐环境不改产品／断言。134 项转绿 11.685 秒，最终 135 项零失败零跳过 11.815 秒。日志完整保留在 `/tmp/typebar-zen-placeholder-{red,first-green,focused,focused-verified,focused-complete,focused-final,source}.log`；不将失败轮计作最终通过。

三张新图 `/tmp/typebar-zen-placeholder-focused-render.60etUT/asl-zen-{empty-after-return,empty-retired-markers,invisible-placeholder}.png` 已逐张检查：实际 Return 后空活动行、退休后独立框、全白隐藏占位。组件窗口从不显示并逐一关闭；零 Typebar 主程序启动。frontend-design 限定为延续原创线描／原生间距，行为优先、源码驱动、最小改动、根因调试及同会话决策／风险复核影响实现，非独立评审。剩余严格空格／已提交空字段、全部组合与回流交错、长提示可见有界渲染、专业手形、真实设备／IME／VoiceOver、浏览器精确字体／间距均开放。六部分／42 历史有界分类不升级，goal active。

最终完整冻结门禁 `/tmp/typebar-zen-placeholder-complete-readiness.log` 终态退出 0：原生 3,795 项零失败零跳过（827.882 秒），服务 501 项零失败零跳过（11.350 秒）；实际十万词耐久 155.767 秒、16 项隔离磁盘迁移冷读 4.794 秒、53 表面、1,096 唯一人工结构、固定元数据／原创边界及未启动应用包资源／URL scheme／严格签名检查全部通过。14 控制布局为 1.096 秒、19 滚动为 4.971 秒、五个占位策略为 0.003 秒。十文件清单 `/tmp/typebar-zen-placeholder-frozen.sha256` 门禁前中后完全一致；62 份原始日志保留 `/tmp/typebar-zen-placeholder-complete-logs.vTFcok`，143 张组件图保留 `/tmp/typebar-zen-placeholder-complete-render.KYgmSp`，三张新图已再次逐张检查。测试日志全文无失败／跳过；CoreData／AddressBook XPC、只读 SwiftData 513 和已有编译／Node 实验警告原样保留，不宣称修复。没有操作真实库／账户／登录／部署，零主程序启动。下面是历史阶段证据。

## ASL 控制字符格、连续空行与空词退休增量

2026-10-09，固定只读参考仍 `91bd24bb8513785c7364cbea29296ff7adafac41`。核对完整 `buildWordHTML`／`updateWordLetters`、`Words`／`Strings` 和 `test.scss`：Return 是前词末尾的真实 `nlChar`，其后才有换行 helpers；前导／连续 Return 也有控制格，不是零尺寸节点。误输或额外 Return 只是当前格的错误标记，不拥有目标换行。ASL CSS 仅替换字体；没有读取、提取或复用 Gallaudet、FontAwesome、图片或官方产品代码／资产。Swift 6.2.4、SDK 26.2、macOS 14；AttributedString 的切片、removeSubrange 和属性容器依安装 SDK 的公开声明核验。

ASL 现用已有 `PromptControlCharacterPresentation` 的原生 →／↵ 与最终共用属性。`ASLPromptGlyphContent.ownsLineBreak` 由真实目标与 extra 状态确定，不由显示替换推断；先拆 hint 再只移除主格末尾那一个结构换行，保留错误替换、Unicode、颜色／下划线和 hint。Zen 的隐藏原始 Tab／Return 转为带原属性的单个控制 marker，仍无墨迹但不采用 Text 的 tab stop 或额外内部文本行。缺失／退休格没有文字则不造 placeholder。Layout 将 Return 的实际尺寸纳入词宽／内部折行，在词末才强制换行；leading／连续 Return 因而保留完整行高，实际词框也包含控制格，空词能滚动／退休。没有改原始输入、计分、回放或存储格式，无新增 Timer，普通／Choo／Tape 路径不变。

新增 QA 探针 `check-source-asl-controls.mjs` 执行完整固定建词／更新函数及真实 Words／Strings 模块，共 36 组 ordinary／Zen、off／replace、future／correct／wrong／extra 的自有输入；仅 DOM、hint、RAF 和 CSS 尺寸是适配边界。原生横向逐格对照 marker／extra／隐藏／换行归属；Zen 空输入 invisible sentinel 不冒充控制格对照。CSS 规则静态核对，**不是浏览器布局、字体宽度、真实 RAF 或 hints 布局证明**。既有 special-caret 探针默认零宽夹具仍在；允许传入真实正宽 Return，原生 mounted 断言已从旧的零宽借前格改为必须拥有自身正宽格，不删除零宽回退测试。

测试先行：`/tmp/typebar-asl-control-layout-red.log` 三项 14 处预期失败，复现 Return 零尺寸／额外输入误换行／结构换行和原始 Tab 未转换。`first-green.log` 三项零失败（0.229 秒）；`source-first.log` 36 组完整源码通过。`expanded.log` 63 项只有两处旧 fixture 渲染字符串失败：同款共用控制策略加入 ↵，旧期望仍不含 marker；修正完整显示期望为带 marker 字符串，保留 typed／prompt 原文与纠正边界断言，未改产品或放宽容限。最终 `focused-verified.log` 84 项零失败零跳过（7.285 秒）：13 新控制布局、17 滚动、21 独立光标、12 词布局、21 共用控制策略；净增 14 项。全部日志共同前缀 `/tmp/typebar-asl-control-layout-`，失败不删除。

六张新组件图在 `/tmp/typebar-asl-control-layout-focused-render.ckpXSk` 已逐张检查：leading／连续 Return、extra Return、错误替换、全隐藏 Zen、独立主 pace、空词退休。所有测试窗口从不显示且逐一关闭，零 Typebar 主程序启动。设计遵循既有原创线描／主题／原生间距；不复制原版 helper DOM 或 CSS margin。保留浏览器数值／精确字体与间距、空格-only 字段、复杂控制／hint 混排、全部回流交错、长提示可见有界渲染、专业 ASL 与真实设备等剩余验收；六部分／42 历史有界分类不升级，goal active。

最终完整冻结门禁 `/tmp/typebar-asl-control-layout-complete-readiness.log` 终态退出 0：原生 3,787 项零失败零跳过（835.484 秒），服务 501 项零失败零跳过（12.541 秒）；实际十万词耐久 158.077 秒、16 项隔离磁盘冷读 5.246 秒、53 表面、1,095 唯一人工结构与元数据无漂移通过。未启动应用包的资源／URL scheme／严格签名／原创边界通过；13 控制布局为 0.913 秒、17 滚动为 4.351 秒。11 文件清单 `/tmp/typebar-asl-control-layout-frozen.sha256` 门禁前后完全一致；62 份分阶段日志保存于 `/tmp/typebar-asl-control-layout-complete-logs.LY2ldF`，140 张组件图于 `/tmp/typebar-asl-control-layout-complete-render.hbQrbr`，其中六张新图已再次逐张复查。CoreData／XPC 系统诊断、Node 实验性警告和既有编译警告保留，未声称修复；冻结输入未改动，没有并行验收任务或 Typebar 主程序启动。

同会话决策／风险审查的主要反例为隐藏 Return 变零尺寸、替换字母丢掉目标行界、extra Return 虚造行、pruned 格恢复答案、控制格增高而视口仍用手形常数，以及 leading 空词无法退休；对应真实 mounted 测试、源码对照和数据保持断言已检验。这不是独立人工评审，组件图不升级人工状态。

## ASL 词级换行与完整词框滚动增量

2026-10-09，固定只读源码仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。核对完整 `buildWordHTML`、`updateWordLetters` 与 `test.scss`：原版以 `.word` 为 flex item，能放进新行的词不拆进上一行余隙，过长词在词容器内折行，后词不能填其最后一条内部行。[CSS Flexbox 收集行算法](https://www.w3.org/TR/css-flexbox-1/#algo-line-break) 支持这个词容器边界；ASL CSS 仅替换字体，不另定义逐字流。SwiftUI Layout／LayoutValueKey／place 依安装的 SDK 26.2 公开接口实现，目标仍 macOS 14；没有复制原版产品代码、字体或其他资产。

新增原创 `ASLPromptWordPlan`／`ASLPromptFlowGeometry`／`ASLPromptFlowLayout`：外层按词分配完整宽度，内层格级折行，尾随原生间隔不制造空内行。生产词归属直接读取会话 canonical target ranges／extras，无空格词界保持独立，错误替换文字不重分组；没有真实 separator 的末尾索引不得覆盖 extra ID。退休或隐藏后缺失的格不重建，实际词框由仍存在的手形／fallback 格联合；滚动读取完整词框行高，光标及视口仍读实际内部格行，不用拉丁 TextKit 猜手形。普通／Choo／Tape、计分、回放与磁盘格式不变，包装器无新增 Timer。

本增量保留既有原生手形、配色和 12 点行距；词间距使用原生 separator cell，不复制 CSS margins 或字体宽度，不宣称逐像素等价。`about:blank` 中自有浏览器夹具的 `data:` 导航被策略阻止，已关闭，未用 localhost／其他浏览器绕过；浏览器实际排版数值、连续空行／Return helpers、全部控制混排、精确 hint／所有回流交错、长提示可见有界渲染、专业 ASL 与真实设备仍未验。ASL 六部分／42 历史有界分类不升级，完整 goal active。

行为日志共同前缀 `/tmp/typebar-asl-word-wrap-`：`red.log` 两项三处失败复现整词被拆及后词进入长词末行；`first.log` 38 项零失败但两项缺参考跳过，只是初测；`word-metrics.log` 38 项零失败零跳过。`boundaries-red.log` 12 项三处失败，定位真实 extra ID 被末词结束位置覆盖和两条末行行距硬编码；`focused-green.log` 保留 Swift 初始化闭包先捕获未初始化属性的编译错误，改为局部测量结果后 `focused-verified.log` 49 项零失败零跳过（6.254 秒）。`proposal-red.log` 一项两处失败复现无限／负宽的无效 size，已规范化提案宽度；最终 focused／冻结完整门禁另记。新增 12 项词布局测试加一项超长词实际退休，净增 13 项；现有滚动 fixture 接入生产同款词元数据，未削弱断言。离屏窗口始终不显示、逐一关闭，本轮零 Typebar 主程序启动。

最终 `final-focused.log` 49 项零失败零跳过（5.927 秒），含 12 项新词布局／16 项滚动／21 项光标；三张新组件图在 `/tmp/typebar-asl-word-wrap-focused-render.HHZxiy` 逐张复查，未显示窗口。53 表面、1,093 唯一人工场景结构和配置／语言元数据无漂移审计通过，人工状态不升级。

最终冻结完整门禁 `/tmp/typebar-asl-word-wrap-complete-readiness.log` 终态退出 0：原生 3,773 项零失败零跳过（832.061 秒），服务 501 项零失败零跳过（12.708 秒）；实际十万词耐久 157.339 秒，16 项隔离磁盘冷读 5.143 秒，53 表面、1,093 唯一人工结构、元数据无漂移及未启动应用包／URL scheme／严格签名／原创边界全部通过。新增词布局 12 项为 0.277 秒、滚动 16 项为 3.996 秒；源码探针不变，未伪造浏览器布局证据。八文件冻结清单 `/tmp/typebar-asl-word-wrap-frozen.sha256` 在门禁前后完全一致；61 份分阶段日志保存于 `/tmp/typebar-asl-word-wrap-complete-logs.uT2eLl`，134 张组件图于 `/tmp/typebar-asl-word-wrap-complete-render.GYIprY`，其中三张新图已再次逐张复查。CoreData／XPC 系统诊断、Node 实验性警告和既有编译警告完整保留，未声称修复；全过程无文件变动或并发编译／测试，零 Typebar 主程序启动。

同会话决策／风险审查重点为 extra ID 与目标结束碰撞、词内外行分离、退休后 anchor 缺失、主 pace 随 resize 更新及无效提案尺寸；红测分别检验因果而非只静态搜名字。这不是独立人工评审，也不以离屏图冒充真实输入／设备验收。两项新增人工场景仍待验收。

## ASL 实测整行滚动与旧词退休增量

2026-10-09，固定只读参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。核对完整 test-ui.ts 的 updateActiveElement／lineJump／removeTestElements、ASL CSS、test.scss 的 flex 词分组及 dom.ts 的 getOffsetTop；没有提取 Gallaudet 或复用产品代码／资产。AppKit 滚动入口以安装的 SDK 26.2 公开头文件核验，目标仍 macOS 14。原版 getOffsetTop 直接返回 native.offsetTop；[CSSOM View 的 HTMLElement 定义](https://drafts.csswg.org/cssom-view/#dom-htmlelement-offsettop) 为 long，不能在自有 DOM 夹具中当成未取整 DOMRect。

ASL 现在把实际 SwiftUI anchor 行框接入已有 PromptAutoScrollView，而不是另写滚动／退休状态机或用拉丁字体测量。ASLPromptLineGeometry 缓存实际行顶、混排最大高度／行距及 canonical ID，几何缺失不走普通 TextKit 回退；普通提示的默认测量路径不变。生产两分支共用上下文工厂，含 attempt、活动词、保留前缀、减少动态、FPS、回流策略和光标运动协调器。实际三行／Zen 两行视口使用测量高度并保留底部空行，短末尾与单个跨行长词的光标可达；关闭两个光标仍保留滚动 owner。第一次跳行不退休，后续平滑完成才通知；前缀裁剪重置滚动坐标而不删原始输入、回放或放开已退休词的退格边界。包装器无新增 Timer，使用现有子控制器；修复保留滚动层时关闭光标仅停调度却留下旧图像的问题。

行为证据：`/tmp/typebar-asl-scroll-red.log` 两项两处预期失败，复现无滚动上下文与固定 184 点视口。`first.log` 初步 49 项零失败但三项缺参考跳过，不算最终验证；`expanded.log` 为夹具 Observation 私有类型与参数顺序编译错误，修正后 `expanded-runtime.log` 82 项零失败零跳过（21.132 秒）。`marker-off-red.log` 一项一处失败真正复现旧 marker 残留，随后修生产隐藏状态。`source-marker-verified.log` 84 项八处失败来自将第一行 43 点直接乘成全部行（实际顶为 43／86／128／171）；夹具改用实测累计平均步长 42.75，保持 0.5 点容限。`final-focused.log` 86 项唯一失败来自自有 getOffsetTop 返回小数，使原版 floor 检查误删前一词；夹具显式取整后通过，未改官方函数或放宽断言。以上日志共同前缀 `/tmp/typebar-asl-scroll-`，全部保留。

最终聚焦 `/tmp/typebar-asl-scroll-final-verified.log` 86 项零失败零跳过（21.792 秒），含新增 15 项：真实 SwiftUI 退休／重排、隐藏光标仍滚动、平滑／减少动态、短末尾、两行大字号、长单词／混排、全行模式不退休、缺失框拒绝回退、重启／拆卸取消、重叠只完成最新边界与完整固定源码对照。QA-only check-source-line-scroll.mjs 可额外接受实测平均行距，默认六序列不变；ASL 调用执行八序列／40 次源转换，其中两序列／十次源转换使用 ASL 实测值，原生按前四个实际行迁移对照。DOM／行距取整／动画立即 Promise 是明确自有边界，不证明浏览器排版、专业字宽或真实帧。五张新组件图在 `/tmp/typebar-asl-scroll-render.MD9SnK`（retired-no-markers／short-final-markers／two-large-rows／long-token／mixed-fallback），已逐张检查；窗口从不显示，串行关闭，零 Typebar 主程序启动。

首轮冻结完整门禁 `/tmp/typebar-asl-scroll-complete-readiness.log` 退出 1：原生 3,760 项唯一失败（813.446 秒）为既有 PromptPaceSchedulingTests 的首次目标不绘制夹具；新增 ASL 15 项 3.628 秒通过，十万词 152.838 秒、磁盘冷读 16 项 6.064 秒通过，没有跳过。59 份完整日志人工保存在 `/tmp/typebar-asl-scroll-complete-logs.9BBQaY`（失败退出未自动归档，原临时目录仍保留），不丢原失败；八冻结哈希一致，服务／打包尚未执行。该夹具默认开启 15 FPS 绘制，却用 60ms RunLoop 等待充当无绘制屏障，实际耗时 112ms 已跨 66.7ms。`/tmp/typebar-asl-scroll-pace-race-red.log` 将等待延至 120ms 单项稳定复现。只在该测试设置已有 automaticallyPresents=false，仍保留 pace deadline Timer，并延长等待及追加显式 present 必须绘制断言；未修改产品计时器或去掉原断言。`/tmp/typebar-asl-scroll-pace-isolation-verified.log` 相关 102 项零失败零跳过（22.546 秒）。随后九文件重新冻结并重跑完整门禁，结果另记。

最终重新冻结完整门禁 `/tmp/typebar-asl-scroll-final-complete-readiness.log` 退出 0：原生 3,760 项零失败零跳过（821.519 秒），服务 501 项零失败零跳过（13.559 秒）；新增 ASL 15 项实际 3.661 秒、十万词耐久 157.207 秒、16 项隔离磁盘冷读 5.774 秒通过。53 表面／生产文件／测试符号、1,091 人工结构、未启动应用包／scheme／严格签名／原创边界全部通过。九个冻结实现／测试／探针／矩阵哈希 `/tmp/typebar-asl-scroll-final-frozen.sha256` 前后一致；运行期间未编辑，终态后仅补结果与边界文档。61 份完整日志在 `/tmp/typebar-asl-scroll-final-complete-logs.iYoePg`（使用既有锁定 Anime archive，较前次少一个准备下载日志），131 张组件图在 `/tmp/typebar-asl-scroll-final-complete-render.IpyikS`；五张新 ASL 滚动图逐张复查。既有 CoreData／AddressBook XPC、隔离只读 SwiftData 513、Node 实验性及编译警告保留，不声称修复。首轮失败和确定性红测不被覆盖；零 Typebar 主程序启动。

同会话有界风险复核以“特殊布局只提供测量、状态与计时器仍共享”为合同，反例覆盖缺失框、同轮重启、重叠回调、关闭 marker 及短文档坐标重置；不是独立审查。设计技能保持既有原创手形、颜色和原生布局，仅接通视口测量与滚动。不能用自动化或组件图代替真实设备验收。

ASL 仍部分覆盖：当前 PromptFlowLayout 逐格换行，尚未复现原版 flex 按词分组／空白边界；空行／控制换行、精确 hint／完整混排／主题动效、全部 Slow Timer／Zen 回流交错、任意共享 coordinator 分支切换、长提示有界可见渲染、专业手形和真实键盘／IME／VoiceOver／显示器仍待验。实测滚动／退休是有界增量，不是所有布局等价。没有存储／协议迁移，没有主动操作真实库／Keychain／账户或部署；53 表面、六部分／42 历史有界分类不升级，新增两项人工仍待验收，goal active。下方为历史阶段。

## ASL 共用文字状态与实际布局独立光标增量

2026-10-09，固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`、只读清洁。只读核对完整 ASL CSS、Caret 目标解析与相关位置／闪烁通道，以及 test.scss 的默认／flipped／colorful／highlight-off／词高亮／blind／typed effects：ASL 只替换显示字体，不能另造一套当前字符颜色、错误背景或计分规则。没有打开、复制、提取或描摹 Gallaudet 字体；SwiftUI Anchor／GeometryProxy／anchorPreference／overlayPreferenceValue 使用已安装 SDK 26.2 的公开接口，以 macOS 14 目标实际编译。

ASLPracticePrompt 现在读取共用 renderedPrompt 的最终属性、canonical ID 和选定原生字体，而不是固定系统 primary／secondary／red 或 current accent 背景。ASLPromptGlyphContent 按 Character 范围切分每格，保留目标／错误替换、组合文字、隐藏／淡化／点替换、前景／背景与错误下划线；字母主体与字母 typo hint 仍绘原创手形，多字组合、非 ASCII／非换行控制符及点使用原生 Text。目标换行仍沿用已有零宽换行格，Return 图示及该格错字显示不在本轮完成范围。显示哪个字符由共用 typo 设置决定：关闭替换时保留目标，替换时显示实际输入，并非上一轮无条件显示 typedCharacter；原始输入与成绩不改。常规角色规划本身的已有局限不据此宣称修复，hint 精确基线／字宽与完整组合仍待验。

每格通过真实 SwiftUI bounds anchor 提供框，专用无计时器 ASLPromptCaretContainer 将它们映射到已有 PromptCaretNativeView 的主／pace 独立通道；不把 canonical ID 当 TextKit offset，也不用普通拉丁字体估算手形。实际布局、换行、缩放、文字替换或 ID 变化递增几何版本；隐藏只去墨迹不删框，实际零宽格可回找，缺失／已裁格拒绝假借前格或恢复旧目标。共用渲染未包含的格连换行也不参与布局，firstGlyphID 取首个实际框。移除旧 current／error／extra 假背景，配置继续使用已有专注／输入／窗口／完成／减少动态 provider 与有界呈现／pace timer，包装器没有新增循环或全局监听。真实 SwiftUI 移除／恢复覆盖层只恢复一个新 owner，旧 child 即使被测试持有也不再呈现。

范围边界一次建立 Character 索引并按 offset 排序，不为每格重扫整个提示；一万格纯模型切片实际约 0.185 秒，不是十万手形窗口或长期性能验收。设计技能维持现有原生线描、字号和布局，仅把手形颜色与光标职责分离，不重设计页面。同会话有界决策／风险／代码复核（非独立）重点反证实际坐标、旧目标泄露、缺失框、共同 coordinator 与资源退休；未修改 SwiftData、设置／归档格式、输入或账户协议。

先行 `/tmp/typebar-asl-caret-red.log` 两项四处预期失败（1.260 秒）证明假 current 墨迹／背景与缺失生产接线；接线检查仅静态证据，后续真实组件另证。`first-focused.log` 18 项通过（2.730 秒）。扩大回归 `expanded-focused.log` 保留三处夹具失败：真实 anchor 与独立 NSHostingView fittingSize 都是 29×31，而非未对齐 28.56；AppKit 自动释放池排空后容器确实释放。`geometry-retirement-red.log` 四项三处失败还真正复现了旧目标回退和缺失框借位，随后修生产边界。`source-render-focused.log` 74 项唯一失败为高度 31.000000000000007 与 31 的浮点精确比较；改成分量 1e-9 精度，不修改实际几何。

`source-render-verified.log` 79 项两处失败、`fixture-diagnostics.log` 两项两处失败保留：原点对齐 -0.1 不能冒充插入空行，用同一 host 的仅保留格布局逐框对照；夹具换了 attempt 后未呈现导致 nil，改为保持原 attempt 并显式呈现。细线强红仅 28 像素，抗锯齿红 243、红通道质量 86.428；像素守卫改成同时要求实线、抗锯齿与超过单条下划线的颜色质量，不把纯红阈值当所有线条。`final-verified.log` 79 项零失败零跳过（4.988 秒），最终 `/tmp/typebar-asl-caret-lifecycle-final-verified.log` 80 项零失败零跳过（5.137 秒），含新增 21 项与既有手形／Choo／普通听写／主光标回归。日志共同前缀 `/tmp/typebar-asl-caret-`，不删早期失败或以跳过换绿灯。

QA-only 既有 check-source-special-caret.mjs 可额外接受三个实际 ASL anchor 框；完整执行锁定 Caret 模块的 16 组四样式／零宽／字前字后解析，对照原生独立 marker 的横向位置／全宽。默认探针行为与原夹具不变；word origin、DOM、方向、space advance 为明确自有边界，不是浏览器 CSS、字体基线、连写／RTL 或完整控制器动画等价。六张新组件图在 `/tmp/typebar-asl-caret-final-render.EQpJhU`（on／off／wrapped／shared-theme／shared-hidden／hint-underline）；前五张此前同实现图与最终 hint 图已逐张检查，完整门禁后再复查。真实 mounted SwiftUI 验证非连续 ID、换行／缩放／字体、主闪烁而 pace 保留、主关闭而 pace 可见、隐藏仅留蓝色光标无原手形彩墨、缺失格与拆卸恢复；测试窗口从不显示或激活，串行关闭，零 Typebar 主程序启动。完整冻结门禁结果另记，不借上一轮全绿证明此轮。

最终冻结完整门禁 `/tmp/typebar-asl-caret-complete-readiness.log` 退出 0：原生 3,745 项零失败零跳过（816.252 秒），服务 501 项零失败零跳过（11.517 秒）；新增 21 项在全量中实际通过（1.824 秒）。十万词耐久实际执行 161.751 秒，16 项隔离磁盘冷读 5.471 秒；固定参考／元数据、53 表面／生产文件／测试符号、1,089 人工清单结构及未启动应用包／scheme／严格签名／原创边界全部通过。八个冻结实现／测试／探针／矩阵哈希 `/tmp/typebar-asl-caret-frozen.sha256` 前后一致，门禁运行期间未编辑文件，终态后仅补结果和范围说明。62 份完整日志在 `/tmp/typebar-asl-caret-complete-logs.MvfozS`，126 张组件图在 `/tmp/typebar-asl-caret-complete-render.CyYP9g`；本轮六张 ASL 图已逐张复查。已有 CoreData／AddressBook XPC、隔离只读 SwiftData 513、Node 实验性诊断与早期夹具失败保留，不声称修复；不删断言、不跳过或重复启动门禁换绿灯。

ASL 仍部分覆盖：专业手形核验、自动整行滚动／旧词退休、长提示有界可见渲染、精确 hint／混排／控制换行布局、全部主题动效／typed fade 时序、任意共享 coordinator 分支切换、真实键盘／IME／VoiceOver／显示器尚未完成；未声称字体轮廓／字宽或连贯动作等价。53 表面分类不升级，三个新增人工项待验收，无主动访问真实库／Keychain／账户或部署，整体 goal active。下方为历史阶段。

## ASL 手形语义与原创矢量增量

固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`，只读清洁。完整读取 `frontend/static/funbox/asl.css` 与 Funbox 元数据：它只替换 wordsWrapper 的显示字体，不变换目标或计分，保留 noJoiningScript 准入。没有打开、提取、复制或描摹 Gallaudet 字体轮廓。语义核验使用 [HandSpeak 字母表](https://www.handspeak.com/topic/408/)、[A](https://www.handspeak.com/word/2460/)、[F](https://www.handspeak.com/word/2465/)、[K](https://www.handspeak.com/word/2470/)、[M](https://www.handspeak.com/word/2472/)、[N](https://www.handspeak.com/word/2473/)、[T](https://www.handspeak.com/word/2479/) 与 [Lifeprint 手形备注](https://www.lifeprint.com/asl101/topics/signingnotes.htm)。这些来源说明手指姿态、拇指位置、接触和朝向不能被同一个伸直位掩码替代；仅观察教学参考，没有下载媒体或把其图片、路径、文字纳入产品。原生坐标与绘图逻辑独立构建，不以照片采样／描摹生成。

原创 ASLHandshape 明确四指 folded／extended／curved／hooked、拇指 alongside／across／underFingers／contact／parallel、joined／spread／crossed／angled 与四种方向，并独立保留 J／Z motion cue。A／S 区别在拇指，M／N／T 分别穿过三／二／一指；D 伸食指、F 伸其余三指，弯指与拇指接触不同；C 留开口、O 指尖接拇指，E 指尖弯向横放拇指；G／Q、H／U、K／P 维持相关配置但方向不同。只接受单个 ASCII 字母，大小写同形，ß／连字／重音 grapheme／全角等不因大写展开变成错误 ASL。实际 ASLPracticePrompt 对不支持的错误输入显示所输入文字，而非空 mask 假拳或原目标。

ASLHandshapeDrawing 使用独立标准化 palm、指节／手指曲线、拇指与方向变换；没有暗藏拉丁字母、编号或字符专属装饰以制造不同图像。原生 Canvas 先绘远层，穿过手指的拇指位于后方；公开 GraphicsContext `.copy` 替换覆盖区域连同 alpha，再描边，避免透明线穿透，且不假造窗口／主题底色。握拳指节改为紧凑轮廓，E 不使用自交管线；J／Z 保留静态方向轨迹，不增加 Timer 或循环。当前字形尺寸、布局、状态颜色和辅助功能提示保留，不借此宣称 ASL 全部主题／高亮／光标或无障碍已等价。设计技能选择安静的原生线描手形，只把辨识度用在实际姿态而非页面重设计。

先行 `/tmp/typebar-asl-handshape-red.log` 一项四处预期失败（0.658 秒）复现 A／D、A／I、M／N、S／T 无法区别；旧 mask 与 cue 不再是生产表示，耐久守卫升级为实际完整绘图比较，而不是给旧 mask 填不同数字。更正上一轮文档：旧 C 的 mask 为 2，并非零；真正零 mask 组为 E／M／N／O／S／T，C／E 那一对未产生红测失败。第一轮 11 项通过（2.117 秒）并不证明视觉正确，实际图发现透明描边穿透和握拳自交；`/tmp/typebar-asl-knuckle-red.log` 一项四处预期失败（1.027 秒）证实轮廓高度 34.673 超过紧凑指节上界 24。修复后 12 项通过（2.093 秒）。扩大夹具先因 SwiftUI 闭包漏写 self、后因配置 helper 需要数组而非 Set 编译失败，分别保留 final-focused.log／score-focused.log，不把编译错误计作产品红测。

最终定向 `/tmp/typebar-asl-handshape-final-verified.log` 83 项零失败零跳过（4.073 秒），含新增 16 项和既有 Choo／Tape／主光标／文字状态回归。26 字母各自实际 Canvas 栅格无标签且不为空、不重复；两张全字母图包含 QA-only 标签用于人工定位，不据标签证明手形区别。28／52 点字母表与错误数字／ß、其对应纯 Text 期望、hidden／empty 共八图已逐张检查，26 个单字图也分轮检查；34 张 ASL 图最终重跑在 `/tmp/typebar-asl-handshape-verified-render.tZeie9`，此前同实现图在 `/tmp/typebar-asl-handshape-final-focused-render.8T4MPc`。实际未显示窗口的错误输入图与纯 Text 全 RGBA 像素相同，hidden 与空白相同。输入／成绩／回放不变性用相同时间、错误／删除／完成输入及实际绘图调用直接对照，速度及精度断言亦通过，不回算历史或修改 SwiftData／账户协议。完整冻结结果另记，不能借上轮门禁证明此轮。

最终冻结完整门禁 `/tmp/typebar-asl-handshape-complete-readiness.log` 退出 0：原生 3,724 项零失败零跳过（816.262 秒），服务 501 项零失败零跳过（11.957 秒）；新增 ASL 16 项在全量中实际通过（2.807 秒）。实际十万词耐久 157.683 秒，16 项隔离磁盘冷读 5.550 秒；固定参考／元数据、53 表面／生产文件／测试符号、1,086 人工清单结构及未启动应用包／scheme／严格签名／原创边界通过。七个冻结实现／测试／矩阵哈希 `/tmp/typebar-asl-handshape-frozen.sha256` 前后一致，门禁运行期间未编辑文件，终态后只补结果文档及历史误记更正。62 份日志保留在 `/tmp/typebar-asl-handshape-complete-logs.nNefLR`，120 张组件图在 `/tmp/typebar-asl-handshape-complete-render.wUMBZr`，含本轮 34 张 ASL 图；最终两张字母表和错误数字／ß／期望／hidden／empty 八图已再次逐张复查。已有 CoreData／AddressBook XPC、隔离只读 SwiftData 513 和 Node 实验性诊断保留，不声称修复；不覆盖早期失败日志、不删断言或跳过换绿灯。

同会话有界决策／风险复核（非独立）拒绝“26 图不同即可验收”的假设，检查接触／方向、ASCII 大写展开、错误输入回退、遮挡与无调度新增。手形可辨识和语义夹具不等于熟练 ASL 使用者认可所有简化图，也不复现字体轮廓／字宽或连贯动作。专业核验、独立主／节奏光标、主题／完整错误高亮、混排布局、真实 SwiftUI 生命周期、键盘／VoiceOver 仍开放。ASL 继续部分覆盖；历史 FUN-17 的 QA37 只证明 J／Z cue 和键盘计分，当前完整手形验收降回待验收。53 表面分类和整体 goal 不升级，零 Typebar 主程序启动，无主动访问真实库／Keychain／账户或部署。下方为历史阶段。

## Tape 单行 LTR 原生文字与独立横向通道增量

固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`、只读清洁。完整读取 [Caret 类](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/elements/caret.ts)、实际 getNlCharWidth／scrollTape 函数与相关初始化／更新调用，以及完整 RAF 模块。起始文字应在 wrapper × tapeMargin 处，不能将有符号 offset 截为零；letter 主光标固定在该边距，word 主光标保留词内偏移。原版主光标不接受 Tape margin，pace 则有独立 marginLeft、ready 折叠和累计修正；文字卷带名义时长 125 ms、inOut(1.25)，与位置及纵向通道分别处理。

原创 TapePromptNativeView 使用单一原生文字 storage／layout manager 绘制、测量与字形映射，不再以 SwiftUI Text 的字符颜色／背景假充主光标。主光标读取独立锁定框；pace 读取未卷动的实际字形框，coordinator 合成已呈现 words margin 与自身横向 margin。新增水平 channel 与纵向状态共存，完成的横向 margin 仅下次 goTo 折入 position 并累计 correction；字宽删除修正原语有直接测试，但场景前缀删除尚未接入。父组件拥有唯一呈现 Timer，关闭子光标重复呈现 Timer，仍保留独立 pace 截止计时器；两光标关闭且文字动效完成时停止呈现，拆卸／弱闭包退休。配置请求不推进帧，重复未变更新不重启动画；尝试／几何配置重锚，减少动态直接定位并保持主光标固显。原版任意异步队列／配置交错不据此认定等价。

实际显示顺序与 logical word ranges 提供 Character offset，包含 extras 的归属，不由扁平字符串空格猜词。零宽字形只在所属词内回找；目标在词首时不借用前词空格。实际测量 advance 变化也触发重锚，不只比较逻辑索引。颜色桥接使用当前 SDK 的公开 AppKit／SwiftUI API：Foundation 保留 SwiftUI.* 属性，原生 glyph drawer 需要显式 NSColor／单线 underline／baseline／kern；错误下划线保留原生颜色元数据。没有读取私有 Text.LineStyle 字段。字符／提示字体准备沿用既有 helper；Unicode UTF-16 run 范围、背景、隐藏文字及错误下划线分别测试，未修改成绩、回放、归档、SwiftData 或账户协议。设计技能维持已有字体、配色与布局，只将文字和光标真正分层。

QA-only `check-source-tape-presentation.mjs` 完整执行实际 getNlCharWidth／scrollTape、Caret 类和 RAF 模块，使用锁定 Anime.js 4.2.2 完整 bundle（实际 lockfile integrity 校验），32 组逐事件夹具涵盖 letter／word、四样式、立即／平滑、重叠输入、完成后折叠。DOM／方向／字体尺寸／时钟为自有单行 LTR 边界；主张为实际函数及原生 coordinator 横向通道对照，不是浏览器 CSS、完整原版控制器或实际 NSView 的逐帧同一证明。名义曲线和既有 8 ms autoplay lead 分开建模。产品不携带参考源码、JS 运行时或字体／资产；探针纳入完整门禁。

先行 `/tmp/typebar-tape-presentation-red.log` 两项四处预期失败（0.703 秒）。首轮编译尺寸常量歧义保留 first-focused.log；后续实际词模式未失效重算与全文件静态断言误涉无关过渡均定位修正。帧间测试最初更换目标不构成反例，保留 frame-request-red.log；真正同目标更新 unchanged-red.log 一项两处失败，再修复配置请求抢先 sample。三图最初只有黑色文字／光标，对照“图片不同”不足，`text-pixels-red.log` 一项三处失败证实灰色像素为零但有不透明文字。明确转换原生属性后像素守卫与截图通过；新增 fixture 错用不存在的 apply API 导致的编译失败保留 native-colors-verified.log，只修测试调用。实际字宽变化 `metric-reanchor-red.log` 一项两处预期失败（17.30859375 未变为 32），随后按测量值失效修复。共同日志前缀 `/tmp/typebar-tape-`，不删失败、不用跳过换绿灯。

最终定向 `presentation-final-focused.log` 107 项零失败零跳过（7.673 秒），含新增 17 项、已有纵向／位置／闪烁／专用字层／高亮与 32 组横向源码对照。三张实际文字＋主／pace 组件图在 `/tmp/typebar-tape-presentation-focused-render.QGAhnL` 逐张复查：起始边距、文字保留而主 bar 消失、滚动中间文字／pace 左移而主 bar 固定。像素守卫按实际 backing scale 换算坐标，不能因只捕到 markers 而通过。唯一组件窗口从不显示或激活，测试后关闭；不是完整练习窗口／真实输入或流畅度验收。

最终冻结完整门禁 `/tmp/typebar-tape-presentation-complete-readiness.log` 退出 0：原生 3,708 项零失败零跳过（805.195 秒），服务 501 项零失败零跳过（11.934 秒）；新增 17 项在全量中实际通过（0.852 秒）。实际十万词耐久 151.354 秒，16 项隔离磁盘冷读 6.273 秒；固定参考／元数据、53 表面／生产文件／测试符号、1,083 人工结构及未启动应用包／scheme／严格签名／原创边界通过。11 个冻结实现／测试／脚本／矩阵哈希 `/tmp/typebar-tape-presentation-frozen.sha256` 前后一致，完整门禁运行期间无文件编辑，终态后仅补本轮结果和 ASL 审计更正。62 份完整日志在 `/tmp/typebar-tape-presentation-complete-logs.JXVeM4`，86 张组件图在 `/tmp/typebar-tape-presentation-complete-render.hxCj6Q`；本轮三张 Tape 图已再次逐张复查。CoreData／AddressBook XPC、隔离只读 SwiftData 513、Node 实验性警告与早期失败均保留；不声称这些既有诊断已修复，不删断言或跳过换绿灯。

只读复核还证实 ASL 历史“等价实现”不成立：ASLHandshapePolicy 的 A／D／I 返回同一 mask 且无 motion cue，ASLHandshapeGlyph 只据 mask／cue 绘制，同状态同大小时三者完全相同；E／M／N／O／S／T 也共用零 mask（后续更正：C 为 2，不属于零组）。已有测试只证明可返回 mask 与 J／Z cue，不证明手形语义。OFFICIAL_FUNBOX_AUDIT.md 将 ASL 明确降为部分覆盖，并修正未纳入 Weakspot／Polyglot 的旧汇总；该轮没有修改 ASL 产品代码、复制官方字体或宣称已解决。下一增量须先建立可靠手形语义与独立矢量证据，再接光标，不能只给错误手形补装饰。

同会话有界风险／决策复核（非独立）检查锁定框与布局坐标、水平与垂直 ready／累计修正、配置抢帧、属性桥接和资源生命周期；根因调试以像素／实际字宽反例定位而不是猜修复。Tape 换行／RTL／混合方向仍保留原有普通回退；长卷带前缀裁剪及其场景修正、no-space／复杂 scalar 几何、真实 SwiftUI 渲染拆卸顺序、任意 RAF 交错、长期性能与设备／IME／VoiceOver 仍开放。ASL、系统鼠标光标与完整周边也未完成。53 表面分类不升级，新增三个人工项保持待验收，零 Typebar 主程序启动、无真实库／Keychain／账户／部署；整体无损纯重写 goal active，下方为历史阶段。

## Choo 实际字形框与普通听写独立光标增量

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 保持只读清洁。完整读取 Caret 类／包装器、Choo／tts／ASL CSS 及相关 Funbox 元数据，核对 test.scss 的正确、错误、多余字母和 highlight-off 选择器。Choo 只旋转字形，光标读取未旋转布局框；零宽目标回找前一可见字形。tts 只令 untyped 色透明，不应把全部已输入文字和独立光标一并隐藏。

原创 ChooLayerView 将 canonical glyph ID 映射到自己的实际 glyphFrames，独立子 PromptCaretNativeView 共用现有主／节奏渲染器和 blink 状态；不把 ID 伪装为 TextKit 文本偏移，不测量旋转边界。几何版本变化重新解析目标，仅真实目的框变化才重定向剩余节奏时长，避免每次输入重新开始同一个 tween。零宽回找、换行／缩放、空格末端宽度、非连续 ID、缺失目标不回落虚构文本框、弱闭包和拆卸停止分别验证。主光标闪烁不影响 pace 或旋转字层；移除旧 current 字符假背景／强调色。继续使用有界 presentation／pace 计时器，没有全局监听或新增后台循环。

普通听写不再排除独立光标；PromptGlyphAppearance 在既有高亮／blind／typed effect 规划后只隐藏 future 角色，正确、错误、多余字符沿用相应颜色。最终 applyVisibility 在 legacy caret 和文字效果改色后执行，仅清前景，不删文字、布局、背景或下划线，避免回退样式重新泄露目标；普通听写闪烁覆盖不等于 Tape＋听写全部完成。设计技能促使维持现有原生字体／布局／颜色，仅分离光标与文字，不重设计页面。

QA-only `check-source-special-caret.mjs` 执行完整实际 Caret 模块的目标解析器，16 个 LTR 自有布局夹具覆盖四样式、字前／字后和零宽回找，并将真实原生字体的空格 advance 传入对照。主张限于横向位置／全宽，不声称 CSS 与 AppKit 基线／形状高度或浏览器动画等价；DOM／方向／尺寸为明确自有边界。tts／文字选择器为静态核查，不是浏览器 CSS 引擎执行。探针已加入完整门禁，产品不包含参考代码、CSS、字体、资产或 JS 运行时。

行为先行静态红测 `/tmp/typebar-special-caret-red.log` 一项三处预期失败；实际 NSView 目标切换 `/tmp/typebar-special-caret-target-red.log` 一项一处预期失败，旧框未跟随 canonical ID 更新，修正主目标失效判断。`expanded-verified.log` 81 项中唯一失败定位到 concealment 位于 legacy 改色之前，移到末端并加共享生产 helper 后 `visibility-verified.log` 82 项零失败零跳过（1.321 秒）。日志共同前缀 `/tmp/typebar-special-caret-`；早期漏传参考的 40 项／1 跳过、夹具 API／类型编译错误和所有失败保留，不作为最终证据。最终 `source-render-verified.log` 84 项零失败零跳过（1.647 秒），含新增 20 项；完整门禁结果另记，不能借上一轮完整绿灯证明此轮。

同会话有界决策／风险复核（非独立）检查 ID／偏移分离、未旋转几何、重复几何版本不重启 pace、文字效果泄露及子视图生命周期。两张实际 Choo 字层＋光标组件图在 `/tmp/typebar-special-caret-focused-render.tAOEIg` 已逐张检查，on／off 只有主 bar 消失，非空文字保留；唯一组件窗口从不显示／激活，测试后关闭，动画层时钟仅 QA 冻结以复现。不是旋转逐帧流畅度、完整练习 UI 或真实输入设备证明。没有 Typebar 主程序启动，没有真实库／Keychain／账户／部署操作，成绩／回放／归档／SwiftData／账户协议不变。

Tape 锁定／原版 margin 动画、ASL 手形几何与混合方向 inline 回退闪烁、渲染切换与共享 coordinator 的真实 SwiftUI 拆卸顺序、任意配置／输入／RAF 交错、系统鼠标光标／完整页眉页脚和设备／IME／VoiceOver 仍开放。53 表面分类不升级；新增三个手工项仍待验收。下方为历史增量，不把普通＋Choo＋普通听写覆盖等同完整特殊分支或整体无损重写，goal active。

本轮最终冻结完整门禁 `/tmp/typebar-special-caret-complete-readiness.log` 退出 0：原生 3,691 项零失败零跳过（793.875 秒），服务 501 项零失败零跳过（9.790 秒）；新增 20 项在全量实际通过（0.295 秒）。十万词实际耐久 155.712 秒、16 项隔离磁盘冷读 5.245 秒，固定参考／元数据、53 表面／生产文件／测试符号、1,080 人工结构与未启动应用包／scheme／严格签名／原创边界通过。8 个冻结哈希 `/tmp/typebar-special-caret-frozen.sha256` 前后一致，门禁运行期间无文件编辑，终态后仅补本文与摘要文档。

61 份完整日志在 `/tmp/typebar-special-caret-complete-logs.XBLkab`，83 张组件图在 `/tmp/typebar-special-caret-complete-render.ooyPdr`。本次新 Choo on／off 两图再次逐张检查，文字保留、主 bar 消失；仍只是实际组件在 QA 冻结图层时钟下的两相位，不是旋转逐帧或完整主窗口。CoreData／AddressBook XPC、隔离只读 SwiftData 513 和 Node 实验性诊断完整保留；早期红测与夹具编译失败不删除、不替代最终证据。无 Typebar 主程序启动，结束后进程仍为零；人工／剩余特殊渲染与整个 goal 均保持开放。

## 普通原生光标层闪烁与输入停止增量

固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`、只读清洁。完整读取 test/caret、elements/caret、focus、RAF debounce、caret.scss、两个关键帧及 afterAnyTestInput，核对首次输入／开始／重开／完成／输入框 focus 与配置 setter 上下文。输入回调即使视觉专注已经提交也直接 stopAnimation，不能只依赖 Focus.set 的状态变化。配置 smoothCaret 变化会重新设动画，即使仍在视觉专注；下一次输入再停止。原版 inline 动画名可覆盖 outline 类的 none，不能笼统豁免该样式。

原创 PromptCaretBlinkCurve／Clock 以一秒周期、每关键帧段分别的 CSS ease 求值；smooth 为 0→1→0，hard 在 50%–51% 短暂淡出而非方波。同动画名的 slow／medium／fast 保持相位，hard／smooth 切换重启，revision 保留帧间 stop→start；隐藏、尝试更换、stop 和系统／用户减少动态效果分别退休或固显。实际规范依据为 [CSS Animations](https://www.w3.org/TR/css-animations/#animation-timing-function) 与 [CSS Easing](https://www.w3.org/TR/css-easing-1/#cubic-bezier-easing-functions)。不把横移平滑时长当闪烁周期，不更改节奏光标透明度、几何或既有截止计时器，不新增 Timer／后台循环。

TypingVisualFocus 单独维护 blink 状态与版本：下一主线程轮次提交专注时 stop／start，实际输入／删除／候选更新立即 stop，配置变化和输入框重新取得焦点 start。focus 或 key-window 在两次绘制间失去并恢复仍显式重启版本，退休失效旧专注提交。普通 PromptCaretNativeView 每帧从实际视图闭包读取可见性／blink／版本，不要求 SwiftUI 每帧重新构造提示；只更新主 marker alpha，既有 TextKit 目标变化规则不变。设计技能选择维持既有字体、形状、颜色和布局，仅恢复原版语义所需动画，并保留减少动态效果。

QA-only 脚本执行完整实际 Caret 类、focus／RAF 模块及 blink 包装器、afterAnyTestInput，四组共 28 状态与原生组合对照；DOM、几何、声音、signal 和帧队列是自有边界，不冒称完整浏览器事件或上游整套 Vitest。另将固定关键帧和 animation shorthand 仅在内存载入本机 loopback QA 页，用隐藏 IAB Chromium 154 的真实 CSSAnimation.currentTime／computed opacity 采集两周期 32 个数值。页面无外部资源、账户或 cookie 操作，采样后关闭唯一 QA tab 并停止自有服务器。仓库仅保留数值及 CSS 哈希，不保存原版 CSS／字体／图片或在产品内使用 WebView、JS／TS。Swift 曲线逐值误差上限 0.00001；浏览器样本与源码哈希也由探针核对。

行为先行 `/tmp/typebar-caret-blink-red.log` 一项一处预期失败（0.756 秒）：旧生产 NSView 在 0.75 秒仍为不透明。探针最初 class 名与包装器 namespace 在 VM 内冲突失败保留 `/tmp/typebar-caret-blink-source.log`；隔离完整 class 的词法作用域修正，没有改实际模块逻辑。`/tmp/typebar-caret-blink-focused.log` 失败于 SwiftUI 长表达式类型检查；只将同序修饰链拆为两个 computed view，未删行为。之后 50 项零失败零跳过（1.037 秒），复核帧间重新可见并补版本后 53 项零失败零跳过（1.062 秒），日志分别为 focused-verified.log／refocus-verified.log（共同前缀 `/tmp/typebar-caret-blink-`）。最终组件图与完整冻结门禁结果另记。

同会话有界决策／风险复核（非独立）排除 hard 方波、已专注不再 stop、outline 不闪、slow→fast 无条件重启、帧间重新可见未退休相位等假设。当前只接通已有普通原生独立光标层；Tape、ASL／Choo、listening 与混合方向 inline 回退尚未接通等价闪烁。任意配置／输入／窗口事件在原 RAF 与原生轮次间的交错、鼠标光标隐藏／首次保留、完整页眉／页脚、实际设备／IME／VoiceOver 仍开放。矩阵仍 53 表面既有分类，扩充证据不升级整体完成；新增三人工项保持待验收。成绩／回放／归档／SwiftData／账户协议不变，零 Typebar 主程序启动，不触及真实 Typebar 库、Keychain、账户或部署，整体 goal active。下方为历史增量，不用旧绿灯证明新实现。

最终扩展定向 `/tmp/typebar-caret-blink-final-focused.log` 61 项零失败零跳过（11.675 秒），含新增 15 项、相关光标／专注与页面矩阵回归。完整冻结门禁 `/tmp/typebar-caret-blink-complete-readiness.log` 退出 0：原生 3,671 项零失败零跳过（841.587 秒），服务 501 项零失败零跳过（11.180 秒）；新增 15 项在全量中实际通过（0.394 秒）。十万词耐久实际通过 161.422 秒、16 项隔离磁盘冷读 5.638 秒，固定参考／元数据、53 表面／生产文件／测试符号、1,077 人工结构与未启动应用包／scheme／严格签名／原创边界全部通过。10 个冻结哈希 `/tmp/typebar-caret-blink-frozen.sha256` 前后一致，门禁期间无文件编辑，终态后仅补结果文档与旧人工剩余描述。

60 份完整日志保存在 `/tmp/typebar-caret-blink-complete-logs.YAFmdr`，81 张组件图在 `/tmp/typebar-caret-blink-complete-render.ZMPbru`。新主光标 on／off 两图已逐张复查：主 bar 消失、pace outline 保留；它们仅透明背景的光标层，不是完整提示／主窗口或真实逐帧设备验收。唯一组件窗口从不显示、不激活并在测试后关闭；无新增 Typebar 主程序。CoreData／AddressBook XPC 系统诊断、隔离只读 SwiftData 513、Node 实验性警告和早期红测／编译／探针失败保留，不声称已修复或以删断言、跳过换绿灯。三项人工状态仍待验收、特殊分支与完整 goal 均保持开放。

## 独立视觉专注、鼠标退出与通知过滤增量

固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`，只读清洁。完整读取 [focus.ts](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/focus.ts)、RAF debounce、test caret 包装器，核对 afterAnyTestInput／start／restart／result／commandline／page 的相关函数或调用上下文，以及 TestConfig／Keytips／Footer／Header 和 getFocus 消费位置。原版视觉 focus 与 testFocusState 的一秒失焦警告不同。实际 mousemove 比较单轴正向 `>3`，不是注释的 5，也不是绝对值；PageTransition 时忽略。set 在请求时先比较已提交状态再排 RAF，因此同轮相反请求未必取消前一次。

原创 TypingVisualFocus／MouseBridge 仅补有界部分：每练习视图独立状态、下一主线程轮次合并提交、严格阈值及窗口／终止退休；通知过滤不再借用 first responder + hasStarted，普通通知暂藏不删除历史；配置栏保留布局但隐藏、禁用鼠标和键盘编辑并从辅助功能隐藏，快捷提示同读视觉状态。设计技能促使保留现有字体／间距／颜色，不重设计页面；过渡遵守系统及用户减少动态设置。输入、自动输入和删除看实际反馈／文本变化，IME 与 test start 也接入；实际 `a\n` 部分批量输入改文本但最终返回空声音反馈，不能仅由声音数组判定。既有失焦警告、窗口返回重开、no_quit 预检、公告／社交通知／奖励及持久化结构不变。

原生安全适配不等于完全浏览器等价：成功重开、终止、命令面板、onDisappear 与窗口不 key／有 sheet 同步 retire 并失效旧回调，不使用浏览器 RAF 时钟。重复请求每轮只排一次弱回调，无新增全局／local 事件监听。NSTrackingArea 限于练习内容可见区域和所属 key window，挂接／拆除先移除旧区域，hitTest 为 nil，不修改 acceptsMouseMovedEvents、不抢输入、不吞事件。直接 AppKit 测试用未显示窗口和明确 isKeyWindow／attachedSheet 替身，验证单区域、旧窗口／背景／sheet／拆除隔离；不是 sendEvent、真实 tracking routing 或实际 key-window 证明。Native deltaX/Y 保留方向和阈值，CSS 像素／设备缩放未证明。

同会话有界决策／风险复核（非独立）推翻声音反馈唯一入场与重复排队假设；另补隐形配置栏 disabled，退休位于重开拒绝预检之后。静态红测 `/tmp/typebar-visual-focus-red.log` 一项四处预期失败（0.706 秒），只证明入口缺失。`/tmp/typebar-visual-focus-focused.log` 因新增测试夹具 actor 隔离和参数顺序编译失败；修正后 `/tmp/typebar-visual-focus-focused-verified.log` 44 项零失败零跳过（2.681 秒）。第二红测 `/tmp/typebar-visual-focus-admission-red.log` 两项三处预期失败（0.708 秒），含实际 100 请求排 100 回调而非 1。修正后集中 61 项仅既有配置探针因漏传 QA 依赖失败（4.491 秒），保留 `/tmp/typebar-visual-focus-final-focused.log`；完整环境复跑 `/tmp/typebar-visual-focus-admission-verified.log` 62 项零失败零跳过（3.929 秒）。随后仅补配置栏 disabled 与静态守卫，最终冻结门禁另记。

QA 脚本完整执行实际 focus／debounced-animation-frame 模块，12 组共 47 个逐步 focus 状态与原生对照，另断言原版 cursor／caret effects。signal、DOM、caret、过渡及帧队列为自有边界，不执行 Solid／浏览器／CSS；原生状态对照不声称已重写 cursor／caret effects。探针前后核对固定 SHA／clean 并纳入门禁；产品无 JS／TS 运行时或参考源码／资产。53 表面既有分类不变，仅扩充 TestSurface 证据与部分描述；新增三项人工记录仍待验收。鼠标光标隐藏及初次保留例外、主光标闪烁、完整页眉／页脚／模式说明、菜单／设备／真实多窗口／VoiceOver 仍未完成或未验证。零 Typebar 主程序启动，不读真实库、Keychain、凭据或账户；整体 goal active。

视觉专注最终冻结门禁 `/tmp/typebar-visual-focus-complete-readiness.log` 退出 0：原生 3,656 项零失败零跳过（823.688 秒），服务 501 项零失败零跳过（11.214 秒）；新增模型 10／AppKit 3／静态接线 2 项全部执行。实际十万词耐久 156.026 秒，16 项隔离磁盘冷读 4.851 秒；固定参考、元数据、53 表面／文件／测试符号、1,074 人工结构与未启动应用包／scheme／严格签名／原创边界通过。8 个实现／测试／脚本／矩阵冻结哈希 `/tmp/typebar-visual-focus-frozen.sha256` 前后一致，门禁后仅补结果文档。

完整 59 份日志保存在 `/tmp/typebar-visual-focus-complete-logs.WBjDE5`，79 张既有组件图在 `/tmp/typebar-visual-focus-complete-render.yBo8xY`；本轮逐张复查普通／专注两张通知堆栈，未制造或冒称新的主练习视觉专注 GUI 图。CoreData／AddressBook XPC、隔离只读 SwiftData 与 Node 实验性诊断保留，早期红测／夹具／环境失败亦保留；没有用删断言／跳过换取通过。系统 SDK 的 NSTrackingArea／NSEvent 头文件已核对。三项人工状态不升级，鼠标光标／闪烁／完整周边与真实设备剩余项保持开放；零 Typebar 主程序启动，goal active。

## 配置通知、已知换行格式与应用确认增量

固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整读取通知状态／两处展示、[URL 配置加载函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/controllers/url-handler.tsx)、[配置 setters](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/config/setters.ts)、escapeHTML／字符串帮助函数及开发通知回调。固定版本 `useInnerHtml: true` 文本盘点仅三处：URL 配置摘要、趣味拒绝、开发通知；实际格式是转义文字加 br。不是一般富文本链接需求的穷尽证明，动态／未来调用仍开放。

原创 LocalNoticeMessagePresentation／View 在主堆栈和历史共用：br／br/／br / 转原生换行，大小写 BR 可识别；按固定 escapeHTML 的七种输出一次解码，转义出的尖括号不二次解释，原始消息／JSON 复制不变。未标记保持 Text(verbatim:) 纯文本；未知标签、属性或未闭合标签整条原样回退并说明，不半解析、不解释 Markdown、不执行脚本、样式、URL、附件或资源，也不使用 WebView／HTML document importer。它补齐已知生产格式，不声称支持所有 HTML 实体、空白折叠、标签或浏览器布局。设计技能选择保持既有系统材质／文字层级，真正的换行承载摘要结构，不添装饰和外部字体／CSS／资产。

TestConfigurationShareActions 是分享工作表实际使用的同步生产动作：复制检查真实 BOOL；导入继续用现有自有／网页离线解码器，原生 apply 返回确认 Bool，挑战返回 applied／requiresSetup／rejected。只确认应用后发 10 秒成功摘要；拒绝保留窗口并重要提示，格式错误只发固定本地化消息。摘要只保留选择元数据，不记录链接、主机、压缩数据、自定义正文、令牌或 Error 对象。网页全空字段仍执行应用／重开但不制造摘要，部分字段按八槽位原序列举；解码仍原子，旧 preset API 转发新增本机字段掩码，不改变 Codable／归档／偏好／SwiftData／网络协议或真实数据。

原版 loadTestSettingsFromUrl 不检查各 setConfig Bool，可能描述尝试的字段；QA 显式执行返回 false 的适配器证明该函数仍发布成功。原生主窗口 apply 确认 Bool 后，分享回调返回实际应用快照或 nil，成功摘要只读取实际快照而非请求值；这是明确的真实性适配，不冒称逐项错误处理与原版完全相同。第二轮有界审查的请求 60 秒／实际规范化 30 秒反例，在 `/tmp/typebar-configuration-notices-canonical-red.log` 一项两处预期失败（0.645 秒），已改用实际快照并保留反例。自有链接摘要列完整本机测试选择，网页摘要只列非 null 字段；数值／标签为原生本地化，外部引语身份、原有严格接纳与 LZ 格式兼容限制仍沿用既有合同。

趣味组合、模式、标点／数字与高亮拒绝保留原内联说明，并由实际 ConfigurationNoticeFeedback 发 5 秒普通通知；趣味命令遇锁定发 3 秒重要通知，专注时可见。挑战选择不冒称已经开始：脚本和单手后续设置给 requiresSetup，分享关闭后排队展示，普通挑战以实际 apply 结果为准。此次同会话有界决策／风险复核（非独立）发现旧 apply 在字体／脚本拒绝前清掉 practiceReturnPreset，已移到全部拒绝预检之后；静态顺序守卫只证明代码排序，不冒称主窗口状态／工作表已经人工运行。

行为先行 `/tmp/typebar-configuration-notices-red.log` 一项三处预期失败（0.738 秒）仅证明三个生产入口缺失；编译后接线两项通过。新行为用实际 helper、原生链接和网页 LZ 解码器、应用／拒绝／后续设置回调、隐私与原始详情等断言验证。原生 48 项首轮中一个 unexpected 是 QA 自定义文本给成 string，固定 results.ts:54–58 要求非空 string[]；改夹具而不改产品解码，失败保存在 `/tmp/typebar-configuration-notices-focused.log`。改后模型相关 30 项零失败零跳过（0.474 秒）；新增反馈 helper／预检顺序后的最终集中验证另记。

QA-only check-source-configuration-notices.mjs 从只读固定源码执行完整 loadTestSettingsFromUrl、toggleFunbox、开发通知回调以及完整 findGetParameter／escapeHTML／camelCaseToWords／capitalizeFirstLetter。8 组原 URL 分支、拒绝 setter 分支、锁定／冲突分支和 9 组格式化消息与原生对照；真实 lz-ts 1.1.2 来自固定锁文件，仅安装隔离 QA 路径、禁生命周期脚本、不入产品。配置、schema、事件、重开和通知收集仍为自有适配器，不运行实际 Zod、Solid、DOM、HTTP、计时、设备剪贴板或上游整套构建。首轮跨 vm 原型严格比较、函数名前缀误选和回调闭合边界三次 QA 失败分别保留 source.log／source-verified.log／source-final-verified.log（共同前缀 `/tmp/typebar-configuration-notices-`）；修正适配器精确边界，不改生产逻辑或放宽字段断言，最终 source-final.log 通过。Swift 6.2.4／SDK 26.2、Node v22.22.1 已实测；不把执行源码测试等同复用上游实现进产品。

实际快照修正前 `/tmp/typebar-configuration-notices-verified.log` 集中 50 项零失败零跳过（38.084 秒），18 项离屏 37.529 秒；四张新增浅深色堆栈／窄内容历史已逐张检查。它仅是前一修订结果，不用旧绿灯支持新代码。最终快照回调修订后 `/tmp/typebar-configuration-notices-canonical-verified.log` 集中 51 项零失败零跳过（38.628 秒），含配置通知 12、接线／顺序 3、原通知 12、离屏 18、旧链接／趣味回归 6；离屏 38.093 秒。完整冻结门禁另记。

最终冻结完整门禁 `/tmp/typebar-configuration-notices-complete-readiness.log` 退出 0：客户端 3,641 项零失败零跳过（827.896 秒）、服务 501 项零失败零跳过（12.623 秒），十万词耐久实际执行 150.767 秒，16 隔离磁盘冷读 7.231 秒。固定参考／元数据、53 有界表面／原生文件／测试符号、1,071 人工结构与未启动应用包／scheme／严格签名／原创资源边界全部通过。12 个实现／测试／脚本／矩阵冻结哈希 `/tmp/typebar-configuration-notices-frozen.sha256` 前后一致，之后只补三份结果文档，不更改已测代码。

最终 58 日志保存在 `/tmp/typebar-configuration-notices-complete-logs.1ooJv5`，79 张图在 `/tmp/typebar-configuration-notices-complete-render.LoR3V5`；四张新增浅深色堆栈／窄内容历史已逐张复查。不可见串行隔离窗口不激活；历史 360 宽仅是内容组件，不冒称外层 minWidth=420 的真实工作表。已知 macOS CoreData／AddressBook XPC、隔离只读 SwiftData 513、Node 实验性诊断及早期编译 actor-isolation 警告保留，没有声称修复；红测和 QA 失败记录不覆盖。真实点击／关闭／滚动／剪贴板、锁定／字体拒绝、脚本／单手工作表排队、主窗口返回状态、多窗口、键盘／VoiceOver 与 HTTP 仍未人工验收，三项状态不升级。零 Typebar 应用启动，工作区未触及真实账户／库／凭据或部署。

53 表面分类不变，仅扩充 AlertsPopup 生产路径与测试符号；新增三个人工项后 1,071 仍仅结构盘点。全部通知生产者、通用 HTML／链接、原版鼠标专注控制器、动画、完整 Alerts 同屏、多窗口、真实字体／脚本／工作表、网络、键盘／VoiceOver 仍待补齐或验证。无凭据读取、真实账户／数据库访问、部署、后台任务或 Typebar 应用启动；整体 goal active。

## 本机会话通知与历史增量

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`：只读核对完整 [通知状态模块](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/states/notifications.ts)、error utility、Notifications overlay、NotificationHistory／AlertsPopup 和收件箱 claimRewards。原版临时通知最新在前，历史保留最后 25 条并逆序显示；notice／success 默认 3,000 ms、error 默认不自动关闭，正时长加 250 ms 退出余量，关闭原因 click／timeout／clear。临时关闭不删历史，专注时只留 important，两条以上可见零时长通知才有全部关闭，截图隐藏，详情复制 title／message／details JSON。这不是现有社交通知列表或奖励邮件的另一名称。

原创 `LocalNoticeCenter`／`LocalNoticeStack`／`LocalNoticeHistoryView` 以 Swift 6.2.4、macOS 14 目标原生实现三种级别、可选标题／系统图标、类型化结构详情、响应状态／422 验证详情和错误消息组合、计时器与回调、有限历史、重要性过滤及 JSON 复制反馈。历史最旧在前保存、显示反序，UUID 不复用；计时器弱持有中心、释放取消，延迟取消后的完成不能删除别的通知，超大时长不溢出。清除先退休旧批次再调回调，回调重入新增通知保留。复制详情不制造新历史，失败只在工作表提示；显式 null 与缺省分开，非法非有限数字拒绝编码而非静默改 null。

实际入口：工具栏“通知”菜单区分会话／社交通知，`notification-history` 命令和完成页导出菜单可打开历史；原社交通知与奖励收件箱功能保留，服务公告继续走原公告入口。主练习、完成页和奖励页挂接真实生产通知卡，完成页覆盖层不受庆祝 Canvas 命中拦截（原庆祝层禁 hit testing）；导出图片只渲染既有 ResultSnapshotCard，不含通知堆栈。六类结果复制保留原 exportStatus，同时按真实写入结果发布成功／错误；缺回放／提示、无慢词及坏阈值也可回看，不把已复制的提示／输入正文放入历史。AppKit SDK 26.2 的 NSPasteboard.h 明确 setString／writeObjects 返回 BOOL，原有无条件成功已改为检查实际返回值；测试注入写入器，不接触用户剪贴板。

奖励更新只在既有当前操作／账户范围确认后发布徽章名，邮件中明确选择的未领取徽章才进入提示，5,000 ms／奖励标题／gift；删除、已读或 XP-only 不伪造解锁提醒。读取／更新失败只追加通用错误，不自动捕获响应、Error 对象、邮箱、令牌或输入。原领取／能力／认证／库存与服务真值逻辑不变；模型与静态接线不证明真实 HTTP 领取或 UI 回调已人工执行。

同会话有界决策／风险复核（非独立审查）选择由现有 AccountSession 持有中心，应用窗口共享同一会话；账户 UUID 或原始地址变化清空计时器和历史，相同用户资料／XP 刷新保留。退役账户的回调不执行，防旧回调跨身份副作用。这是比原版全局会话历史更严格的明确隐私适配，不冒称原版也会清空。只在内存中保存，不新增 SwiftData／归档／偏好／服务字段、网络接口、凭据访问、迁移、部署或后台任务；回退无需数据恢复，系统剪贴板是用户主动复制的独立外部效果。

设计技能促使采用系统材质通知卡、三种语义级别和同时可读的 SF Symbol，窄侧栏表达真实级别而非装饰；历史用原生可选择正文、明确复制动作和本机会话说明，无上游字体／图标／CSS／动画资产。明确未完成：当前只接结果复制与奖励页生产者，不是全部原版通知调用点；原版 HTML 富文本／链接目前保留原始文本并标注，未声称格式等价；原生按输入／窗口焦点及活动测试过滤，未重写原版鼠标移动三像素的专注控制器；动画、完整 Alerts 同屏布局、真实多窗口、键盘／VoiceOver／计时与剪贴板、全功能无损仍待验。53 表面仅包括原 52 页面／模态加本次实际 AlertsPopup，不代表其他 popup 已穷尽盘点；整体 goal active。

行为先行 `/tmp/typebar-local-notices-red.log` 实际一项测试三个预期失败（0.818 秒）证明展示／历史／复制入口缺失，静态接线只是接线证据。核心首轮 21 项零失败但一项 QA 依赖测试跳过；`/tmp/typebar-local-notices-source-focused.log` 保留一次性计时器适配器未出队的失败，按实际事件循环先出队后回调修正，生产逻辑不改、断言未放松。合并首次 `/tmp/typebar-local-notices-render-focused.log` 40 项中两处失败／一处 unexpected，均由命令遗漏 TYPEBAR_INBOX_SOURCE_PACKAGE 造成；在隔离 `/tmp/typebar-local-notices-source-runtime.Wf5MVh` 准备锁定 TanStack DB 0.6.8 后原样复跑。最终 `/tmp/typebar-local-notices-render-verified.log` 41 项零失败／零跳过（36.602 秒），含实际等待 continuation、最大时长／释放取消／回调重入／范围退休、真实剪贴板 helper 结果与私密正文不保存、徽章选择及生产离屏表单；五张新增图在不可见隔离窗口生成，不激活、不联网、不调用用户剪贴板。

`check-source-local-notices.mjs` 只在 QA 执行完整实际通知模块／错误工具及实际完整 copyDetails 回调，43 次状态变化逐步与原生对照（仅默认标题本地化），另执行真实 timeout callback 和详情复制成功／失败。store 为自有数组适配、时钟与剪贴板为明确捕获器，不运行 Solid 响应追踪、浏览器、动画、真实计时或设备。探针纳入完整串行门禁，前后检查固定 SHA／干净参考；产品没有 TS／JS 运行时或上游实现／资产。页面矩阵新增真实 AlertsPopup 并登记生产路径／测试符号，三个人工项增至 1,068，仅结构盘点。零 Typebar 应用启动，最终冻结完整门禁另记。

首轮冻结完整门禁 `/tmp/typebar-local-notices-complete-readiness.log` 客户端执行 3,626 项，三处失败全部来自同一旧盘点测试的 52／46 数量与 sourceFiles 精确断言（793.600 秒），不是零失败；服务与打包尚未执行。原日志保存在 `/tmp/typebar-local-notices-complete-logs.wj3TKv`，保留系统 XPC 与隔离只读库诊断。按实际新增 AlertsPopup 更新为 53／47、登记其精确路径，另断言该表面实际存在且有原生映射，未删除守恒／互斥／证据路径／测试符号检查。单项复验 `/tmp/typebar-local-notices-surface-recovery.log` 通过（9.083 秒），随后重新冻结完整门禁；最终结果另记。

修正精确盘点测试后重新冻结的完整门禁 `/tmp/typebar-local-notices-final-readiness.log` 退出 0：客户端 3,626 项零失败／零跳过（819.638 秒），服务 501 项零失败／零跳过（12.994 秒）；十万词耐久实际执行 155.471 秒，16 项隔离磁盘冷读 5.406 秒。固定参考／元数据、53 表面／生产文件／测试符号、1,068 人工结构、未启动应用包／scheme／严格签名／原创资源边界全部通过。15 项冻结实现／测试／脚本／矩阵哈希 `/tmp/typebar-local-notices-verified-frozen.sha256` 前后一致，结果只补本文及人工／页面审计文档，不更改已测代码。

最终 57 份日志保存在 `/tmp/typebar-local-notices-final-logs.oUd2z3`，75 张图在 `/tmp/typebar-local-notices-final-render.RXyJJV`；本次新增五张空历史／长详情浅深色窄组件／完整与专注通知堆栈逐张复查。不可见串行隔离窗口不激活、不联网、不读写用户剪贴板、不打开真实库；360 宽历史仅测试内容组件，不冒称外层 minWidth=420 工作表。已知 macOS CoreData／AddressBook XPC、隔离只读 SwiftData 513 与 Node 实验性诊断保留，没有修复这些系统诊断；首轮与早期失败仍按上文保留。真实点击／滚动／键盘／计时／多窗口／HTTP／VoiceOver 未验，三项新增人工状态不升级；零 Typebar 应用启动，整体 goal active。

只读已知通知 API 名称加左括号文本扫描，在固定 `frontend/src/ts`（排除通知状态模块和测试文件）找到 85 个文件、303 个匹配。它不是 AST 或运行时穷尽盘点，别名／动态调用／包装器未证明覆盖，不作为已完成比例；用于后续生产者补齐，当前只声明结果复制和奖励页入口。

Typebar 已独立接通周任务、持久邮件、一次性领取及 SwiftUI 收件箱。送达不会增加账户 XP；领取才入账，领取 XP 不写回周练习榜。此增量不是完整 Monkeytype 重写完成声明，整个 goal 保持 active。生产代码与文案为自有实现，固定参考只供只读 QA 动态执行，不进入应用包。

[日榜任务与交付](DAILY_LEADERBOARD_SETTLEMENT_CONTRACT.md) 也已沿用此原生收件箱及领取链路；日榜生产与恢复的新增证据见该合同，不将本文件的上一阶段测试汇总当作日榜全量结果。

## 接口与原生入口

| 入口 | 身份要求 | 行为 |
| --- | --- | --- |
| GET v1/inbox | 当前账户会话 | 返回该账户 inbox 与 maxMail |
| PATCH v1/inbox | 当前账户会话 | 领取或删除指定邮件，返回邮箱及刷新后的 user |
| GET v1/moderation/weekly-rewards | 非空部署者审核密钥 | 只读任务状态，不提供外部发奖或触发任务接口 |
| 工具栏收件箱与命令打开奖励收件箱 | 原生登录账户 | 显示邮件、单封或批量领取、无待领取奖励时批量删除 |

PATCH 严格接受可选 mailIdsToMarkRead 和 mailIdsToDelete UUID 数组，允许空对象、重复 ID 和不属于当前账户的未知 ID；显式空数组、null、额外字段及非 UUID 拒绝。认证和配置门禁先于解码，禁用收件箱返回 503。Typebar 使用自有平铺响应及完整账户回执，不是原版返回 null 的 HTTP 协议兼容实现。

原生端要求 v1／typebar 服务明确宣告 rewardInbox available；旧服务、未知能力和禁用配置不会被当作空邮箱。领取没有乐观加分；成功回执才刷新账户。响应写入前同时检查原始地址、会话 token 和账户 scope，错误 user ID 或账户切换后的响应不应用。视图也检查操作身份，切换账户清掉旧列表和删除确认。原生列表按时间降序、当前系统语言区域的标题升序排序，标题相等时自选保持原顺序；零 XP 仍显示待领取。未读奖励行只显示领取，无奖励行显示删除。

原版查询未指定标题 collation，但实际锁定 TanStack DB 0.6.8 继承集合 locale 排序。QA 动态执行该确切 npm 包完整 comparison 模块和集合默认配置函数，原先 UTF-16 实现已被十二组反例推翻。Foundation String.compare 修正后仍复现一处中文重音顺序差异；原生改用公开 CoreFoundation 区域比较，并仅对比较操作数规范到 NFC，保留可见标题与同值原顺序，不引入 JS 运行时。四个显式区域样例对照不等于所有浏览器语言／系统 ICU 版本或完整查询的同值键排序等价。

## 领取与容量规则

[固定用户 DAL](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 的 updateInbox 仅领取未读目标邮件，先取读集合，再取删集合；删除优先，重复 ID 去重。XP 直接相加，不使用成绩奖励的 BSON 低位转换。标记已读同时清空 rewards，删除则移除邮件，重试不再领取。徽章保留原库存先出现的同 ID，再按奖励顺序追加新 ID。

自有 version=1 邮箱状态分离邮件、交付回执、领取账本和徽章库存。同一用户／邮件 UUID 的交付回执在删除或容量淘汰后仍保留，这是明确增加的幂等保证，不冒称原 DAL 也具有此保证。前插并保留 maxMail 封，淘汰未读邮件不领取；启用且容量零不保留邮件。坏状态、重复回执、不安全算术及领取／已读不一致拒绝加载。邮件和领取账本在一次文件提交保存，失败全部回滚。

删除成绩不删除领取信用；账户重置及删除账户清除该账户邮箱、交付、领取和徽章库存，不触及其他账户。全球任务去重记录保留，避免重放已经完成的周交付。邮件 XP 可为负，算术独立限制在 JavaScript 安全整数域；这不等于原 schema 全数值域兼容，后续成绩报告仍受既有上下文校验约束。

自有徽章使用字符串 ID、标题和 SF Symbol，不导入原版数值徽章目录、图片或 selected 资产字段。首次邮箱更新将当前已解锁的自有徽章纳入持久库存，使旧徽章先于新邮件奖励；它不是原版徽章 schema 或账户导入兼容证明。现有好友通知保持原独立机制，不冒充奖励邮箱。

## 实际调度与恢复

新成绩首次获得周缓存名次时，在同一投稿事务保存一个按接受 key 唯一的任务；同 UUID 重试不再安排，旧回执不补造历史任务。due 为 key 加七天加一分钟；首次 worker 扫描到期任务，失败最多尝试 23 次，每次在失败时钟后一小时再试。每次扫描最多处理十个任务，正常服务约每分钟扫描一次，故不承诺恰好到毫秒执行。

结算读取当时配置及尚未过期的原始缓存，而非投稿时冻结配置；原版 worker 不重跑公开查询隐私过滤，Typebar 保留这一私有交付行为，公开榜单仍使用当前隐私护栏。重叠档位取高，单名次取 maxReward，最后舍入，零奖励送未读邮件。启用空档明确失败；收件箱禁用不能掩盖此前的空档错误。空榜、禁用周榜、禁用收件箱或无匹配名次不产生邮件。自有空候选事务成功不证明真实 Mongo 空 bulk 的行为。

每个任务的全部邮件与 complete 状态共享一次原子文件提交。计算失败不留下部分邮件，记录 pending／failed 和不含账户内容的错误码；保存失败不消耗尝试次数，保留原待处理状态，重启后继续。complete 与 failed 记录不删除，这与原版成功／最终失败移除及 LRU 容量 100 的重复安排行为不同。

WeeklyExperienceRewardWorker 是单 writer actor 工作循环，实际 executable 使用 Vapor 4.122.1 的 asyncBoot／asyncShutdown 生命周期启停；重复 start 不生成第二循环，shutdown 取消并等待退出。测试显式注册并通过真实异步 boot／shutdown，不绑定网络端口，不启动 Typebar GUI。同步 boot 的默认协议钩子不运行本 worker，不支持多服务 writer、分布式锁或 BullMQ 兼容部署。

## 部署配置和文件升级

TYPEBAR_INBOX_CONFIGURATION 默认是 Typebar 自选 enabled=true、maxMail=100；原版 base 是 false／0，不宣称线上配置相同。TYPEBAR_WEEKLY_XP_CONFIGURATION 仍默认启用、15 天、空档位，因此实际任务会按规则报空档错误，不会自动猜奖励。部署者应明确配置档位，例如：

```json
{"enabled":true,"expirationTimeInDays":15,"xpRewardBrackets":[{"minRank":1,"maxRank":10,"minReward":50,"maxReward":200}]}
```

升级前备份完整服务 JSON，保持唯一 writer，禁止旧 writer 覆盖新文件。旧缺字段初始化空状态，仅在下一次成功写入时记录托管标记；纯加载不写字节。rewardInboxManaged 或 weeklyRewardJobsManaged 为 true 时对应状态字段缺失拒绝，显式 null／坏版本拒绝；新奖励已标记安排却缺任务也拒绝。标记是误删恢复护栏，不是抵抗任意文件篡改的密码学账本。恢复使用完整备份或向前修复，缺字段读取不证明无损降级。原生 SwiftData 列、归档 26 和设置 4 不变。

## 自动化证据和仍待验收部分

初始两个路由测试产生四处预期失败；禁用门禁和托管邮箱遗漏再产生三处失败。独立周任务标记反例在账户重置后复现一处失败，随后补护栏。初次 mailbox 排序表达式编译失败经具体类型和独立循环修复，不算行为测试红绿证据。

Scripts/check-source-inbox-claims.mjs 在只读固定检出动态执行完整 updateInbox 及其生成的 JavaScript function body，比较 108 组读删选择和 108 次重复操作；Mongo 更新管线为显式观测适配，不是真实 Mongo／BSON 事务。徽章数值 ID 仅在 QA 桥接成自有字符串和元数据，比较库存顺序，不声称原目录兼容。探针已接串行 readiness，前后核对固定 SHA 和干净状态。

聚焦原生九项通过，0.233 秒，含十二组实际依赖区域排序及反向规范等值拼写；服务二十三项通过，0.474 秒，均零失败／零跳过。首批服务十九项曾因缺环境跳过一项源码测试，保留历史但不替代后来补验。排序红阶段十二处差异、初次 Foundation 修正仍有一处差异均保留。HTTP 领取、账户隔离、严格形状、重试、磁盘提交失败、旧形状、任务重启、当时配置、零奖励／容量及异步生命周期均有自有自动化。

最终同一次串行门禁原生 2961 项通过，692.762 秒；服务 338 项通过，7.082 秒，均零失败、零跳过。新增十项原生及二十三项服务测试纳入全量，含领取回执的 XP／徽章联合解码。十万词耐久 148.850 秒，九项隔离磁盘迁移 3.972 秒；887 条人工场景只作结构校验，源码及原创边界审计、未开窗应用包构建和资源边界全部通过。没有削弱旧断言，CoreData XPC 环境诊断不替代最终 XCTest 汇总。构建／测试／打包运行时冻结全部项目文件，门禁后只补记文档。

本轮主日志 /tmp/typebar-inbox-final-readiness.log，完整原生及服务日志 /tmp/typebar-inbox-final-client-tests.log、/tmp/typebar-inbox-final-service-tests.log；唯一临时父目录 /tmp/typebar-inbox-gate.JcwZ5a。归档来自这次运行，不混用旧临时日志。初始红测、迁移反例与排序修正日志保留在 /tmp/typebar-inbox-routes-red.log、/tmp/typebar-inbox-recovery-red.log、/tmp/typebar-inbox-job-recovery-red.log、/tmp/typebar-inbox-order-red.log 及 /tmp/typebar-inbox-native-final-focused.log，后者是仍有一处差异的失败阶段，不作最终通过证据。

源码驱动和行为优先测试使配置、领取与区域排序基于实际源码而非页面猜测；会话内有界决策、风险和迁移复核促成两个独立托管标记及单 writer 边界，不是独立评审。界面设计复核保持原生列表，以等宽奖励条和明确待领取状态区分通知与信用；文档复核保留接口、目录和队列差异，不冒报整体兼容。

没有操作真实账户库、部署或修改系统时钟。单窗口布局、大字体、VoiceOver、原生异步网络实机交互、真实 Mongo／BullMQ、崩溃瞬间 fsync 及多 writer、长期规模、macOS 14／Intel、日榜奖励、premium、完整 PB 缓存和整体功能等价仍未验。不能用候选计算、HTTP 或源码探针通过替代这些验收。
