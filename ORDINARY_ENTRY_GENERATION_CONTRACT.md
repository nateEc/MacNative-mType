# 普通条目分段与连续出题

恐怖短语、原创生物名、竞技术语与 Tamil 旧词库的主练习现共用候选段游标，不再逐批重新抽段或把 Weakspot 整段当作一个输出词。普通续批保留段内余词，重开复用实际目标，缓存结束后抽新段。词数、标点及数字都按输出词计算。原有代码路径、原创目录、Polyglot 与用户自定义输入保持各自合同；整体重写仍未完成。

## 源码规则与范围

参考只读固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[getNextWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L819) 逐词消耗基础抽样，但只在新段执行最近词、整候选数字和标点过滤及 Weakspot 覆盖。以 ASCII 空格分段，保留段内词序；跨批不重新抽段。最近词使用变换后的实际目标。反池与已有代码规则见 CODE_SECTION_GENERATION_CONTRACT.md。

普通候选在标点关闭时使用源码的特定 ASCII 符号集合过滤，而非要求所有字符都是字母或数字。该集合不含感叹号，非 ASCII 性别符号也不是过滤项；百次重抽上限后仍可能输出带句号等符号的候选，不把“标点关闭”理解为无条件清理文本。普通输出词含 ASCII 大写且无取词钩子时才小写；Weakspot 的 getWord 钩子跳过该小写步骤。[大小写和 originalPunctuation 分支](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L929) 对原标点词库不再追加标点，但仍可逐词按严格 10% 分支用数字替换整词。数字沿已验证的浮点取整规则，包括极近上界的五位例外。

| 源身份 | 原生内容路径 | 原标点标志 |
| --- | --- | --- |
| typing_of_the_dead | Typebar 原创恐怖短语 | 是 |
| pokemon_1k | Typebar 原创生物名 | 否 |
| league_of_legends | Typebar 原创竞技术语 | 否 |
| tamil_old | Typebar 原创 Tamil 旧词库 | 否 |

这些身份与标志来自只读元数据，不导入原版词或资产。源四项的条目数／规范化后多词数分别为 10098／7338、1025／28、442／229、460／1；原生自有内容不因此被宣称词值等价。完整非 code_* 扫描得到 67 个原始含 ASCII 空格的身份、66 个规范化后真正有多词候选的池。Arabic 10k 的源条目有边缘空格而没有规范化后的多词，此区别避免按一个空格统计直接改写整个词源。其余 62 个普通多词池没有由本轮接线或证明完整等价。

## 实现与数据兼容

GeneratedCandidateContinuation 是原代码段游标的共享实现，保存待输出段、偏移、实际前词、输出预算和已生成批次。GeneratedCodeContinuation 与 CodeWordDecorationPolicy 的旧名称只是内存类型别名，没有新增第二套状态机，也没有序列化这些别名。PoolWordDecorationPolicy 保留代码分支，并为这四项执行普通通用装饰；不把它声明为所有语言装饰器。

主工厂、普通内容 API 与 Weakspot 内容 API 都从 OrdinaryEntryContent 的同一自有池取词，删除已无调用的 sectionPrompt／entryPrompt 旧规则。主会话保存已变换目标与隐藏词界；内容 API 返回装饰后的源词，调用者仍负责文字修饰器，避免反写执行两次。正常有限／无限首批不超过 100 词，完整预览沿现有策略；101 词测试在实际尾词完成，no-space 历史按隐藏词逐项提交。重开游标清空旧待输出段而保留缓存，且不会改动原游标的待输出余词。

只改变以后生成的新题。没有设置、成绩、实体列、服务或归档格式变化，归档仍 22；旧提示及指标不重抽、不补造、不回算。四入口的完成、词历史、正式及便携归档由真实会话测试覆盖。回退只影响以后出题，不能删除已经保存的新提示；真实旧库、旧二进制、共存或降级没有运行。

## 验证证据

