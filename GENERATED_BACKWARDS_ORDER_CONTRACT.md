# 生成型词流反写顺序

## 2026-10-12 空白末词错误字母与 quickEnd

固定源码完整前置过滤与输入处理器执行 quickEnd 两值 × stopOnError 三值共六组：错误字母 `x` 仅在 quickEnd=true 且 stop=off 时完成；letter-stop 事件标记 inputStopped，其他不擅自结束（work/blank-lf-quick-source.log）。普通难度、非 strict、deleteOnError=off，DOM／事件／导航为自有适配器，不泛化到其他设置。

原生先行复现该组无法完成（work/blank-lf-quick-red.log），补上最终显式空白字段长度判断；随后结果断言复现完成词数 1 而非 2（work/blank-lf-quick-focused.log），修正 words 模式已完成末词的 quickEnd 计数。保留错误字母，不伪造正确输入。最终相关七组 115 项零失败（23.100 秒，墙钟 23.112 秒），覆盖六组状态、letter-stop 输入保留、完成计数和逐字回放；日志 work/blank-lf-quick-regression.log。deleteOnError、不同错误序列及难度／strict 混合、重复 quickEnd、真实 GUI／IME 与完整门禁仍开放，goal active。

## 2026-10-12 空白 LF 末词规则组合

固定源码完整前置过滤／输入处理器执行 3 难度 × 2 strictSpace × 3 stopOnError 共 18 组：正确最终 LF 均触发 finish；strictSpace=true 或非普通难度的事件不 commitsWord，仍依当前词正确完成。DOM／输入／事件／导航为自有适配器，未执行真实浏览器导航。源码日志 work/blank-lf-rules-source.log。

原生新增组合用例在旧实现复现 normal/strict=true/stop=off 的 active、计数 1 与结果 nil 三处失败（work/blank-lf-rules-native.log；先行一次测试类型名拼写编译错误已纠正，不计行为证据）。补充有限最终空白字段正确 LF 的非导航完成判断，要求显式字段数满足实际有限预算、无待加载内容且本次输入正确。18 组结果逐字回放及计数通过；相关七组最终 114 项零失败（23.137 秒，墙钟 23.150 秒），日志 work/blank-lf-rules-regression.log。下文“strict-space／难度组合未验收”为历史状态；本段只验收正确 LF 的上述组合，错误输入、deleteOnError、quickEnd 组合、真实导航／IME 和完整门禁仍开放，goal active。

## 2026-10-12 普通空白 LF 末词完成修正

新增固定源码执行覆盖完整 before-insert、onInsertText、validation、util 与 finish helper：普通难度、strictSpace=false 下，末词 `\n` 通过前置过滤，事件 correct/commitsWord=true，并触发 finish。输入 DOM、事件、游标、导航与 UI 为自有适配器，不代表浏览器真实导航／网络／IME 端到端。参考源码仅只读执行，不移植其代码。

原生重新启用空白 LF 完成断言，旧代码复现 active 与 nil 结果失败（work/blank-lf-native-red.log）。定位为完成判断排除了显式空白字段。初版改动引发 9 处已有提前完成回归（work/blank-lf-native-green.log），随后收紧输入计数为实际非空字段；目标侧保留显式空白字段，推断空白分词不变。最终 113 项零失败（23.057 秒，墙钟 23.069 秒），含末字符前不完成、101 词完成计数、逐字回放和重复；日志 work/blank-lf-final-regression.log。源码探针 work/blank-lf-handler-source.log 通过。下文先前“空白 LF 完成未证明”为历史状态，本段只关闭普通设置的处理器／原生内核边界；strict-space／难度组合、真实导航、主 GUI、完整门禁／Release 仍未验收。goal active。

## 2026-10-12 有限末词 LF 提交符增量

后续重复／结果证据：实际固定生成器重复读取仍返回含 LF 的原字段，最终显示去提交符不回写生成历史。非空 LF 原生用例增加 101 词完成计数、零错误、结果逐字回放及重复练习完成断言；相关 33 项通过（2.996 秒，墙钟 3.000 秒），日志 work/final-lf-repeat-regression.log 与 work/final-lf-repeat-source.log。探索性假设“空白 LF 输入后应完成”失败（work/final-lf-repeat-diagnostic.log 明确 terminal="\\n"）；尚无完整原版输入链证明此假设，未据此改变产品，也未把 active 状态固化为正确规则。空白 LF 仅验证发布保留，完成语义仍开放。本次只增加证据，无产品代码变更。

