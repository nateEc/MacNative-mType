# 组合投影的真实字段与部分字形归属

## ASL 与 Choo 完整冻结复验（2026-10-10）

对原生提交 `a2235a1843fd3e7bd7da83e524c6d9f9982b0b1f` 执行唯一完整串行门禁，session 4802 终态退出 0；只读参考固定为 `91bd24bb8513785c7364cbea29296ff7adafac41`，保持干净。持久证据 `../../work/special-projection-readiness.Ijmz2B/` 保留 readiness.log、16 输入 frozen.sha256、中途与终态哈希检查、75 份日志及 228 张组件图。启动前、中途、末期与终态十六输入一致；终态后仅五份结果文档补记，不改变代码、测试、人工清单或门禁。

原生 4,092 项零失败零跳过（873.603 秒，墙钟 874.091 秒）；服务 501 项零失败零跳过（11.901 秒，墙钟 11.963 秒）。十万词耐久 153.769 秒，磁盘迁移十六项 9.386 秒（墙钟 9.389 秒）。字段 1,249 槽与十次缓存量测 0.139525 秒、改变候选配置 0.014623 秒，仅配置诊断，不代表 UI／设备 FPS。Core Data／XPC 诊断及刻意只读存储的 Code 513 失败诊断原样保留，未跳过或放宽断言。

新增六张 ASL／Choo 的 overflow、cancelled、return-extras 真实组件图均逐张复查；组件窗口不可见并关闭，Choo 捕获暂停旋转，不是完整 ContentView、实际系统 IME、动态动画或像素等价验收。未启动应用包、签名、资源边界与原创性检查通过；零 Typebar 主程序启动，终态零测试／编译进程残留。

53 表面、1,141 个唯一人工场景的结构、239 键盘布局及 446 语言检查通过；人工场景没有执行。94 配置仍 89 映射／4 部分／1 不适用，部分项为 compositionDisplay、tapeMode、showAllLines、fontFamily；主题精确映射仍 0／187（49 相关替代、138 无相关替代），挑战 57 映射／1 待映射。Choo 视口／行跟随、Tape 投影、方向／完整组合、真实 IME／VoiceOver／字体和设备性能仍开放，完整 goal active。本段替代下方 ASL／Choo 专项“完整门禁未重跑”的当前状态，不宣称整体功能等价。

## ASL 组合投影适配增量（2026-10-10）

普通 ASL 生产分支不再排除共享组合投影。实际 SwiftUI 手形／回退文字组件读取最终 `fieldRuns`，保留虚拟负 ID、分裂 canonical 关联、候选下划线和独立提示属性；词框、提交空白、退休字段及主 before／after 与 canonical pace 由实际槽框驱动。投影零宽槽保持自己的行／字段框，不借用前字段；投影显式缺失 caret 不恢复旧 canonical 跟随位置。无投影的既有路径保留。

结构 Return 来自原始字段元数据，边界位于整个容器（包括真实 extras）之后，不从显示字符推断；marked 溢出 Return 不产生目标结构换行。共用布局同步修复。Zen 最后空词占位可以位于目标范围数组之后，明确没有目标结构，不直接越界取数组元素。未改输入、计分、历史、持久化、pace 时钟或动画队列；没有新增计时器和产品依赖。

固定只读参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。核对完整更新／caret 函数及 ASL 配置和 CSS：上游仅更换字体、关闭 joining，没有独立 ASL 候选更新算法。本实现沿用原创原生手形，未复制 Gallaudet 字体、CSS、实现或资源，不宣称专业手形或像素等价。行为先行、源码核对、决策复核和根因调试约束了本次字段元数据／独立几何修复；本会话风险复核不等于独立审计。

持久证据 `../../work/asl-composition.OOXGsz/`：`red.log` 六测试十五处失败、`marked-return-red.log` 一测试两处失败；`first.log` 七新增通过后，既有 Zen 空占位测试真实越界崩溃（signal 5），修复后 `second.log` 52 项零失败；`zero-red.log` 一测试一处失败证明组合符借用前字段框。最终 `broad.log` session 99010 退出 0，820 项零失败（183.616 秒，墙钟 183.712 秒），其中九项新增 0.566 秒；没有跳过测试或隐藏失败重试。`originality.log` 边界检查退出 0。

三张 `asl-composition-overflow.png`、`asl-composition-cancelled.png`、`asl-composition-return-extras.png` 经离屏真实组件挂载后逐张检查，窗口始终不可见并关闭；不是完整 ContentView、系统 IME 或真机验收。候选溢出、取消的跨字段组合符、Return 后真实 extras 均保留各自槽；既有组件捕获同目录保留。零 Typebar 主程序启动。

本增量尚未执行完整冻结发布门禁，不能沿用下方 4,072／501 项结果代表当前修改。Tape／Choo 的全局投影适配、混合方向、ASL 组合 Tape 删除产生的匿名结构行、整体 RTL 排版、专业手形、真实 IME／VoiceOver／设备／字体和 UI 性能仍开放；配置 89 映射／4 部分／1 不适用不升级，主题与挑战缺口不变，完整 goal active。

## Return 与 Unicode 增量的完整冻结复验（2026-10-10）

对 `e349198829e0b60929b0b3fd2c07d6b5e24a8c40`（含前一 Return 增量）执行唯一完整串行门禁，session 57271 终态退出 0。持久证据为 `../../work/unicode-readiness.MknL9P/readiness.log`、`frozen.sha256`、`logs/`（75 份日志）及 `images/`（222 张既有组件图，不计新画面或实机 IME 验收）。十四文件在启动前、中途及终态哈希一致，门禁全程没有修改输入；终态后只在本合同、README、规范、功能盘点补结果，十个代码／测试／QA 冻结输入不变。

