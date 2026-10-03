# 代码词标点装饰与数字替换

本契约保留装饰阶段的历史验证。后续代码多词分段与缓存后新段规则见 CODE_SECTION_GENERATION_CONTRACT.md；下方“多词候选分段”缺口不代表后续状态，其他限制仍未全部解除。

代码主练习现在逐词追加标点，并在其后按 10% 概率用数字替换整个词，再生成实际的修饰器目标。它不再把保留代码自带符号当作标点开关的全部功能。已生成文本、隐藏词界及随机大小写仍只捕获一次，重复练习复用这些目标。完整原生重写尚未完成。

## 固定源码规则

参考只读固定在 91bd24bb8513785c7364cbea29296ff7adafac41。[punctuateWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L46) 对 code_* 不进行句首大写或英文缩写替换，但保留句末符、双引号、单引号、成对括号、冒号、独立连字符、分号、逗号及代码运算符分支。概率判断先消耗随机单位再检查前词与 bound；当前 bound 的最后位置仍消耗句末分支的两次抽样。首批默认 bound 最多 100，续批沿既有全局词序号和 bound 100，不把最后一个有限尾词擅自视为新的一词句子。

括号包含圆、花、方、尖四种，JavaScript 系列额外包含反引号。C 前缀但非 CSS，以及 Arduino，使用扩展运算符选择；该源码前缀也涵盖 Clojure、COBOL、Common Lisp 和 CUDA，不按“是否 C 语法”自行缩窄。运算符与括号是语法符号，不是导入的词库或程序资产。原生 Dockerfile 不是 code_*，保留普通句首大写和非代码括号规则。

前词为句号时，早期包围与冒号等分支会受限，但逗号分支仍可进入。冒号和分号的排除集合不同；句末句号选择包含 0.8，问号严格介于 0.8 和 0.9，其余为感叹号。Tab 再 LF 的迁移发生在标点处理末尾；不开标点不迁移这些控制字符。