固定参考源码的完整 addWord、生成器和 TestWords 执行证据确认：非空最终字段移除 LF 提交符，空白 LF 字段不移除。自有输入与游标，不代表真实导航或网络。原生先行用例在旧实现上复现一处失败；仅扩展最终缓存字段的提交符处理，保留空字段和生成历史。四组相关回归 73 项零失败（19.452 秒，墙钟 19.460 秒）。日志在 work/final-lf-source.log、work/final-lf-red.log、work/final-lf-green.log。无空格字段、重复完成边界及全量门禁／Release 未在本增量验收，不声称 LF 功能全部等价；未启动主 GUI。

## 2026-10-12 原生旁路发布与生成历史增量验收

本节为当前状态；下方“试作”“未提交”和早期失败记录均为各阶段历史，不覆盖本节结论。本轮将原生改动纳入提交：旁路需求使用已发布词数，单段按配置词数上限发布原文（不套用反写、大写、下划线或英式拼写变换），先发布新段再消费一个旧生成器缓存字段，而非排空缓存或按剩余全局预算裁段。有限超量发布后以实际末词完成，停止后续缓存追加。原生不复制参考实现或资产。

重复只保存生成器实际返回的字段；旁路词及未消费缓存不进入历史。部分重复后再次重开保留既有完整历史，重放不重复入库，历史缺失再请求生成。逐字段积累，仅在重开时合并，避免每次前进重建整个历史。非最终缓存末词缺失空格提交符会在生成字段边界补齐；最终发布端移除空格时不改写生成历史。归档／数据库格式、设置和服务协议没有变化，不重写旧记录。

测试更新依据固定源码完整 addWord、生成器、词存储及完成辅助函数的执行证据，不是为绿灯删除行为检查。保留末字前活动、末字完成、字段计数、三种错误规则、精确回放／归档；新增普通与下划线的部分重复、三种中文语言的原文旁路与新生成段差异。手工构造的无尾提交符开场需要显式补提交的用例不冒称原版异步导航等价。先行失败与分阶段日志保留：缓存末词提交符两处失败（nonfinal-cached-commit-red.log），英式旁路转换一处失败（side-british-conversion-red.log）；旧广回归从 63／39／28 处断言逐项核对至零，不能将中间数量解释为相同数量的产品缺陷。

最终命令设置 TYPEBAR_QA_IN_MEMORY_STORE=1，串行运行 BritishWordGenerationTests、EncyclopediaIntroductionTransportTests、LiveGeneratorDemandTests、LivePracticeReplacementHostTests、LocalPersonalBestLedgerTests、PoetrySourceCleaningTests 和 ProviderFieldSessionTests：154 项零失败、无跳过，243.543 秒（墙钟 243.560 秒）。其中全部 35 宿主 222.783 秒（222.787 秒），随后同进程 19 PB 台账 0.262 秒（0.264 秒）。完整日志为工作目录 live-side-final-host-pb-regression.log。三条只读保存错误对应 PB 的实际只读写入／导入／重置失败回滚用例，三项断言通过，不是忽略通用保存故障。没有运行主程序，测试终态无残留进程。

会话内风险复核（非独立评审）查出并修正英式转换漏口。仍需继续验证：旁路空段且缓存为空的同调用再取、末词 LF 提交符、异步请求返回时发布预算变化的 admission／导航可达性、全部修饰器与实体 IME／视觉组合、真实网络。新完整门禁、Release 和十万词耐久未在此增量运行，154 项定向通过不能代替它们。原有功能分类不升级为完整实现，整体 goal active。

## 2026-10-12 有限超量完成和已消费历史试作

固定源码脚本进一步执行完整 fail-or-finish 模块的完成辅助函数：在实际词存储已发布 111 词、配置 105 词且 areAllWordsGenerated 返回 true 时，正确输入在索引 104 和 109 均不结束，在索引 110 才结束。原版处理器传入的 allWordsTyped 标志在此为自有输入，因此不冒称完整输入监听器／导航／DOM 执行。完整脚本通过，日志 side-oversupply-finish-source.log。

原生新增超量完成用例先复现三处失败；改为以已发布末词完成并停止继续排空旧缓存后剩一处词数 110／111 差异，原因是发布末词仍带空格提交符。现在在发布端去除该最终空格，生成器历史保留去除前的返回值。14 项 LiveGeneratorDemandTests 零失败（0.828 秒、墙钟 0.831 秒），日志 side-oversupply-finish-native-red.log、side-oversupply-finish-native-focused.log 和 side-oversupply-final-commit-focused.log。换行提交符及全部无空格组合仍未据此验收。

