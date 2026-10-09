# 组合投影的真实字段与部分字形归属

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
