# 生成型词流反写顺序

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