原生 4,072 项零失败零跳过（871.072 秒，墙钟 871.549 秒）；服务 501 项零失败零跳过（11.814 秒，墙钟 11.876 秒）。十万词耐久 154.236 秒，十六项磁盘迁移 3.376 秒；字段 1,249 槽与十次缓存量测 0.132208 秒，改变候选配置 0.014231 秒，仅配置诊断，不代表 UI／设备 FPS。系统／Core Data／XPC 诊断全部保留，未通过跳过或放宽断言消除；未启动应用包、签名、资源边界和原创性检查通过，零 Typebar 主程序启动、终态零测试／编译残留。

固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 干净不变；53 表面、1,139 人工清单结构、239 布局、446 语言及固定源函数对照通过。人工清单未执行，94 配置仍 89 映射／4 部分／1 不适用，主题精确映射 0／187（49 相关替代、138 尚无相关替代）、挑战 57 映射／1 待映射不升级。真实 RAF／DOM、非 BMP 整批事件、融合排版、其余呈现字段适配、实机 IME／VoiceOver／字体与 UI 性能仍开放；完整 goal active。本段替代下方专项阶段“完整门禁未重跑／待补”的当前状态，不以门禁成功宣称整体功能等价。

## 准入探针的 scalar 槽数与 UTF-16 临时单位

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的完整 `updateWordLetters` 按 `Strings.splitIntoCharacters`（for-of scalar）生成已输入／待输入 letter，完整 `getActiveWordTopAndHeightWithDifferentData` 却从实际 DOM letter 数开始索引候选 UTF-16 单位。这两个单位不能合并为 UTF-16 长度或原生 grapheme 数。原生准入现按活动字段目标／接受输入的 scalar 数计算已有槽数，仍逐 UTF-16 单位追加临时槽；旧单 Text 回退也逐单位解码，不能把两临时 surrogate 槽重新融合为 emoji。控制换行／SPACE 插入点、候选隔离、接受／计分／回放／归档协议不变，没有新增运行时依赖。

QA 只读执行完整原版更新、caret 与上述探针；八输入×两模式×三组合风格的 48 例，实际源槽数、临时节点 textContent UTF-16、追加顺序及全部移除均有断言，几何为自有受控绑定，不宣称浏览器字体／像素。原生对照限定普通模式 replace 组合风格、typo off 的八例，六宽度×两方向共 96 组，使用真实原生布局和原版给出的临时单位；组合／ZWJ 的原生 baseline 仍不是原版 scalar 排版。上一批 72 组实际接受副本几何对照中，emoji 例移入独立测试：现在明确断言最终接受渲染可容纳，但原版临时探针仍增高拒绝；其余五例 60 组继续对照，未删除 emoji 覆盖或放宽原版断言。

持久证据 `../../work/unicode-probe.lxVnkO`：`red.log` 一项 17 断言失败，证实 emoji／ZWJ／已有 astral extra 的槽数及几何错误；`first.log` 30 项四失败，仅为旧“探针等于最终渲染”的 emoji 假设。`legacy-red.log` 与 `legacy-emoji-baseline-red.log` 是不能区分旧／新的成功夹具，不算 red；实际字体单独检查后，用两种文字宽度的中点构造 `legacy-derived-width-red.log`，一项一失败证实回退路径 surrogate 融合。`verified-focused.log` 最终 32 项零失败零跳过（4.355 秒，墙钟 4.359 秒）。扩大回归／原创性结果待补，完整门禁未重跑；本批零主程序启动，无新截图。

最终 `broad.log`：798 项零失败零跳过（189.352 秒，墙钟 189.456 秒），使用上一批持久 QA 动画归档，含本批三个新增测试。`frozen.sha256` 十文件在启动前、中途及终态复核一致；终态后仅四文档补结果，六个代码／测试／QA 输入未变化。`originality.log` 退出 0；零 Typebar 主程序启动、终态零测试／编译残留。1,249 槽量测 0.136242 秒、候选改变配置 0.015218 秒，仅诊断，不代表 UI FPS。首轮失败与不能区分的夹具均保留；上述“待补”由本段取代，但完整门禁仍未重跑。

有界本会话复核保留源混合单位的可观察行为，不以较自然的最终排版替代原版探针；只有活动字段只读计数改变，没有改输入事件顺序或持久化。仍开放：真实 DOM／RAF 尚未刷新时的节点数、非 BMP 事件整批与原生逐单位准入的边界、融合／ZWJ／孤立 surrogate 的全部源排版、隐藏词界与 stopped preview 全组合、混合方向和其余呈现、实机 IME／字体／VoiceOver／性能。94 配置 89／4／1、主题与挑战缺口、人工验收不升级，完整 goal active；下方为历史。

## Return 字段容器与错误输入归属增量

依据固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 `buildWordHTML` 与完整 `updateWordLetters`：Return 是词容器内的 letter，结构换行在整个容器之后，不能把后续 extras 提前移到下一行。普通原生字段现将边界放在最后一个槽之后，独立槽／连接文字及整体 RTL 共用该规则；移除字段的既有结构行计数不变。

旧导航会把 `aa\n` 上的 `aax` 关联为未输入 Return 加 extra x；实际原版只有三个 letter。新的只读显示纠正使用真实字段输入，将 x 关联为 Return 的错误输入并抑制重复 extra，真正后续 y 保留。提交空格后旧记录可能把空格关联到 Return，历史字段同样以实际输入纠正。接受文字、计分、导航、回放、存储与协议不变；没有 LF 的提示快速跳过纠正。隐藏／未分段／Zen 边界不使用该纠正；融合 extra 无法确认 scalar 归属时不猜测。