先行五项在旧产品上产生 16 个有效失败断言，0.463 秒，日志为 /tmp/typebar-ordinary-entries-red.log；实现后五项零失败，0.007 秒，日志为 /tmp/typebar-ordinary-entries-green-initial.log。扩大阶段确认两项历史测试的七个断言仍固定要求“清除所有标点”或“每九词固定数字”，日志为 /tmp/typebar-ordinary-entries-expanded-first.log；这些不符合已执行的原版规则。修改为合法候选组件／数字形状断言，并用新确定性夹具验证概率、覆盖与预算，没有跳过或吞掉失败。

会话内决策复核发现 Weakspot 大小写反例，一项先行产生一个有效失败断言，0.443 秒，日志为 /tmp/typebar-ordinary-entries-case-red.log。修正后新增 OrdinaryEntryGenerationTests 共 14 项，相关 106 项零失败，7.899 秒，日志为 /tmp/typebar-ordinary-entries-case-expanded-final.log。覆盖四个工厂、取词 rank、段内顺序、普通过滤／大小写、原标点、逐词数字、Weakspot 边界、反池、no-space、101 词尾批、缓存后新段、独立游标及内容 API 源值契约；先前 105 项与本组有重叠，不能相加。

Scripts/check-source-code-decoration.mjs 在内存执行七个完整实际模块，保留代码装饰 48 组及代码段 15 组，新增普通条目 12 组和四入口／全普通空格元数据断言。/tmp/typebar-ordinary-entries-source-expanded.log 是通过证据。配置、随机 rank／单位、活动元数据、间隔、数组、类型和 UI 为明确自有适配；词输入也是自有夹具，不是原版字典。首次夹具误把感叹号当过滤项，实际源码反证后增加感叹号与句号分别验证；这不计产品先行失败。

2026-10-04 冻结实现后的完整门禁通过：客户端 2526 项零失败，580.803 秒；显式十万词耐久用例 144.004 秒，旧回放两种投影的 12000 次组合字形删除基准 0.025093 秒。服务端 145 项零失败，1.459 秒；固定参考、原创边界、796 项唯一人工场景清单及未打开的 macOS 应用包检查通过。人工清单的结构校验不是设备验收。证据在 /tmp/typebar-ordinary-entries-full-gate.log、/tmp/typebar-ordinary-entries-client-complete.log 和 /tmp/typebar-ordinary-entries-service-complete.log；运行环境为 Swift 6.2.4、macOS 26.1、arm64。参考工作树保持干净，Typebar 图形实例为零，真实 local-practice-background 路径不存在。

门禁之后只修改说明文档，没有变更被测实现或夹具。使用 bundled Node 24.19.0 的 --experimental-vm-modules 参数重跑源码对照：48 组代码装饰、15 组代码分段、12 组普通条目及元数据检查通过，日志 /tmp/typebar-ordinary-entries-source-final-vm.log；另脚本原有 23 组取词／反池夹具通过，日志 /tmp/typebar-ordinary-entries-pool-source-final-vm.log。首个未带 VM 模块开关的命令在加载模块时失败，不计为产品回归或通过证据。最终人工场景及参考行为索引复查通过。

源码驱动与行为优先技能约束先行证据，决策／迁移复核区分源值和实际目标、普通续批和缓存后新段，并限定旧数据不变；风险复核在本会话进行，不是独立评审。写作技能把四项接线和全普通词源等价分开。全部客户端测试使用内存库，未启动 Typebar 图形程序、播放音频、操作账户或真实 Typebar 数据。

## 未验证范围

后续 [Weakspot 实时评分与后续出题](WEAKSPOT_LIVE_GENERATION_CONTRACT.md) 已接入会话内即时学习，两类游标的新批次读取最新评分，尝试之间传整簿而不重复吸收旧样本；段内余词和已生成缓存不重抽。这取代先前的初始化评分快照缺口，但原版按词导航补词与原生批次预取的时序、原始事件捕获及全部普通路径缓存仍未证明等价。

其他普通多词池、普通单词主路径的装饰与最近词规则、Polyglot、外部词源、原版词值及随机分布、全部修饰器组合／简化输入／Unicode／半代理、空候选异常、段身份消费者、长期缓存、GUI／IME／VoiceOver、真实设备、旧库和服务部署仍未证明等价。446 个语言身份、48 个 Funbox 入口及静态检查不升级为全部功能覆盖；goal 保持 active。
