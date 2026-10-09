# 组合投影的真实字段与部分字形归属

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