持久证据位于 `../../work/field-return.RWlg29`。`red.log`、`return-ownership-red.log` 记录早换行与重复槽反例；`history-return.log`／`history-diagnostic.log` 记录已提交字段重复 extra 的失败和真实关联。`source-return.log` 88 项零失败零跳过，但在历史路径修正之前，不代表最终版本。新增 QA 原版探针为四输入×两模式×三组合风格的 24 案例；实际原生会话对照限定普通 replace 组合风格、typo off 的四例，逐槽核对文字 UTF-16、marked 与正确性，不扩大为全部风格／浏览器像素或真实 IME 等价。

`broad-return.log` 首轮 795 项、7 跳过、29 断言失败（含 14 unexpected），原因是未提供锁定 QA 动画归档；不计通过。随后用 QA 专用 `animejs-4.2.2.tgz` 补齐原版动画运行环境，不修改产品依赖或断言，最终结果另记。本批零 Typebar 主程序启动，无新截图；完整门禁未重跑，上一批 4,064／501 只适用于上一冻结版本。

最终 `broad-return-locked-runtime.log`：795 项零失败零跳过（181.655 秒，墙钟 181.742 秒），其中字段布局新增三项、输入准入新增一项、原版逐槽对照新增一项。1,249 槽加十次缓存量测 0.142357 秒、候选改变配置 0.015352 秒，仅原生配置诊断，不是完整 UI FPS。`originality.log` 退出 0；终态零主程序／测试／编译残留，终态后仅 README 和本合同补结果。首轮失败日志保留，不以环境补齐后的成功覆盖。全部检查均不是独立第三方审计。

仍开放：非 BMP／融合 extra、隐藏边界、逐词 broken-joining、混合方向、其余呈现的字段迁移、真实 IME／VoiceOver／窗口设备与 UI 性能。人工清单不升级为已验收，主题精确映射和整体功能兼容性缺口不变；完整 goal active。下方为历史阶段，仅上述限定范围被本段替代。

## 普通字段输入准入接线增量

普通 LTR／整体 RTL 路径的生产准入现在以 `composition: ""` 生成候选为空的真实字段投影，而非 `nil` 禁用投影。`PromptInputWrapGeometry` 在存在字段 map 时使用与生产文字、光标、跟随及视口同一个 `PromptFieldTextLayout` 构造入口；无 map 的混合方向保留旧量测，其余三呈现仍按原门控不启用此准入。传入实际字号、行距、整体方向和连接文字标志，宽度仍来自已挂载的弱视图；不改计分引擎、准入资格、输入顺序、回放、存储或协议。

探针只复制字段 run，按现有 UTF-16 资格计算缺少的单位，追加临时槽而不接收输入、不加入 IME marked 内容；commit SPACE 保持在墨迹外，目标 Return 与已存在 extras 的顺序不被重排。前后活动字段框只比较 top 或 height 是否增长，位置和关联不写回原快照。字段布局新增 run 构造入口，map 入口委托给它，避免造出范围与文字不一致的临时 map；前后量测复用不可变框，未增加缓存历史链、计时器或窗口。平台入口在主 actor，同步调用；portable engine 未增加 actor 依赖。

