# 普通候选池反写与弱项评分

普通词库的 backwards 应先改变抽样池的顺序，再逐词反写；抽样后的整批不能再倒序。本轮把这条规则接入普通首批和续批，并修正 Weakspot 将未知字符计入均分的问题。Polyglot 会创建新池，保留这个例外。完整原生重写仍未完成。

## 固定源码与对照范围

参考目录只读固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[候选池构造](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L639) 先反转 wordList，再调用 withWords 和建立 Wordset。[实际 Wordset](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/wordset.ts) 从已排列的池按普通或 Zipf 索引抽样；getNextWord 才进行当前词的文字变换。[Polyglot](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L653) 的 withWords 忽略传入池并加载组合语言，不能把该新池再次反转。[Weakspot](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/weak-spot.ts) 按 for-of 字符迭代，仅累计 book 中已有的字符，包括值为零的已学记录；从 20 个候选中保持第一个最高分词。

Scripts/check-source-generated-backwards-order.mjs 现在运行完整实际 words-generator、funbox-functions、wordset、weak-spot 四个模块。保留四组生成型夹具，并新增九组：普通／Zipf 的正反池共四组，未知字符、已学零分、组合标记、辅助平面字符四组，以及 Polyglot 新池一组。普通池 ab/cd/ef 按自有固定索引 0/2/1，正常输出 ab/ef/cd；反池再逐词反写输出 fe/ba/dc。

随机索引与 Zipf 索引、shuffle、语言内容、配置、活动元数据、输入间隔、GetText、类型及 UI／异常都是明确的自有适配。测试执行真实取词和评分函数，但不执行原版随机分布算法、浏览器生命周期或实体输入；不能由这些夹具证明原版词库内容与随机分布等价。参考函数和资产不进入原生项目或包。

## 原生实现与消费者

IndexedLexicon.ordered 在取指定 rank 时才访问映射后的源下标；45 万项夹具在创建视图时不读取词，随后只访问请求的镜像 rank。空池和非零 startIndex 切片均有验证。普通语言分派的 295 个 lexicon 参数采用该视图，6 个既有有限条目／段落数组仅在反池请求时倒序；机械逆变换审计确认除此之外没有改变原分派、过滤、装饰或标点规则。原生自有中英交替入口保留原池策略，不冒充官方 Polyglot。

OfflineContent 和 WeakSpotWordSelection 显式接收反池要求。TestSessionFactory 的普通首批以及 GeneratedWordContinuation 的续批保留抽样顺序；既有逐词 UTF-16 变换、下划线全局位置和同次生成的可见／隐藏目标继续共用。代码和外部词源未在本轮修正，自定义和引语路径不变。

WeakSpotScores 区分未知 nil 与已学零分；选词均分按 Unicode 标量读取已学习记录，不让未知字符稀释已知慢字符。评分簿的相邻间隔、错误罚时、50 样本更新、20 候选和首个并列胜者保留，持久化弱项分析仍是独立入口。Swift Character 键的规范等价、实际事件捕获、组合输入和跨脚本评分簿身份仍需验证，本轮不声称整个 Weakspot 完全等价。

## 先行失败与回归

三项普通续批先行测试在旧产品上出现四个失败断言；补充未知字符评分后四项出现五个有效失败断言。两次日志分别为 /tmp/typebar-ordinary-backwards-red.log 和 /tmp/typebar-ordinary-backwards-expanded-red.log，不将后续测试属性拼写导致的编译错误计作产品失败。

新增共十三项覆盖普通续批顺序、最近词重抽、全局下划线、懒索引、空池／切片、普通／Zipf 固定索引管线、微型池 101 次有界逃逸、未知／零分／Unicode 评分、冷簿并列、实际 501 词末尾提交和归档／固定重开。其中遍历单语言非代码入口的一项只证明提示可用和固定重开，不证明每个词库的内容身份或端到端随机 rank 等价。

相关 96 项零失败（8.811 秒），另组弱项／Polyglot／Zipf／最近词旧回归 34 项零失败（2.135 秒）；两组有重叠，不合并成独立测试总数。实际源码十三组夹具通过。日志分别为 /tmp/typebar-ordinary-backwards-expanded.log、/tmp/typebar-ordinary-backwards-wider.log 和 /tmp/typebar-ordinary-backwards-source.log。

## 保存和未验证边界

归档仍为 22，SwiftData 实体、偏好、保存成绩和服务协议不变。只改变后续新练习的生成及瞬时选词，不迁移、回算或重生成历史提示；已保存结果沿固定目标重放。回退代码只恢复后续生成规则，不会逆转已保存的新结果。没有运行旧二进制、真实用户数据库、降级或跨设备迁移。

验证只用内存库、串行无界面测试和未打开应用包，不启动 Typebar GUI、播放真实音频、操作账户或部署服务。真实背景练习路径须事前确认不存在，不能只靠内存库环境变量假定隔离。单实例规则继续执行。

源码驱动与行为优先技能限定对照范围；会话内决策／风险／迁移复核采用按需视图而非复制大型池，并保留旧固定记录。文档技能将 Weakspot 和 backwards 的有限证据与完整等价分开。这不是独立评审。代码／外部段落、原始未排序组合、半代理、源 RNG 恢复、变换后最近词身份、超大完整预览、全部词库／主题身份、真实 GUI／IME／VoiceOver、长场混合性能及线上服务仍有缺口，完整 goal active。

## 完整门禁状态

冻结代码后的完整串行门禁已通过：客户端 2,460 项零失败（585.322 秒），服务端 145 项零失败（1.492 秒），本轮实际十万词耐久通过（143.983 秒）。792 条人工清单结构、固定参考元数据／行为及原创性审计、未打开应用包构建、签名和资源边界均通过；这不是人工场景验收。Swift 6.2.4、macOS 14 包目标与依赖保持不变；源码对照使用 bundled Node 24.19.0。

完整外层日志为 /tmp/typebar-ordinary-backwards-final-full-gate.log，完整客户端和服务端日志分别为 /tmp/typebar-ordinary-backwards-final-client-complete.log、/tmp/typebar-ordinary-backwards-final-service-complete.log；through-endurance 文件只是中途快照，不冒充完整套件日志。客户端日志包含 macOS CoreData／XPC 系统诊断，但没有测试断言失败；不以此证明系统服务、实体设备或权限行为已验证。临时打包目录由门禁清理，不删除用户文件。参考目录仍干净、Typebar GUI 为零、真实背景练习路径仍不存在；完整 goal active。
