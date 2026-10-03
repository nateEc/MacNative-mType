# 生成型词流反写顺序

本轮修正生成型 Funbox 的首批与续批顺序。先反转候选词池不等于把已经生成的整批输出反转；旧实现混淆两者，改变了二进制等词流的目标顺序和批边界。现在保持生成器的全局词序号，再逐词反写；真正的自定义与引语候选池反转保持不变。完整重写仍在进行。

## 固定源码证据

参考固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[候选池构造](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L639) 先反转 wordList 再构造 Wordset；[生成下一词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L891) 调用 Funbox getWord 后才进行逐词文本变换。[二进制入口](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L566) 不读取候选池，[反写](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L349) 只反转当前词的 UTF-16 单位。生成后的整批不再反转。

Scripts/check-source-generated-backwards-order.mjs 只读运行完整 words-generator、funbox-functions、wordset 三个实际模块，四组自有二进制生成输入验证正常／下划线、默认百词／显示全部、候选池反转和第 101 词续取。GetText 输入、随机抽样、活动元数据、配置、数组工具、类型与 UI／异常为明确适配，不是原版随机生成算法、词库、浏览器布局或完整生命周期运行证据。源函数未复制到原生实现，参考代码与资产不进入应用包。

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