固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41` 中完整 `onBeforeInsertText` 与 `getActiveWordTopAndHeightWithDifferentData` 已复读：仅必要增长进入昂贵量测，按输入单位追加临时 letter，并拒绝 top／height 增长。复读独立槽、joining-script、结构换行规则；复用已安装 Swift 6.2.4／SDK 26.2 和现有 AppKit 接口，无新产品依赖或复制原版代码／资源。行为测试和根因追踪约束真实反例，本会话有界复核覆盖候选／计分隔离及字段顺序／字体度量，不是独立审计。

证据位于 `../../work/field-readiness.wiQBed/field-admission-*.log`：`red.log` 两项一处预期失败，证明已经在下一行的 `bb` 仍被旧全局量测错误拒绝；`first.log` 55 项无失败但一项缺参考环境跳过，不计完整覆盖。`expanded.log` 62 项两失败：Return 夹具假定错误的槽数／顺序，并暴露初版探针在 Return 前插入导致与实际呈现不符；`diagnostic.log` 保留真实槽顺序 `a,a,Return,x`，以及阿拉伯字段后加拉丁字符的原生行高 31→35 点。探针改为保留实际顺序；Return 在 3.2 列宽追加一个字符不增高、追加三个增高，拉丁 fallback 增高需拒绝、同脚本追加不增高需接受，分别独立验证。

`corrected.log` 62 项零失败零跳过；`native-oracle.log` 十新增零失败，包含六种输入×六宽度×两方向的 72 次与实际不限准入输入副本的前后渲染对照。最终 `final-focused.log` 63 项零失败零跳过（3.594 秒，墙钟 3.601 秒），含十新增；既有 456 条完整固定源资格／助手对照保留，不把受控 DOM 度量当浏览器像素证明。批量可容纳 extras 接受、超高输入拒绝且不进入指标／回放、退休、Return、无效宽度、无增长、RTL、连接文字及生产空候选接线均有证据。本批无新截图、零主程序启动；完整冻结门禁结果待补，尚未提交本增量。

最终完整门禁 session 11679 退出 0，替代上段专项阶段“待补”的状态；持久证据位于 `../../work/field-admission-readiness.xU4ebM` 的 `readiness.log`、`frozen.sha256`、`logs/`（75 日志）、`images/`（222 既有组件图，本增量没有新画面）。十文件启动前、中途与终态哈希一致。原生 4,064 项零失败零跳过（863.547 秒，墙钟 864.011 秒），服务 501 项零失败零跳过（12.624 秒，墙钟 12.689 秒），十新增 0.255 秒；十万词 151.400 秒、十六磁盘迁移 5.252 秒。字段 1,249 槽诊断 0.143730 秒，改变候选配置 0.014657 秒，不代表 UI／设备 FPS。53 表面、1,139 人工场景结构、固定源码对照、元数据、未启动包／签名／资源及原创性边界均通过；参考 pin 干净未变。系统诊断保留，零 Typebar 主程序启动、终态零测试／编译残留；终态后仅合同、README、规范和功能盘点补结果，其余六个冻结输入不变。

**仍开放**：上述是同原生字段几何，不是原版 CSS 精确等价；Return／extras 呈现顺序与源 DOM 的完整一致性、非 BMP 新增 extras 的 UTF-16／scalar／grapheme 差异、逐词 broken-joining、混合方向、其余三呈现、实际 IME／VoiceOver／设备／字体恢复／大题目 UI 性能仍需继续。新测试覆盖的是目标含 emoji／组合符时追加 BMP 字符或组合符，不宣称已覆盖新增 surrogate pair 的独立临时槽。人工场景只登记未执行，94 配置 89／4／1 不升级，主题精确映射 0／187、挑战 1 项待映射，完整 goal active。下方均为历史，旧“准入仍全局量测”的描述仅本段范围被替代。

## 普通原生字段与独立槽布局增量

上轮普通单一 Text 的跨字段再融合反例现由实际 `PromptFieldPracticePrompt`／`PromptFieldNativeView` 替代路径处理。共享投影新增按实际归属排列的 `fieldRuns`，不从拼接后的 grapheme 猜字段，不插入分隔 Unicode，不重复 offset。普通 LTR／整体 RTL／Zen 使用独立字段及槽字框；连接文字仅在字段内共同塑形。Tape／ASL／Choo 全局候选适配和混合方向仍未迁移，不能计四呈现完成。

`PromptFieldTextLayout` 使用已有自有原生流布局与 AppKit 字体／颜色准备；非连接文字按槽独立测量／绘制，连接文字按字段内段保留塑形，真实 Return 分段，独立删词保留精确匿名结构行。提交 SPACE 不属于词墨迹；整词换行、超长词的完整外层分配、软换行空白跟随与 RTL 外层位置共用实际字框。提示独立绘制且预留末行空间，不扩大槽、字段或 pace 的墨迹；零 advance 的组合符仍绘制，不强塞假宽度。

同一份几何驱动文字、主 before／after、canonical pace 首／末关联、字段行跟随与自定义视口行高。首次 pace 动画从第一个真实保留槽开始；fresh provider 在候选重排时同步使主／pace 几何失效，不等 SwiftUI 下一次配置，未改变 pace 时钟与队列算法。停止时清空滚动上下文、取消通知和既有子控制器，新增 owner 无计时器、无应用启动。原生辅助功能仅登记 staticText 与共享文本，不作为 VoiceOver 实测。

缓存仅复用内容、字体、方向、间距和宽度匹配的不可变文字／度量；位置、分组、字段身份、canonical 关联与锚点每个快照重新计算，不缓存虚拟 ID 的跨快照语义，也不保留历史模型链。复用结果与全新布局逐框对照，退休后组号变化及宽度／RTL 变化不污染旧快照。最终专项中 1,249 槽首次配置加十次缓存量测 0.153050 秒，改变候选后的原生配置 0.014284 秒；不含完整 formatter／SwiftUI 重建、实机绘制或 FPS，首次成本与大题目 UI 性能仍须优化和验收。

固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`，Swift 6.2.4／macOS SDK 26.2、最低 macOS 14。复读完整 `updateWordLetters`、`.word letter` 独立 inline-block、joining-script 字段内 inline、词换行和提示规则；已安装 SDK 确认 NSViewRepresentable sizeThatFits 在 macOS 13 起可用，文字绘制和量测复用仓库已使用的原生 API。行为测试与根因追踪驱动修复；源码核对、有界本会话三次实质复核分别约束字段／槽塑形、身份与几何边界、不可变缓存，非独立审计，后续仅处理具体风险反例。没有复制上游产品代码、CSS 或资源，也没有新增产品依赖。

`/tmp/typebar-field-layout-red.log` 两项两处预期失败：组合符／区域旗帜字段都落在前字段的 x=0 字框；独立布局后通过。`policy-red.log` 五项三处真实失败定位到 canonical 关联缓存、软换行 SPACE 和不重建文本时的视口行数通知；`policy-green.log` 五项通过。`expanded.log` 十六项两处失败分别为匿名空行默认字号，以及未隔离 AppKit 自动释放池的释放测试；显式当前字号及按既有测试惯例隔离池后，`height-red.log` 十七项仅余末行提示内容高度 33 小于 51.816 的真实反例，预留空间后通过。`pace-red.log` 单项两处断言确认首段 pace 直接跳终点；`fresh-pace-red.log` 单项两处断言确认新候选重排未同步移动未变序号的 pace。两者修复后，最终 `/tmp/typebar-field-layout-verified-regression.log` 537 项零失败零跳过（62.584 秒，墙钟 62.642 秒），含 21 项新增字段测试（0.818 秒）；上述简写日志均为 `/tmp/typebar-field-layout-` 前缀，失败轮不覆盖。

五张新图在 `/tmp/typebar-field-layout-focused-images.bA8GsQ`，文件为 `composition-fields-fused-cancellation.png`、`composition-fields-regional-boundaries.png`、`composition-fields-slots-hint.png`、`composition-fields-wrapped.png`、`composition-fields-joining-rtl.png`；实际生产字段组件经 NSHostingView 挂载，窗口不可见且关闭，不是完整 ContentView 或实际系统 IME。新图中跨字段组合符与区域标志不再共用前字段框；单区域标志采用系统字体的独立字形，不冒充国旗资源。自有 palette／hint 夹具并非完整主题。旧三张单 Text 诊断图现在是旧组件对照，不代表新的普通生产路径。