[取词后的数字分支](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L957) 在标点之后，严格小于 0.1 才替换整词。[实际 getNumbers](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/generate.ts#L180) 的名义范围为 1–4 位、首位 1–9、其余 0–9。因此数字替换可去掉刚生成的句末符、括号和控制字符；反写或无空格目标随后才生成。

实际整数 helper 先加下界再 floor，不能改成 floor 后加下界。七模块源码夹具确认：长度单位 0.25 的 nextDown 会生成两位，而最大有效单位可因 IEEE-754 加法进位产生五位。原生保留这一可观察例外，不用名义范围夹紧。夹具中的最大单位与最大首位输入加四个零实际得到 90000，不是最初误判的 100000；修正预期后的两项才作为有效产品红测。

## 原生实现与旧数据

CodeWordDecorationPolicy 是独立编写的逐词规则，在 GeneratedCodeContinuation 中候选门槛与 Weakspot 取词之后、实际目标变换之前执行。它使用前一个已变换目标，不从当前批次的原始词重新推测前词。内部单位回调可用于确定性验证；默认仍使用原生随机数，不保存闭包或未生成未来的 RNG 状态。开关均关闭时不消耗装饰随机数。

原有源值、实际文本和词界缓存继续工作。数字替换后的 no-space 会话、有限尾词完成、正式与便携归档及重复练习验证使用实际目标目录。完整原创程序样例和自定义输入未改。没有实体列、成绩字段、设置或服务协议变化，归档仍 22；旧记录保留原提示与固定指标，不补造装饰、不重新出题或回算。回退只改变之后的新练习，不能抹去已保存的新提示。真实用户库、旧二进制及降级未运行。

## 执行证据与限制

三项先行测试在旧产品上出现 141 个有效失败断言（0.509 秒），覆盖 69 个 code_* 单词末尾、主工厂与反写／无空格实际目标；/tmp/typebar-code-decoration-red.log 保留该结果。实现后三项零失败（0.036 秒）。补充有效浮点边界两项后出现四个失败断言（0.415 秒），保存在 /tmp/typebar-code-decoration-float-valid-red.log。修正取整顺序后 CodeDecorationTests 共 23 项，相关 113 项零失败（12.131 秒），扩大代码／反写／英文标点回归 164 项零失败（51.829 秒），两组有重叠，不能相加为独立总数。末次日志为 /tmp/typebar-code-decoration-expanded-final.log、/tmp/typebar-code-decoration-wider-final.log。

Scripts/check-source-code-decoration.mjs 在内存执行七个完整实际模块，包括 words-generator、wordset、funbox-functions、weak-spot、generate、strings 与 util/numbers。48 组夹具验证数字覆盖标点、实际缓存重复、全部主要代码分支、概率边界、前词限制、bound、控制字符、数字范围和浮点端点，以及反写／无空格的实际生成路径；/tmp/typebar-code-decoration-source-float-valid.log 保留通过结果。最终门禁后再次运行，48 组通过，末次日志为 /tmp/typebar-code-decoration-source-final.log；原有取词／反写二十三组也通过，日志为 /tmp/typebar-code-decoration-pool-source-final.log。配置、活动元数据、候选 rank、随机单位、数组边界、类型和 UI 是明确自有适配；不执行浏览器，不复制这些源码函数或资产到原生项目。

初版源码夹具错误地禁止句号后的逗号，实际源码反证后修正预期；另一轮原生测试的元组类型推断编译失败通过显式类型修复。这两项不计产品先行失败。源码驱动、行为优先、根因调试及会话内决策／风险／迁移复核限定本轮实现和证据；不是独立评审。文档技能把完成的分支接线与整体等价分开。

仅验证自有 ASCII 输入及部分控制字符、固定原生池和有效随机单位。原版词库内容与规模、多词候选分段、原始组合顺序、全部 Unicode／半代理、源 RNG 分布与未生成未来恢复、其他词源装饰及数字浮点规则、长期代码缓存性能、真实 GUI／IME／VoiceOver、旧库／设备和服务部署仍未证明等价。446 个语言身份、48 个 Funbox 入口及静态审计通过不升级为全面功能覆盖，整体 goal active。

## 完整门禁记录

修正浮点边界后的完整串行门禁成功退出：客户端 2,498 项零失败（577.639 秒），服务端 145 项零失败（1.439 秒），794 条人工场景结构检查和固定参考／原创性／元数据／布局／页面／服务／主题及挑战身份／行为证据审计通过。原生应用包构建、签名与资源边界检查通过，包未打开；这些检查不升级为真人设备验收。

当前 MostCF 轮实际十万词 passed 行在临时目录清理前捕获，143.519 秒；旧 12,000 次组合字形删除双投影为 0.025193 秒。只支撑各自既有路径，不证明长代码缓存、混合模式或实机性能。完整外层、客户端与服务端日志分别为 /tmp/typebar-code-decoration-final-full-gate.log、/tmp/typebar-code-decoration-final-client-complete.log、/tmp/typebar-code-decoration-final-service-complete.log；through-endurance 文件只是中途快照。客户端含 macOS CoreData／XPC 系统诊断但无断言失败，不代表系统服务与权限行为已验收。

本轮环境为 macOS 26.1 arm64、Swift 6.2.4、Node 24.19.0，依赖未变。测试和包检查串行，客户端使用内存库；未打开 Typebar GUI、播放音频、操作账户、真实 Typebar 库或部署。固定参考仍干净，图形进程为零，真实背景练习路径仍不存在；整体 goal active。

较早门禁在发现数字取整反例后主动终止唯一的本轮客户端 xctest，外层句柄随后确认失败退出，客户端和服务端测试进程均消失，之后才编辑代码。它不是产品套件失败证据，也不是通过；中途日志为 /tmp/typebar-code-decoration-interrupted-full-gate.log 与 /tmp/typebar-code-decoration-interrupted-client.log，临时目录由门禁清理。未启动 Typebar 图形进程或删除用户文件。
