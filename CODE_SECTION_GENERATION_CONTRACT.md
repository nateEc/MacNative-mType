# 代码候选分段与重复练习

代码主练习现在先抽一个候选，再按其内部顺序逐词输出。词数限制可在段内截断，正常续批保留剩余词；重复练习复用已生成的实际目标，缓存用尽后抽新段，而不是继续旧段尾。九个代码入口已接入 Typebar 自有多词候选，其他代码入口及 Polyglot 的平面词池保持不变。整体原生重写仍未完成。

## 固定源码依据

参考只读固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[getNextWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L819) 每输出一个词都先消耗基础候选抽样，即使段内还有余词。只有新段才对候选首个 ASCII 空格分量与最近两个实际目标作比较，并对整个候选作数字等配置过滤。最多重抽 100 次，首次比较小写，重抽比较保留大小写。

新段在 Weakspot 覆盖前合并连续 ASCII 空格、去除首尾 ASCII 空格，随后按 ASCII 空格切分。Weakspot 在段边界额外抽 20 个候选，不对每个剩余词再次评分。Tab、换行或不换行空格不能被擅自当作段分隔符。各输出词独立执行装饰、数字覆盖及文字变换，反池不改变段内词序。开场传入的前词为空串，因此带前导空格的候选会先触发首分量重抽，再规范化；有界夹具保留这一顺序。

[generateWords](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L617) 每次初始化都清空 currentSection，包括重开；[重复分支](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L780) 直接返回缓存中的实际目标。源码执行证明缓存结束后开启新段。原生游标复制时清空待输出段，但保留目标缓存及原游标的值语义，重开不会改动原游标的余词。

## 内容范围与兼容边界

元数据扫描只统计 code_* JSON 的身份、总条目数及含 ASCII 空格的条目数，不输出或导入词字符串。固定源的 69 个代码身份中，以下九项有多词候选：

| 身份 | 源条目数 | 源多词条目数 |
| --- | ---: | ---: |
| code_abap | 200 | 2 |
| code_haskell | 208 | 5 |
| code_javascript | 126 | 3 |
| code_javascript_react | 202 | 3 |
| code_ocaml | 495 | 57 |
| code_ook | 9 | 9 |
| code_rust | 192 | 13 |
| code_typst | 43 | 1 |
| code_vim | 167 | 1 |

CodePracticeContent.wordCandidates 使用已有原创程序的行生成短语；八项保留原有单词并追加短语，Ook 只使用原创行段。原生条目数和内容不等于上表，也不宣称分布相同。JavaScript 1k 和 ABAP 1k 不因同属语言家族而增加段候选。Polyglot 继续调用原有 polyglotTokens，完整程序样例及用户自定义输入不变。

GeneratedCodeContinuation 用段数组与偏移保存当前余词，不反复删除长数组首项。跨批实际前词、全局词序号、标点 bound、一次变换及 no-space 实际词目录沿既有路径工作。只改变之后生成的新题；没有设置、成绩、实体列或服务协议变化，归档仍 22，旧固定提示不重抽、不回算。便携及正式归档测试通过；真实旧数据库、旧二进制共存及降级没有运行。回退只能改变未来出题，不能抹去已经保存的新提示。

## 执行证据

先行七项在旧实现产生 21 个有效失败断言，0.472 秒，日志为 /tmp/typebar-code-sections-red.log；修正后七项零失败，0.008 秒，日志为 /tmp/typebar-code-sections-green-initial.log。扩展后的 CodeSectionGenerationTests 共 14 项，相关 86 项零失败，43.271 秒，日志为 /tmp/typebar-code-sections-expanded.log。覆盖有限词数、跨批顺序、首分量比较、整段数字过滤、ASCII 规范化、Weakspot 边界、反池／no-space、100／101 词、缓存后新段、原游标隔离、九项真实工厂入口、完成与归档。

Scripts/check-source-code-decoration.mjs 继续在内存执行七个完整实际模块，保留原有 48 组装饰夹具，并增加 15 组分段夹具及九项元数据统计断言；/tmp/typebar-code-sections-source-expanded.log 为通过证据。实际源码的 sectionIndexes 也被断言，但原生通用段身份消费者尚未等价证明。候选、rank、随机单位、配置、活动元数据、间隔、数组、类型与 UI 边界是明确自有适配，不代表原始 RNG 或浏览器运行。较早夹具错误地预期前导空格直接规范化；源码先比较空分量而反证该预期，此次夹具修正不计产品先行失败。

源码驱动与行为优先技能限定改动和先行证据，会话内决策／迁移复核把普通续批与缓存后新段区分，并限定持久化不变；不是独立评审。文档按写作技能区分当前接线和完整等价。所有验证无窗口、客户端使用内存库，不启动 Typebar、播放音频、操作账户或真实用户数据。

## 尚未证明的功能

原版词库内容与规模、源随机分布、全部组合顺序、其他普通或外部多词源、完整 Unicode／半代理、Weakspot 覆盖产生空分量的源码异常、段身份下游消费者、长期代码缓存性能、GUI／IME／VoiceOver、设备和服务部署仍有缺口。当前自有池保证非空规范段，不借内部夹具声称异常路径等价。446 个语言身份、48 个 Funbox 入口及静态审计不代表完整功能覆盖；goal 保持 active。

## 完整串行门禁

最终门禁成功退出：客户端 2,512 项零失败，577.803 秒；服务端 145 项零失败，1.445 秒。795 条人工场景的结构检查、固定参考、原创性、元数据、布局、页面、服务、主题及挑战身份和行为证据审计通过。应用包构建、签名与资源边界检查通过，包未打开；场景结构与身份审计不升级为真人验收或完整功能等价。

十万词耐久用例实际通过，143.277 秒；旧 12,000 次组合字形删除双投影为 0.025935 秒。只支撑各自既有路径，不证明长期代码段缓存性能。完整外层、客户端及服务端日志为 /tmp/typebar-code-sections-full-gate.log、/tmp/typebar-code-sections-client-complete.log、/tmp/typebar-code-sections-service-complete.log。客户端有系统 CoreData／XPC 诊断，但无断言失败，不因此声称系统权限或服务行为已验收。

本轮环境为 macOS 26.1 arm64、Swift 6.2.4、Node 24.19.0，依赖未变；客户端在内存库中运行。源码与文档在门禁期间冻结，仅在成功终态后补录本段。参考仓库保持干净，Typebar 图形进程为零，真实背景练习路径仍不存在，没有操作真实 Typebar 数据、音频、账户或部署。

门禁终态后再次执行源码夹具：48 组装饰、15 组分段和九项元数据统计通过，日志为 /tmp/typebar-code-sections-source-final.log；原有取词／反写脚本的 23 组也通过，日志为 /tmp/typebar-code-sections-pool-source-final.log。最终差异、场景结构及行为证据审计通过，会话内风险复核未发现需要追加修改的问题；上述未验证范围仍然保留。