**仍未完成**：输入准入依旧显式传 `composition: nil` 并用旧全局文字量测，必须迁移到同一真实字段几何且保持候选隔离；连接文字 dots 等逐词 broken-joining 策略、其余三呈现、混合方向、任意滚动／动画队列、字体恢复、原版混合 UTF-16／scalar 差异、真实 IME／窗口／VoiceOver／设备与 UI 性能均保持开放。原生边界和组件图不能宣称浏览器 CSS 像素等价。94 配置仍 89 映射／4 部分／1 不适用，完整 goal active。下方为此前阶段历史，仅此段范围替代普通单 Text 的旧几何缺口。

### 持久证据复验（2026-10-09）

此前 `/tmp/typebar-field-layout-*` 日志、图与冻结清单在续跑时已不存在，不能以会话摘要代替当前可复核证据。本次未改动产品代码或测试，重新冻结十一文件并执行唯一完整门禁 session 33772，退出 0。持久证据目录为 `../../work/field-readiness.wiQBed`：`readiness.log`、`frozen.sha256`、`logs/` 下 75 份日志及 `images/` 下 222 张组件图。启动前、中途与终态十一项哈希均一致；终态后仅本合同、README、规范与功能盘点四文档补记录，其余七输入不变。

原生 4,054 项零失败零跳过（855.222 秒，墙钟 855.661 秒），服务 501 项零失败零跳过（10.585 秒，墙钟 10.639 秒）；新增字段 21 项 0.775 秒，十万词 152.773 秒，十六磁盘迁移 9.191 秒。1,249 槽加十次缓存量测 0.132289 秒，改变候选后的原生配置 0.014082 秒，仅诊断，不代表完整 UI 或设备 FPS。上述五张字段图已从持久目录重新逐张查看；系统／CoreData 诊断保留，未通过跳过、重试或放宽断言消除。

只读参考 pin 干净未变；53 表面、1,138 人工场景结构、94 配置 89／4／1、未启动包／签名／资源及原创性边界均通过。隔离 QA Redis 6.2.6 从官方版本归档重建，现代 SDK 使用 `REDIS_CFLAGS=-DMAC_OS_X_VERSION_10_6=1060` 选择原有 `fstat`／kqueue 分支；归档、构建日志与服务程序位于 `../../work/typebar-qa-runtime`，未改本机 Redis 服务或产品依赖。零 Typebar 主程序启动，终态零测试／编译残留。人工场景仅结构检查，主题精确映射仍 0／187、挑战 1 项待映射；输入准入及前述未完成项保持开放，完整 goal active。

## 普通呈现的最终属性与光标接线增量

本增量把 `PromptCompositionPresentation` 接入普通生产 `ContentView.renderedPrompt` 的 LTR／整体 RTL 路径（含 Zen），不再把整段候选塞进一个当前字形。Tape／ASL／Choo 与原先混合方向回退仍走既有共享渲染，不能计作四呈现完成。普通渲染在候选更新及取消时生成全局槽；既有颜色、typed effect、错误提示、控制字符和源字段 phase 继续由原生策略负责。候选不是已完成输入，不参与 dots／hide 的完成集合；marked 下划线与匹配颜色分开。`.below` 的独立候选条保留。

新增 `PromptCompositionTextMap` 保存每槽完整属性、完整 UTF-16 范围及不含提示／结构 Return 的 inkRanges，另存 canonical 一对多关联和派生的字段字符坐标。旧 character offsets 只是旧调用者的便利，不作为新槽的身份目录。普通主光标使用显式 before／after 锚点，pace 仍取 canonical 关联的首／末槽；TextKit 直接测量 UTF-16 墨迹，不再把 hint 或结构换行当正文框。before 提交空白保留既有软换行跟随策略，after 候选不借下一词的框。普通行跟随改用实际字段 ID／派生坐标；这不是实际字段独立框布局。

融合片段的状态与词错误从实际接受字段单位及 forced flags 读取，不能继承跨字段 canonical 整字形错误。pending／隐藏片段、记忆模式遮蔽、真实空词与提交 SPACE 的范围保留；独立移除字段保存精确 Return 数量，不把多次换行压成一个布尔值。输入准入明确调用 `renderedPrompt(for: current, composition: nil)`，继续使用不含候选的既有准入表示；本增量没有修改准入、导航、计分、回放、存储或协议算法。

Swift 6.2.4／macOS SDK 26.2、最低 macOS 14，固定只读参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。主代理完整复读固定 `updateWordLetters` span 与 `.dead`／highlight-off 样式，复用已有原生 AppKit／TextKit 接口；不复制产品源码或资源。行为测试、源码驱动及本会话有界复核分别约束身份、属性和几何；三次实质复核聚焦融合范围、片段状态、hint／Return 框，非独立审计，之后仅修具体风险反例。

十九新增测试覆盖最终属性／接受提示、拼接后重新融合但独立的 UTF-16 范围、三种样式、字段状态与 forced errors、主／pace ink、软换行、记忆遮蔽、SPACE、Return 精确数量、Zen 控制／占位、实际 TypingInputView marked 更新／取消、整体 RTL block after／取消与 fresh provider，以及普通生产路径和准入的静态接线检查。测试 factory 提供自有颜色／提示；真实组件是 NSHostingView Text 与原生 caret，不把它等同于完整 ContentView 挂载或实际系统 IME。现有 132 常规／36 Unicode／15 字段的完整源码对照继续保留，未新增源码夹具数量。