重复历史改为只记录生成器实际消费的字段，旁路原文和未消费缓存排除；重复时保留既有完整历史并禁止重放二次入库，避免部分重复后再重开丢词。两项首次历史用例先行四处失败（live-consumed-history-red.log），部分重复用例在普通与下划线两模式四处失败（live-partial-repeat-history-red.log）。完成该阶段后 52 项扩大回归零失败（79.086 秒、墙钟 79.093 秒），仅可选十万词耐久因未设置 TYPEBAR_ENDURANCE_TESTS=1 按既有规则跳过；不声称本次耐久通过。该 52 项运行早于后续有限超量完成修正，不能覆盖后者。

原生试作仍仅在未提交工作区；旧广回归的过时契约和真实回归需继续逐项核对，新完整门禁未运行，目标 active。本次只提交源码探针和检查记录，不将试作送入 main。主程序保持零实例。

## 2026-10-12 旁路预取边界补证（仍有原生缺口）

同一固定参考的完整 addWord、生成器与词存储探针新增三项自有状态：100 个已发布词、5 个保留词，在活动索引 80 时不预取、81 时预取；有限总词数为 105 且缓存已占满预算时仍预取。后二者先发布新段 fresh、later，再从旧缓存发布 retained0，只消耗一个旧缓存词。完整脚本运行退出 0，三项均通过；日志位于工作目录 side-prefetch-published-threshold-source.log。

这些是构造的存储／游标边界，不证明真实键盘导航可达性、HTTP、浏览器呈现或原生等价。原生目前把未发布缓存计入需求与有限预算；仅替换预取阈值会让追加函数拒绝已请求的新段，调用方又可能将拒绝误判为来源失败。因此预算、发布顺序及重复练习历史需要一并设计与验证，当前未修改产品逻辑。本轮只增加源码证据，不代表旧完整门禁覆盖新提交；完整重写目标保持进行中。

### 旁路追加与重复练习组合证据

完整脚本进一步实际生成自有 105 词首段（发布 100、保留 5），只适配活动索引为 81，然后运行真实 addWord：显示新增 sideFirst、sideSecond、opening100。切换自有重复标记并再次运行真实 generateWords，首 100 词命中旧历史且不请求来源；随后真实 getNextWord(100) 返回 opening100 而不是 sideFirst。索引 101 的历史缺失会重新请求来源并返回 fallbackFirst；索引 105 的历史缺失抛出 Repeated word is undefined，不请求来源。完整脚本退出 0，日志为工作目录 side-prefetch-repeat-composition-source.log。

会话内有界决策复核（不是独立评审）据此否定“把原生保存历史重排为显示顺序即可等价”的方案。原版保存的是生成器返回历史，旁路直接发布绕过此历史；原生 initialExternalPromptContinuation 则保留整个预取尾段及后续段落，二者所有权不同。后续实现必须区分已发布目标、尚未消费的生成器缓存、实际生成器返回历史；重复开场重放历史，历史缺失且未到有限上限才恢复生成，旁路发布不能混入生成器历史。还需覆盖预取与前进请求交错、过期响应、NoQuit、无空格／下划线字段以及有限超量发布后的完成判断。不能用一条计数或数组重排替代这些状态约束。

本证据使用实际模块与完整 addWord，但来源、重复标记和活动索引仍为自有适配；不证明真实导航可达性、网络、实际应用重复按钮或原生修复。此次仅增加组合回归与设计约束，未运行新的原生构建／完整门禁，也未宣称原生缺口解决。

### 原文发布与有限超量的补证及试作状态

同一脚本新增两个完整调用链用例：开启 backwards 时，新段 fresh、later 保持原文，而实际 getNextWord 消费旧缓存 retained0 后返回 0deniater；100 个已发布词、总词数 105 时，10 词旁路段完整发布再消费一个旧缓存词，最终发布数为 111，而不是按剩余五词截断。完整脚本退出 0，日志为工作目录 side-prefetch-raw-oversupply-source.log。这只证明发布和缓存边界，不证明输入完成判定或实际导航可达性。

原生试作已复现并修正旁路错误套用 backwards 的问题：先行单项一处有效失败，修正后 LiveGeneratorDemandTests 10 项零失败（0.415 秒，墙钟 0.417 秒），日志 side-prefetch-raw-native-red.log 与 side-prefetch-raw-native-focused.log。上一阶段 65 项广回归仍有 63 处断言失败（包含随后纠正的未来窗口测试预期）；这不是 63 个已确认产品缺陷，也不能全部归为过时测试。重复历史、无空格字段及有限超量完成边界尚待逐项核对。试作保留于未提交的 TypingEngine.swift 和 LiveGeneratorDemandTests.swift，不随本次源码证据提交进入 main；未运行更新后的广回归或完整门禁。目标继续，主程序未启动。

