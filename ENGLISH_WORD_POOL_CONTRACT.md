# 英语逐词候选与上下文装饰

十三个单语言英语词库的主练习现在使用已有的候选游标，不再把每个续接词交给索引从零开始的整批生成器。它保留全局词索引、实际前词、复合候选的段内余词、Weakspot 和重复缓存。本增量对齐这组入口的逐词处理，不宣称其他普通语言、源词值或浏览器输入时序等价。

## 固定源码合同

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[getNextWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L809) 每词先取基础候选，新段才执行最近两词及选项重抽，重抽最多一百次；段内词仍消耗基础取样，但不重新选择整段。初次比较小写，重抽比较保留大小写，Lazy 参与比较。关闭标点时普通 ASCII 大写转小写，Weakspot 取词钩子例外。之后依次执行 Lazy、标点、英式拼写、数字替换和 Funbox 文本变换，缓存实际目标。

[标点函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L42) 使用全局词索引和前一个已变换词。首词或句末之后只大写，不额外追加终止符；其余分支按顺序抽取，最后英语缩写门槛严格小于 0.5。[英语缩写](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/english-punctuation.ts#L42) 要求完整单个 ASCII 词匹配，外围可以是非词字符，数字和下划线不能被当作外围剥掉；匹配后另抽一次选择。[首字母函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/strings.ts#L67) 操作首个 UTF-16 单元，不把开头的辅助平面字母整体大写。数字选择仍在此前装饰之后覆盖整词。

## 独立原生实现

EnglishWordPoolContent 仅路由 English、1k、5k、10k、25k、450k、Commonly Misspelled、Contractions、Double Letter、Legal、Medical、Shakespearean 和 Old English 共十三个既有自有词库。Wordle、Pig Latin 和 Polyglot 不因名称相近误入英语缩写路径。词库仍为 Typebar 独立内容；保留原有英式自有池，不声明源字典或取样分布相同。

GeneratedCandidateContinuation 共用既有代码／条目游标和实际目标缓存，主工厂传入取样、大小写及装饰随机值。正常导航只补一个词；新段读取会话最新 Weakspot，待输出段内词和缓存不重新评分取样。英语 Lazy 在候选比较和装饰之前处理，已有文本变换的幂等规范化保留。普通其他语言及手工 GeneratedWordContinuation 仍走各自合同，未被删除或假称等价。

PoolWordDecorationPolicy 补齐英语缩写的最后分支，复用本项目既有自有替换表，但不再重复消费概率门槛。新入口严格匹配 ASCII 词字符边界；数字和下划线不是外围标点，非 ASCII 外围可以保留。英式自有拼写处理放在数字替换前，之后只执行文本变换，不二次转换。公共首字母处理按 BMP 首标量上界保留辅助平面首字符，并折叠单词间的 ASCII 连续空格，不导入上游实现或资产。

## 行为与风险证据

首轮九项测试出现 39 处失败，其中反池夹具误用正常池索引；改为真实镜像索引后仍有 36 个失败断言，0.428 秒，日志 /tmp/typebar-english-pool-red-corrected.log。不把反池夹具误差计产品红测。主要反例为英语工厂没有消费装饰随机值、实际 rank 未接线及公共装饰器缺少缩写选择。接入后九项零失败，0.013 秒（/tmp/typebar-english-pool-green-initial.log）。

会话内风险复核新增最新 Weakspot、Lazy 前词比较、101 词无空格完成／归档／重开，以及 UTF-16 开头字母反例。UTF-16 单项实际一处失败，0.416 秒（/tmp/typebar-english-pool-utf16-red.log），根因为使用完整 Character 大写而非首单元；只修复拥有该逻辑的公共装饰器。最终十三项及相关 178 项零失败，31.183 秒（/tmp/typebar-english-pool-expanded-final.log），含现有代码、四类条目、缓存、补题、反池、组合提交及 376 个普通语言的有限完成检查。较早 144 项回归通过，但与最终集合有重叠，不相加。

Scripts/check-source-code-decoration.mjs 新加入完整实际 english-punctuation 模块；十模块新增 17 组英语夹具通过（/tmp/typebar-english-pool-source-second.log）。包括全局索引、真实缩写／选择、ASCII 边界、UTF-16 首字母、数字覆盖及缓存不消耗 rank／装饰抽取。既有 48＋15＋12＋4＋4＋14 组保留通过；词字符串、rank、配置、DOM 和输入队列都是明确自有适配，未执行浏览器或实体输入，也不导入词库值进应用。

冻结实现后的完整串行门禁成功退出：客户端 2571 项零失败，617.004 秒；显式十万词耐久 144.460 秒，旧回放 12000 次组合字形删除双投影 0.025518 秒。服务端 145 项零失败，1.469 秒。固定参考、元数据、原创边界、800 项唯一人工场景结构与未打开应用包检查通过。日志为 /tmp/typebar-english-pool-full-gate.log、/tmp/typebar-english-pool-client-complete.log 和 /tmp/typebar-english-pool-service-complete.log；这些有界性能数字不能证明长期生成缓存内存或全部组合性能等价。

只使用内存库客户端、串行服务测试和未打开应用包；不启动 GUI、不播放声音、不操作账户或部署。人工场景仍待验收，结构检查不能算设备通过；真实 local-practice-background 路径单独检查。环境为 Swift 6.2.4、macOS 26.1、arm64；门禁后仅更新说明，未改被测实现、夹具或探针。只读官方元数据另确认十三个入口均无 originalPunctuation，Old English／Legal 允许 Lazy，其余十一项禁止 Lazy；未保存上游词值到项目。十模块探针重跑通过（/tmp/typebar-english-pool-source-final.log），另保留 4＋9＋10 组顺序／候选池探针（/tmp/typebar-english-pool-order-final.log）；800 项清单、原创边界与差异格式复查通过，参考固定且干净、Typebar 图形进程为零、真实背景成绩路径不存在。

## 兼容与剩余工作

没有修改持久设置、SwiftData 字段、服务协议、评分持久化或正式归档格式，仍为 22。旧保存提示、日志和固定成绩不重生成／回算；新会话改变取样和装饰，回退边界仅为后续新会话生成器，无数据迁移。真实旧库／旧二进制共存与降级未验。

源码驱动、行为优先及局部简洁实现限定本次变更；根因调试区分夹具索引和真实 UTF-16 缺陷，迁移／决策／风险复核保留无窗口边界，写作复核区分自动测试与设备证据。只有会话内有界复核，没有独立评审。

后续继续把普通其他语言的特殊标点与数字字形、其余多词候选池、外部／Polyglot 和自定义词流接入实际逐词合同；旧内容辅助 API 的整批规则仍未全部替换。英式字典身份、全部 Funbox 组合、原始捕获／Unicode／live-cache、浏览器异步与 pullSection、GUI／IME／VoiceOver、旧库／降级、长期缓存内存与性能、主题身份和服务部署仍开放。94 配置键及部分 Funbox 总体覆盖不升级，完整 goal active。