初始 `rendering-initial.log` 因新 API 缺失编译失败，不是行为红测。`rendering-first.log` 八项六处失败中的 `.both` 预期和随机 `.words` 构造为测试错误；修正后 `rendering-fixture-verified.log` 八项两处真实失败定位到接受片段被误判、重复 hint，按实际字段单位修复。`rendering-ink-red.log` 十项两处预期失败：hint 把 pace 框扩成 48 点，Return 把 after 光标推到 400 点容器右缘；独立墨迹范围修复。`rendering-policy-red.log` 十五项六处失败，修正隐藏、字段错误、SPACE 范围、软换行和准入静态接线。`rendering-policy-green.log` 67 项零失败但一项源环境跳过；不冒充最终全覆盖。

单项 pace 首次墨迹量测 18 点、第二次 21 点的差异，在任何视图创建前两次相同 TextKit 调用即可复现；NSApplication 初始化未解决，内部原因未查明，不宣称平台缺陷已修。`rendering-pace-isolated/range/appkit/diagnostic/repeat.log` 均保留。最终该测试验证精确 1 单位的 ink range、同一环境下完整含提示框大于墨迹框以及真实 pace 等于墨迹框，仍能捕获旧完整框错误；不以首次调用字体度量恒定为合同，也没有重试或跳过。`rendering-structure-red.log` 的额外两处颜色 wrapper 比较、一个已结束会话构造为测试问题；按既有允许移除未来词的案例重构后，`rendering-structure-verified-red.log` 十九项一处真实失败确认两个 LF 丢成一个，再改为精确计数。本段简写日志均以 `/tmp/typebar-composition-` 为前缀。

最终 `/tmp/typebar-composition-rendering-final-regression.log` 444 项零失败零跳过（41.578 秒，墙钟 41.621 秒），十九新增 0.079 秒。三图位于 `/tmp/typebar-composition-rendering-focused-images.3W6m5R`，文件为 `composition-normal-slots-hint.png`、`composition-normal-overflow-after.png`、`composition-normal-fused-cancellation.png`，已逐张查看；截图仅为离屏组件，无主程序启动。

**第三张图证实仍未完成的几何限制**：普通单一 Text 拼接会再次把组合符合到前字，颜色／光标仍受融合字框塑形影响；独立 UTF-16 身份不是原版独立字段布局等价。旗帜、组合符跨字段的源外观和边界 caret 仍须实际字段框／槽布局解决，不能靠重复 offset、插入假分隔符或绿测宣称完成。Tape／ASL／Choo 全局槽适配、混合方向 fallback、实际 IME／窗口／VoiceOver／设备、完整滚动队列、字体恢复与 UI 性能继续开放。94 配置 89 映射／4 部分／1 不适用，完整 goal active；下方均为此前阶段历史。

本增量最终十二文件冻结清单 `/tmp/typebar-composition-rendering-final-frozen.sha256` 在启动前、中途及终态全部一致。唯一完整门禁 session 32192 退出 0，主日志 `/tmp/typebar-composition-rendering-final-readiness.log`；原生 4,033 项零失败零跳过（933.750 秒，墙钟 934.248 秒），服务 501 项零失败零跳过（13.110 秒，墙钟 13.180 秒）。十九新增呈现测试 0.154 秒、十万词耐久 159.999 秒、十六磁盘迁移 5.003 秒；耐久不证明新 UI 性能。固定源码对照、元数据无漂移、53 表面、1,136 人工场景结构、94 配置 89／4／1、未启动应用的包／签名／资源与原创性边界均通过；人工结构检查不是人工执行，主题精确原生映射仍为 0／187，挑战仍有 1 项待映射，不把门禁通过当成整体功能等价。74 日志保留在 `/tmp/typebar-composition-rendering-final-logs.ORWE4y`，217 组件图在 `/tmp/typebar-composition-rendering-final-images.Q17VC1`；其中三张新普通候选图已逐张复查，融合取消缺口仍如上所述。系统／CoreData 诊断及失败轮保留。参考 pin 干净未变，零主程序启动、终态零测试／编译残留；终态后只在本合同及 README／规范／功能盘点四份文档补结果，其余八个冻结代码／测试／人工清单输入不变。完整 goal active。

## 全局组合身份投影增量

本增量新增纯原生、只读 `PromptCompositionProjection`。`PromptCompositionField` 同时保留显示切片的全局 UTF-16 范围、完整源单位与权威字段目录；旧 ends 转换为单位边界，Zen 使用实际接受字段起点，没有可信目录的隐藏文本明确为一个 unsegmented 字段。会话不接受候选、不改变计分、导航、回放、结果、存储或协议。

呈现 ID 与 canonical glyph ID 分开：整字形替换可以保留原 ID，融合字段拆片、多字形组成的字段字符及候选溢出使用互不重复的负 ID。负 ID 只在当前快照内有效，不作为持久或跨快照身份。`canonicalAliases` 是独立的一对多关联，不向文字 offset 字典塞重复键；`sourceSlices` 保留原始单位片段，`sourceFieldIndex` 不从解码后的 grapheme 或词框猜测。真实接受 extras 优先按输入缓冲的字段起点归属；未知归属显式 nil。退役／独立移除仅过滤相应字段片段，空字段目录与结构 Return 元数据保留。

主光标明确记录某呈现槽之前或最后候选之后，reference UTF-16 caret 坐标独立于原生字段 grapheme。取消时按真实活动字段找回目标片段，不能依赖可能因融合而缺失的旧 canonical caret。Zen 候选期间隐藏尾部光标占位符，取消恢复；已结束会话返回 nil。`displayUTF16` 是身份／候选墨迹投影，**不是完整的已输入错误替换、hint 或最终 attributes**；禁止直接代替生产 renderer 的属性文本。