本轮修正生成型 Funbox 的首批与续批顺序。先反转候选词池不等于把已经生成的整批输出反转；旧实现混淆两者，改变了二进制等词流的目标顺序和批边界。现在保持生成器的全局词序号，再逐词反写；真正的自定义与引语候选池反转保持不变。完整重写仍在进行。

## 固定源码证据

参考固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[候选池构造](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L639) 先反转 wordList 再构造 Wordset；[生成下一词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L891) 调用 Funbox getWord 后才进行逐词文本变换。[二进制入口](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L566) 不读取候选池，[反写](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L349) 只反转当前词的 UTF-16 单位。生成后的整批不再反转。

本阶段当时的 Scripts/check-source-generated-backwards-order.mjs 版本只读运行完整 words-generator、funbox-functions、wordset 三个实际模块，四组自有二进制生成输入验证正常／下划线、默认百词／显示全部、候选池反转和第 101 词续取。后续四模块与普通词池扩展见 [普通候选池反写与弱项评分](ORDINARY_BACKWARDS_POOL_CONTRACT.md)。GetText 输入、随机抽样、活动元数据、配置、数组工具、类型与 UI／异常为明确适配，不是原版随机生成算法、词库、浏览器布局或完整生命周期运行证据。源函数未复制到原生实现，参考代码与资产不进入应用包。

## 原生改动与消费者

TestSessionFactory 的 TypebarStreamContent 分支和 GeneratedStreamContinuation 明确保留已生成词序，仍经既有规范逐词变换。只改这两个入口，不改变普通抽样词、弱项、代码、外部段落、自定义／引语的生成实现，不以本轮通过证明这些其他路径已等价。

首批的下划线 bound 与续批的全局 wordOffset 保持：默认 101 词只使第 100 词不带下划线；显示全部时才使实际第 101 词不带下划线；501 词续批的末词仍须输入下划线才完成。可见目标、隐藏词界、完成计数、词历史、回放和新记录沿用同一次生成结果，不重新采样或猜词界。

八项新增回归覆盖首批顺序、续批与有限耗尽、501 词完成边界、显示全部、十二种兼容的自有生成流、无空格下不同分批大小、无限续批／重开及独立旧提示归档。十二种流的确定性自有内容不冒充原版录入内容或随机分布；只验证相同生成输入不被错误倒序。普通候选词池反转、代码词序、外部段落、非 BMP 半代理和完整组合顺序仍需补齐。

## 保存与回退边界

归档版本仍为 22，CompletedTestResult、SwiftData 实体、设置与服务协议不变。不迁移、重算、重新生成或回写旧成绩；独立构造的旧批次倒序提示可完整归档／取回并保持固定值，新练习才采用纠正后的目标顺序。回退代码会恢复后续新练习的旧顺序，不会逆转已保存的新记录；没有运行真实旧二进制或用户数据库。自动化只使用内存库、未打开包，不启动 GUI、播放真实音频、部署或操作账户。

## 验证与剩余工作

先行四项在旧产品代码上复现九处有效失败（0.993 秒），修正后相关 86 项零失败（9.527 秒）。扩展至八项新增并覆盖自定义候选池、引语、管道、随机目标、下划线和完整预览消费者后，相关 218 项零失败（12.682 秒）；四组实际源码对照单独通过。Swift 6.2.4、macOS 14 包目标与依赖保持不变。

源码驱动与行为优先技能限定证据范围；会话内有界决策／风险及迁移复核保留真正词池反转和旧固定记录，文档技能纠正“48 项均等价”的旧矩阵措辞。这不是独立评审。入口覆盖不能证明全部组合、原版内容身份、实际 GUI／IME／VoiceOver、长场混合性能或服务部署完成。超大完整预览上限和其他原版缺口仍开放，完整 goal active。

冻结版本上的最终串行门禁已通过：客户端 2,447 项零失败（584.649 秒），服务端 145 项零失败（1.566 秒）；本轮实际十万词耐久通过（143.750 秒），不是沿用历史结果。790 条人工清单结构、固定参考／原创性等审计与未打开应用包构建、签名和资源边界检查均通过。完整外层门禁日志为 /tmp/typebar-generated-backwards-final-full-gate.log，完整客户端日志为 /tmp/typebar-generated-backwards-final-client-complete.log，through-endurance 文件只是中途快照；服务端通过摘要保留在外层日志，临时详细日志已随门禁自动清理。参考目录保持干净，Typebar GUI 仍为零，真实背景练习路径不存在；人工验收仍待实机，完整 goal active。
