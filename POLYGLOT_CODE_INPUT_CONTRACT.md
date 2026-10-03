# 多语主语言代码输入与历史保护

后续单语言 Dockerfile 输入修复见 [Dockerfile 制表符输入与历史记录保护](DOCKERFILE_INPUT_CONTRACT.md)。下文保留多语阶段的证据和当时未完成的边界。

新 Polyglot 会话以方向检查后确定的主语言决定自动补 Tab 和缩进退格，不以当前候选词的语言决定。主语言可以不在所选词池中；普通主语言不会因抽到代码词而启用这两条规则，Dockerfile 也不属于源码的 code 前缀分支。旧混合配置不补输入标记，导入、显示、回放及原始目标重复不重新生成或回算成绩。本增量仍不是完整 Polyglot 或设备等价证明。

## 固定源码行为

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[插入处理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L340) 在刚输入的键正确、当前或下一字段以 Tab 起头且当前位置仍是 Tab 时，以 Config.language 的 code 前缀排入一个零延迟自动 Tab。请求保留原输入时间；实际执行后才可能排下一个。手动批输入先继续处理，不能把已经排入的请求合并或在执行前重新判断其正确性。

[删除处理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts#L26) 同样看主语言前缀及 codeUnindentOnBackspace。输入非空且全为 Tab、浏览器删除后的余值仍匹配目标前缀时，先记录清字段的整词动作，再以用户原请求的字符或整词删除方式返回上一字段，记录目标位置的字符动作。既有 confidence 和活动状态检查发生在这条分支之前。

[键盘 Tab](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/keydown.ts#L26) 看实际提示是否含 Tab，而非代码候选身份；[换行准入](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-insert-text.ts#L38) 看提示换行或 Zen。原生既有 session 准入到 AppKit 的接线保持不变，本次只测试其提示级判断，不声称完成了实体按键、快捷键组合或 IME 验收。

## 独立原生实现

PolyglotGenerationPreparation 在新会话完成方向处理后写入可选 polyglotUsesPrimaryCodeInput。usesCodeIndentationInput 对新混合会话读取有效主语言并排除 Dockerfile；仅替换自动缩进和两种手动删除入口的三处判断，继续使用既有逐回调队列、attempt ID、防旧回调、时间、错误处理、confidence、隐藏词界和回放位置。普通语言、单代码语言以及手动 Tab 和换行准入路径未改。

这是配置 JSON 的可选加法，归档仍为 22，不新增 SwiftData 实体列、全局偏好键、队列存档或服务协议。缺少标记的旧混合配置保持手动行为，包括已经保存主语言、甚至有上一阶段方向标记的记录；显式 false 也不启用。无有效主语言的孤立标记被忽略，清除主语言同时清标记。实际新结果、分享和重复保留标记；旧结果归档往返相等。下一次真正新生成才进入新规则，真实旧库和旧二进制降级仍未验证。

单语言 Dockerfile 仍保留既有原生 isCodeLanguage 路径，它与固定源码前缀判断的差异尚未修复；这是单独的兼容与历史行为工作，不把本次新混合分支的排除宣称为全局 Dockerfile 对齐。自定义、引语、Zen 和外部词提供器仍需完整审核，新配置准备本身不证明那些模式等价。

## 行为证据

先行九项原生测试在旧实现中有五项失败，22 处断言失败，0.479 秒；其中 18 处直接证明自动输入或缩进删除缺失，另外四处误用了插入位置字段，后续改为严格检查 deletionCharIndex、字段索引和插入位置缺省。首次夹具还有一个不存在的 wordIndex 编译错误，未计作行为红测。生产实现后只剩四处位置夹具失败，没有放宽生产逻辑。日志 /tmp/typebar-polyglot-code-input-red.log、green.log（相同前缀）。

最终新增 16 项零失败，0.078 秒；相关 118 项零失败，3.321 秒（/tmp/typebar-polyglot-code-input-expanded.log）。覆盖全部原生代码身份的主语言路由、未选择的代码主语言、普通主语言与代码候选、Dockerfile、方向改为 RTL 后禁用代码输入、延迟批输入、错误提交与停止输入、两种删除及目标位置、选项关闭、confidence、No Space 词界、新结果／分享／重复、旧方向标记和旧结果、false／孤立标记以及旧 attempt 回调保护。工厂准备是真实实现；输入目标是自有夹具，不把它们当作完整生成词库或实体输入证据。

源探针运行十三个完整实际模块，新增十三组主语言代码输入场景通过，原有八组插入、十组删除、八组普通插入和两组末 SPACE 批输入仍通过（/tmp/typebar-polyglot-code-input-source.log）。Polyglot 标签、目标词、配置、DOM 哨兵、浏览器删除和 FIFO／微任务排空为明确自有适配；不是浏览器事件循环，也未运行完整 Polyglot 生成或 AppKit。原版代码只在只读参考中读入内存，不写入应用或包。

源探针曾误读日志的时间字段，核对实际 getAllTestEvents 后以零起点 timer 和 testMs 检查原时间；后来把删除夹具的 1 毫秒改为输入 7 毫秒之后的 8 毫秒，避免源码按时间排序使尾部比较混淆。这些是夹具错误，不计为产品缺陷，也没有修改只读源码或其日志排序行为。

实现、测试和探针冻结后完整串行门禁通过：客户端 2630 项零失败、零跳过，663.351 秒；服务端 145 项零失败，1.464 秒；804 条人工场景结构、固定参考／原创性／元数据审计及未开窗 macOS 包资源检查通过。最终日志 /tmp/typebar-polyglot-code-input-full-gate.log，清理前捕获完整客户端和服务端日志 /tmp/typebar-polyglot-code-input-client-tests.log、service-tests.log（相同前缀）；包捕获日志末尾不完整，最终包结果以完整门禁日志为准。

同轮十万词耐久实际通过 144.347 秒，旧 12000 次组合书写簇删除双投影 0.025505 秒；不证明多语联合池长期内存或设备性能。门禁前后 Typebar 图形进程为零、真实背景成绩路径不存在，参考仍固定且干净，没有删除用户数据。仅内存成绩库测试、串行服务测试和未开窗包检查，没有真实音频、账户或部署操作。

源码驱动与行为优先技能限定实现；会话内决策、风险和迁移复核以已有主语言的旧记录、Dockerfile、方向切换与延迟旧回调为反例，采用可选输入标记和已有队列保护。文档写作技能区分自动证据与设备验收；这不是独立评审。

## 剩余验收

真实键盘与快捷键、GUI／IME／VoiceOver、原始捕获／Unicode／live-cache、单语言 Dockerfile、完整词提供器与 Funbox 组合、语言加载失败及不足两种时恢复、真实配置 setter／通知与初始化、源内容和 Shuffle／Zipf 分布、memoized 数组累计反转、真实旧库／降级、多语联合池长期内存、主题身份与服务部署仍开放。人工场景仅登记为待验收；不启动 Typebar GUI、不播放音频、不写真实成绩或部署。兼容性矩阵保持部分覆盖，完整 goal active。