十七项新模型测试覆盖多槽、三种样式、溢出、接受 extras、真实空字段、重音／旗帜跨字段、普通 SPACE 融合、Zen、控制结构、取消、旧 ends／flat、回删／重开／结束、实际退休／删词、lone surrogate 和全空目录。现有完整源探针保持 132 常规／36 Unicode／15 字段案例，追加实际 `updateWordLetters` marked 输出；新增一项 XCTest 比较全局候选文本、归属、唯一身份与 reference caret，并仅在 ASCII 目标下比较单位一致的正确性。探针仍使用自有事件快照、DOM／RAF／cache 绑定，未执行这些案例的源码插入／导航、浏览器布局或系统 IME。不得把十五组夹具计作十五项 XCTest。

首次 `/tmp/typebar-global-composition-initial.log` 为新 API 不存在及一个测试方法名误用的编译失败，不是生产行为红测。首轮实现 `/tmp/typebar-global-composition-first.log` 共 36 项、两处失败，均为融合字段取消时旧 canonical caret 为 nil；按字段目标单位定位后，`/tmp/typebar-global-composition-caret-green.log` 36 项零失败（0.080 秒）。扩展 `/tmp/typebar-global-composition-source-regression.log` 44 项两处失败，是测试把停止输入后的接受文本误当成原始提交；改为保存投影前接受文本及原始字段快照并验证不变，未修改生产输入语义。最终 `/tmp/typebar-global-composition-verified-regression.log` 66 项零失败零跳过（8.242 秒，墙钟 8.249 秒），含十八新增及相关字段、计划、源码与退休回归。

行为测试、有界决策复核、源码驱动和风险检查共同约束实现。本会话三次有界复核关注身份融合、取消 nil caret、原始输入／退休边界；非独立审计。没有重用上游产品代码或资源，JS 仅用于 QA 对照。本轮零 Typebar 主程序启动，测试串行无编译重叠。

十文件冻结清单 `/tmp/typebar-global-composition-final-frozen.sha256` 启动前、中途与终态逐项一致。唯一完整门禁 session 46964 退出 0，主日志 `/tmp/typebar-global-composition-final-readiness.log`；原生 4,014 项零失败零跳过（951.350 秒，墙钟 951.839 秒），服务 501 项零失败零跳过（11.764 秒，墙钟 11.825 秒）。十万词耐久 185.908 秒，十六磁盘迁移 4.976 秒，17 项新模型 0.016 秒、四项源对照 0.730 秒；不作新增投影 UI 性能证明。固定源码探针、元数据无漂移、53 表面、1,134 人工场景结构、94 配置 89／4／1、未启动应用包／签名／资源与原创性检查通过。结构通过不表示人工执行。74 日志保留于 `/tmp/typebar-global-composition-final-logs.WIhk2c`，214 既有组件图在 `/tmp/typebar-global-composition-final-images.llEax3`；本轮无新组合 UI 图、未作新图复查，不冒充生产接线或 IME 证据。CoreData／系统诊断及首轮失败日志保留。终态固定参考 pin 干净且未变，零主程序、测试、编译器残留；终态后仅四份文档补结果，其余六个冻结代码／测试／探针输入不变。

**仍未接入普通／Tape／ASL／Choo 生产呈现。** 下一阶段须统一最终属性、UTF-16 渲染范围、字框和字段几何、before／after 主光标、canonical pace 别名、滚动／退休与字体恢复。不能把部分片段拼接后的新 grapheme 边界冒充源槽位，也不能用重复 offset 伪造身份。原版混合 UTF-16／scalar 与原生 grapheme 的 Unicode 差异、UI 性能、实际系统 IME、模式和设备验收继续开放。94 配置仍 89 映射／4 部分／1 不适用，完整 goal active。下方保留此前字段阶段的验收历史。

固定只读源码 `91bd24bb8513785c7364cbea29296ff7adafac41`，独立原生实现，Swift 6.2.4／macOS SDK 26.2，最低 macOS 14，QA Node 22.22.1。本增量继续 [组合模型](COMPOSITION_PROJECTION_CONTRACT.md)，不缩减完整重写目标。**仍未替换生产渲染**：不能将字段读取和模型初始化称为普通／Tape／ASL／Choo 接线，也不代表真实系统 IME 已验收。配置仍为 94 项中的 89 映射／4 部分／1 不适用，goal active。

## 必须保留的身份

现有 `promptWordPresentations` 的 grapheme 范围不能表达所有真实字段：去空格后的相邻词会融合重音或旗帜；普通文字的空格与随后组合符也可属于同一 grapheme。通过整个已输入文本分词、用 caret 推断活动词、或把局部字形编号直接当全局 ID，都会错占相邻字段。真实空隐藏词必须与尚未生成的未来空尾区分。

新增只读 `TypingSession.promptCompositionField`：读取实际接受单位缓冲的活动 index／inputUTF16，保留不完整 surrogate；终末 element 已清空时不暴露旧验证输入。旧会话仍用已有真实词尾边界，不因缺少新目录丢掉字段；没有任何可信词界时才标为 unsegmented，不猜语言分词。Zen 只返回当前字段且不创造 target ID；已结束尝试返回 nil，回删与重开自然重新计算，不缓存候选。

`PromptCompositionField` 的 `targetUTF16` 是显示目标而非改写验证目录：与完整 Words.push 相同，尾部一个 SPACE 是提交间隙，Return 仍在显示目标中。`TargetGlyphSlice` 分别记录 fieldUTF16Range、glyphUTF16Range、canonical glyphID 和完整字形单位数；`isWholeGlyph == false` 仅表示关联，**不允许 renderer 覆盖整个 canonical 字形**。例如隐藏词 `a`／`◌́b` 的后词先关联 glyph 0 的后半，旗帜后词可横跨一个旧字形的后半与另一个完整字形；不能把切片一一当作字段字符。

