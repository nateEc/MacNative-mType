# 完整生成目标缓存与嵌套重开

普通词和生成流现在保留全部已生成实际目标，重复练习不重新生成缓存词或随机大小写。它们与代码／四类普通条目共用值缓存，仍保留各自的生成规则；这个增量不改变批次预取时序，也不宣称所有词源等价。

## 固定源码证据

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[getNextWord 的重复分支](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L776) 按词索引返回之前的实际结果；缓存之后仅在模式和预算允许时重新生成，否则抛出 Repeated word is undefined。[生成末端](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L983) 保存已装饰、变换和追加提交符的结果。原生独立实现这个行为，不复制源代码或词值。

Scripts/check-source-code-decoration.mjs 在内存运行七个完整实际模块，以自有 node／bay／elm 和 oak／cedar、明确 rank／unit 队列及适配边界新增四组夹具：随机实际目标、生成后缀复用、嵌套增长与有限耗尽。缓存复用不消费随机队列；缓存末端继续新生成，最终拒绝无预算取词。既有 48 组代码装饰、15 组分段、12 组普通条目及四组实时 Weakspot 夹具保留。日志 /tmp/typebar-generated-target-cache-source.log 首次执行通过。这不是完整上游 Vitest、浏览器、原版词库或 RNG 分布证明。

## 原生契约与兼容边界

GeneratedPromptCache 是会话游标持有的值，保存 GeneratedWordChunk 的 source、transformed、noSpaceTargetWords 和 noSpaceWordLengths。重复游标保留最终生成状态，先回放初始提示之后的全部缓存，再产生新词；缓存读取不调用源选择、变换或 Weakspot 取样。新评分只影响缓存结束后的新生成，缓存目标不重抽。

初始检查点既可在零个缓存批次，也可在已 primed 的开头批次之后。重开保存稳定的 openingCount，不能把副本持有的整份缓存误当新的初始提示；未读缓存也不能在二次重开时丢失。各副本后续增长互不影响。代码／条目仍跳过已包含在初始提示里的一个批次，仍按原合同重置候选段。

有限词数游标的 hasRemaining 同时检查未读缓存和剩余生成预算。全部尾词已进入提示后不再冒称可续批，末词可以完成，包括模型层组合输入的完成投影。这里未进行实体 IME 输入验证。

没有增加持久缓存、设置、SwiftData 字段、服务协议或共享可变引用；归档仍为 22。已保存结果不重新生成或回算。回退仅涉及新内存尝试的缓存行为，不需要数据迁移；旧二进制／真实旧库读写未验收，不用旧程序覆盖唯一数据。

## 行为证据

最初 modifier 名称错误造成编译失败，不计产品反例。修正夹具后，保持旧重置语义的占位实现执行六项测试产生 27 个有效失败断言（/tmp/typebar-generated-target-cache-red-behavior.log）；共享缓存首版六项零失败。随后真实会话与 primed 普通游标的嵌套重开两项产生六处失败（/tmp/typebar-generated-target-cache-nested-red.log），根因为初始缓存检查点随整份历史扩大。稳定检查点修复后，最终 GeneratedTargetCacheTests 十项、相关回归合计 83 项零失败，1.319 秒（/tmp/typebar-generated-target-cache-expanded.log）。

覆盖缓存源词与随机目标不再生成、隐藏词界、primed 开头、有限尾批、部分重开后的完整未来、副本独立增长、生成流索引、真实会话嵌套重开、普通 Weakspot 新旧评分以及有限末词完成／便携和正式归档往返。相关集合与早期阶段有重叠，不相加；未放宽既有测试。

2026-10-04 冻结实现后的完整串行门禁通过：客户端 2545 项零失败，583.341 秒；显式十万词耐久 144.419 秒，旧回放两种投影的 12000 次组合字形删除基准 0.025303 秒。服务端 145 项零失败，1.576 秒；固定参考、原创边界、798 项唯一人工场景结构与未打开应用包验证通过。日志 /tmp/typebar-generated-target-cache-full-gate.log、/tmp/typebar-generated-target-cache-client-complete.log 和 /tmp/typebar-generated-target-cache-service-complete.log。首次日志保存助手的服务文件路径拼写错误，另一个正确路径助手已保存完整服务日志；不影响串行测试、终态与门禁通过。

环境为 Swift 6.2.4、macOS 26.1、arm64。仅用 TYPEBAR_QA_IN_MEMORY_STORE=1 无窗口客户端测试，再串行服务测试与未打开的应用包验证。真实 local-practice-background 路径单独确认不存在；不启动 Typebar GUI、不播放声音、不写真实数据、不操作账户、不部署。门禁后只更新说明，不修改被测实现／夹具。

提交前再次运行七模块对照，48＋15＋12＋4＋4 组全部通过（/tmp/typebar-generated-target-cache-source-final.log）；四模块排序／普通池／代码池旧 4＋9＋10 组也通过（/tmp/typebar-generated-target-cache-order-final.log）。798 项人工清单结构、固定行为证据和 diff 空白检查再次通过；清单绿灯不升级设备状态。

使用源码驱动、行为优先、简洁局部实现及会话内决策／迁移／风险复核；嵌套失败按根因调试追溯，写作复核区分实际缓存与预取时序。没有独立审查。人工场景只登记待设备验收，不把结构检查称为实机通过。

## 仍未等价的范围

后续[生成词前瞻队列](GENERATED_LOOKAHEAD_CONTRACT.md) 已把普通词、代码／条目与自有生成流默认首批改为 100，专注模式为 1–4，并在成功导航时补一词；此前 500／300–500／200 priming 和整批边界描述不再是这些生产路径的当前状态。原版异步事件顺序、其他词源、普通候选／标点／数字分布仍未因共享缓存或补题窗口自动对齐；生成流源内容仍是自有索引派生，不是原版随机分布。

其他词源／Polyglot、完整组合、Unicode／半代理、原始 live-cache 和键规范、实体 GUI／IME／VoiceOver、旧库／降级、服务部署、词值与资源身份仍开放。缓存随尝试增长，没有任意上限；十万词输入耐久不是长期缓存内存或所有混合路径性能证明。94 配置键和部分 Funbox 的既有覆盖不升级，整体 goal 保持 active。
