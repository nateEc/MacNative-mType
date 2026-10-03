# Weakspot 实时评分与后续出题

会话现在在有效输入后更新内存评分簿，普通词及代码／普通条目游标在生成后续批次时读取最新评分，而非只用初始化快照。当前显示目标，以及代码／条目游标的段内余词和重复练习缓存，不因学习重抽。这个增量修复评分读取和尝试间传递，不证明原版与原生预取时序完整等价。

## 固定源码与时序

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[insert-text](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L299) 在记录输入后更新 Weakspot，再执行词导航。[评分簿](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/weak-spot.ts) 保留最多 50 样本的 EMA 与五秒错误罚时，取词时从 20 候选中保留首个最高平均分。取词不再评估当前段的余词；重复练习先复用全部已生成缓存，之后才选择新段。

原版 [addWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L571) 通常在词导航时补一个词，并维持约百词前瞻。当前原生仍在队列耗尽边界按批补题，普通无限入口也有既有首批预取策略。因此，同样输入到达时，两者可能已经生成不同数量的未来目标；本轮不把“新批次读取最新评分”升级为“每个未来词在完全相同时间采样”。

## 原生实现与数据边界

TypingSession 持有一个值拥有的 currentWeakSpotScores。有效相邻输入在既有两位毫秒舍入后立即更新评分；首个输入没有间隔样本，无空格模式预先拒绝的空格不学习，删除既不学习也不撤回过去评分。未启用 Weakspot 的会话同样保留学习。字符键及原始事件捕获继续沿已有合同，不因此证明多标量／多字符输入等价。

GeneratedWordContinuation 与 GeneratedCandidateContinuation 的 nextChunk 接收当前评分；不传时仍使用初始化簿，以保留独立调用的语义。候选段游标的缓存分支先返回已生成目标，不抽样；新评分只影响之后新选的段，不能改变待输出段内词。普通词生成游标还没有这套完整缓存，见剩余差异。普通词选择的可注入 rank 是自有测试输入，不是与原版 RNG 分布一致的声明。

主工厂把基准簿交给会话，普通、代码、引语和初始化失败都保留它。repeatedAttempt 传递最终评分且清空本次样本／首输入计时；应用在重置或重复入口接收整簿而非重新吸收已学习样本。较早保存的内存重复尝试用 withWeakSpotScores 继承最新应用簿，目标和缓存不变；异步外部内容替换也保留当前簿。全程没有新增共享可变引用或持久评分存储。

归档仍 22，设置、成绩、回放、服务、SwiftData 实体和协议没有变更；旧成绩及保存目标不重新生成。独立持久化弱项分析不受替代。回退只改变以后活跃会话的学习／出题，不删除已保存结果；真实旧库、旧二进制、应用共存和设备降级未运行。

## 行为证据

先添加不改变旧取词／学习行为的评分传入和观察接口，再运行六项回归；有效失败为 18 个断言，0.471 秒，日志 /tmp/typebar-weakspot-live-red-behavior.log。两个更早日志只有夹具错误导致的编译失败，不计行为红测。接入后六项零失败，0.012 秒，日志 /tmp/typebar-weakspot-live-green-initial.log。

新增 WeakSpotLiveGenerationTests 九项，相关 78 项零失败，1.684 秒，日志 /tmp/typebar-weakspot-live-expanded-complete.log。覆盖真实会话的基准学习、删除后间隔、首输入重置、无空格拒绝、重复不重记、工厂／引语基准传递，以及两类游标的最新评分、待输出段与缓存目标和旧内存尝试替换。阶段 53／66 项与最终集有重叠，不相加。最后修正一项测试标题的范围，已由完整门禁重新运行验证。

2026-10-04 冻结实现后的完整门禁通过：客户端 2535 项零失败，582.380 秒；显式十万词耐久用例 143.813 秒，旧回放两种投影的 12000 次组合字形删除基准 0.026055 秒。服务端 145 项零失败，1.577 秒；固定参考、原创边界、797 项唯一人工场景清单和未打开的 macOS 应用包通过。人工清单只做结构检查，不计设备验收。日志 /tmp/typebar-weakspot-live-full-gate.log、/tmp/typebar-weakspot-live-client-complete.log 和 /tmp/typebar-weakspot-live-service-complete.log。环境为 Swift 6.2.4、macOS 26.1、arm64；未启动 Typebar 图形程序，真实 local-practice-background 路径不存在。门禁之后只更新说明，不更改被测实现或夹具。

Scripts/check-source-code-decoration.mjs 在内存运行七个完整实际模块，新增四组实时评分夹具；既有 48 组代码装饰、15 组代码段、12 组普通条目及元数据检查保留通过。日志 /tmp/typebar-weakspot-live-source-final.log。初次重复夹具误把已补出的词当作未缓存词；按真实缓存复用和最近两词百次重抽纠正精确 rank 队列后通过。这是夹具预期修正，不计产品红测；没有跳过断言。间隔、随机 rank、配置、UI 和词输入均为明确自有适配，没有浏览器／实体捕获或源内容分布证明。

使用源码驱动、行为优先、简单局部实现及会话内决策／迁移／风险复核；缓存反例按根因调试追溯，写作复核区分实时评分与预取时序。没有独立审查。验证只用内存库和串行无窗口测试，不播放声音、不写真实 Typebar 数据、不操作账户、不部署。

## 剩余功能差异

后续必须继续核对原版补词触发／前瞻队列和正常导航的事件时序，以及普通生成路径的完整已生成缓存复用。字符键规范、输入批次拆分、Unicode／半代理、原始 live-cache、所有 Funbox 组合、外部词源／Polyglot、词库身份及随机分布、真实 GUI／IME／VoiceOver／设备、长期缓存和服务部署仍未验证等价。整体 goal 保持 active。