`PromptCompositionPlan(field:composition:style:)` 将真实字段接到上一阶段原生模型；其 native grapheme 坐标与 reference UTF-16 坐标仍分开。输入的原始数组不会因显示解码变成 replacement unit；但既有模型对解码后 grapheme 的候选布局不是未配对单位／跨字段融合排版的完整源等价。本次不改变输入导航、计分、回放、归档、协议或生产渲染，也不把这些差异藏进已完成状态。ASCII 读取按需构造只读单位目录，尚无新 getter 的大规模 UI 性能证明；不把输入耐久计时当其基准。

## 行为与源码证据

十四项新 `PromptCompositionFieldTests` 覆盖不完整提交后字段、接受 extras、Return／空提交、隐藏词、真实空词、融合重音、跨词旗帜、普通空格融合、严格领先 LF 保留、lone surrogate、Zen、无目录 flat、旧词尾目录、终末清空、回删与重开。读取和建模不会接受候选，原有错误与结果原始单位仍由引擎拥有。

现有 QA-only 完整源码探针扩展十五组字段案例：运行完整 Words、events/helpers、events/data、word-update span 和 caret 模块；真实 getCurrentInput 从自有种下的输入事件快照读取，实际 Words.display 与更新／caret 的单位输出进入 Swift 对照。DOM／RAF、cache 回调、配置、活动 index 与输入快照明确为自有适配；**未执行这些新案例的插入／导航／生成、live-cache 数学、浏览器布局或真实 IME**。上一阶段 132 常规与 36 Unicode 案例保留。本轮新 source test 直接比较真实原生会话生成的 index、原始目标／输入数组和 reference caret 单位；不把多组夹具算成多项 XCTest。

先写新 API 测试的 `/tmp/typebar-composition-field-initial.log` 因成员尚不存在编译失败，不是生产缺口的行为红测。首轮十一项通过，`field-first.log`（0.013 秒）。第二轮同会话有界复核发现旧 retained ends 被误标 unsegmented，`field-legacy-red.log` 两项中一项六处预期失败（0.669 秒），保留真实旧边界后 `field-regression.log` 104 项零失败零跳过（0.730 秒）。第三轮完整 Words 对照发现隐藏词尾 SPACE 的显示规则错误，`field-display-space-red.log` 两项中一项一处预期失败（1.232 秒）；修正显示切片而不改验证目录。

源码扩展初次 `/tmp/typebar-composition-field-source-check.log` 因完整 Strings 与 events/data 的 `__testing` 同名声明冲突而失败。只隔离 data 模块的词法作用域并暴露所需函数，不删除／改写原函数，`field-source-verified.log` 后通过。根因调试检查了实际两处声明，非关闭测试或忽略错误。扩展源对照中途 `field-source-regression.log` 105 项通过（0.793 秒）；最终 `field-final-regression.log` 152 项零失败零跳过（1.032 秒），包含十五新增与相关组合／空词／停止输入／终末重入／词布局／控制结构回归。本段简写文件均以 `/tmp/typebar-composition-` 为前缀。

三轮有界决策复核均为本会话检查，非独立审计；最强反例为融合字段、旧边界丢失与隐藏 SPACE，均保留证据和结果，停止继续形式化复核。四 renderer 的全局 cells、字段拆片、候选／pace 分离锚点及退休／字体恢复仍需实际接线与验证，不因模型绿测改动原始目标。

提交前风险检查进一步发现读取时以 units.isEmpty 判断“未构建目录”，会丢掉没有旧 ends 的真实全空隐藏词目录。`/tmp/typebar-composition-field-empty-catalog-red.log` 两项中原生空目录一项一处预期失败（总 1.273 秒）；源全空夹具因自有构造还带旧 ends 已通过，不能称同一反例已被源码测试捕获。按已有 sourceStatsTargets 的 fields.isEmpty 语义只修读取判断，保留空目录，`field-verified-regression.log` 152 项零失败零跳过（0.975 秒）。源字段夹具最终十五组，XCTest 数量未增加；本次为风险检查发现的具体缺陷修复，不开启第四轮形式化决策复核。

## 冻结验收与下一阶段

十文件冻结清单 `/tmp/typebar-composition-field-final-frozen.sha256` 在启动前、中途和终态逐项一致。唯一完整门禁 session 18230 终态退出 0，主日志 `/tmp/typebar-composition-field-final-readiness.log`。原生 3,985 项零失败零跳过（878.808 秒，All tests 墙钟 879.260 秒），服务 501 项零失败零跳过（11.963 秒，墙钟 12.023 秒）；新字段十四项 0.014 秒、源码对照三项共 0.495 秒。十万词耐久 152.917 秒、十六磁盘迁移 5.015 秒通过，不作为新 getter UI 性能或优化证明。

固定源码探针、元数据再生成无漂移、53 表面、1,132 唯一人工场景结构、94 配置 89／4／1 分区、未启动应用包的构建／签名／资源与原创性边界检查通过。结构检查不是 1,132 场景人工执行。74 日志保留于 `/tmp/typebar-composition-field-final-logs.prDbqW`，210 既有组件回归图保留于 `/tmp/typebar-composition-field-final-images.ziMfvM`；本次未增加或查看新组合 UI 图，不能当生产接线证据。原 CoreData 故障夹具与系统诊断完整保留；日志末尾另一个 Swift Testing 零项摘要不替代上述 XCTest 数量。

终态固定参考 pin 未变且干净，无主程序、测试、编译器或门禁残留；本轮零 Typebar 主程序启动。终态后只本合同与 README／规范／盘点补充结果，其余六个冻结输入不变。下一阶段须依据真实字段切片建立全局投影：保留相邻字段的未替换片段、为候选溢出及拆片分配独立呈现身份，不复用同一个 canonical ID 表示多个框；所有四呈现共同使用最终 attributes、词归属、控制结构和 caret after 几何。随后实际系统 IME、模式、Unicode、滚动／退休与设备验收，不以本次只读桥接替代它们。完整 goal 保持 active。
