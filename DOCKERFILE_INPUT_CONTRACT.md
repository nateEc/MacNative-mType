# Dockerfile 制表符输入与历史记录保护

新生成的单语言 Dockerfile 会话不再自动补 Tab，也不把纯 Tab 字段的删除处理成代码缩进回退。用户输入和删除仍按普通字段处理，实际提示中的 Tab 与换行保持可输入。旧记录的回放、计分和原始目标重复保留之前捕获的自动缩进行为。这补齐了此前多语输入契约明确留下的单语言差异，不证明 Dockerfile 全语料、浏览器或设备等价。

## 固定源码依据

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[实际插入处理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L336) 和 [实际删除处理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts#L26) 都以 Config.language 的 code 前缀决定特殊缩进，不以代码内容类型决定。dockerfile 没有该前缀；正确提交或手动首 Tab 不排入自动 Tab，字符删除只移除当前字段的一项，整词删除清空当前字段而不顺带清上一词。

实际提示有换行时仍可输入换行，confidence maximum 仍先阻止删除；No Space 的已知字段不因为内容为 Dockerfile 而切换为缩进回退。源码探针使用完整模块及自有目标，不读取或复制 Dockerfile 词值。实机快捷键与输入法行为未执行。

## 原生修复与兼容边界

根因是原生 isCodeLanguage 将 Dockerfile 纳入内容家族，输入入口沿用了同一分类。内容分类仍用于原创候选生成、菜单和已有内容行为，不把整个分类改成源码前缀，也不改大小写、装饰或词流。仅在 TestSessionFactory 新生成阶段写入可选 dockerfileUsesLiteralIndentation 为 true，usesCodeIndentationInput 对该快照关闭自动缩进；既有两个删除入口和自动队列继续复用同一判断，没有另建输入或窗口路径。

应用初始练习、重开和异步内容替换均经过工厂；原始目标重复则直接保留 TypingSession 已捕获的配置。缺少标记或显式 false 的旧 Dockerfile 配置继续使用历史缩进规则，导入和解码不补造标记；只有真正新生成才升级。非 Dockerfile 语言的孤立标记解码为 nil，其他代码语言和多语主语言规则不被它禁用。新结果、归档、分享、活动选择和重复保留标记。

配置 JSON 是可选加法，归档仍 22，不增加 SwiftData 实体列、全局偏好键、队列存档或服务协议。旧结果归档往返严格相等，不回算成绩。旧二进制可能忽略新字段，降级后的新目标重复不保证等价；真实旧库和双版本运行仍未验证，没有删除或迁移用户数据。

## 自动化证据

先行八项测试中六项按预期失败，共 19 处断言失败，0.475 秒（/tmp/typebar-dockerfile-input-red.log）。它们区分自动 Tab、首 Tab 后续补齐、字符与整词删除的目标及位置、选项关闭和 No Space；其他代码语言及旧 Dockerfile 重复作为通过的正向对照。生产实现后同组八项零失败，0.011 秒（/tmp/typebar-dockerfile-input-green.log），没有削弱断言。

扩大后新增 15 项零失败，0.026 秒；相关 167 项零失败，8.343 秒（/tmp/typebar-dockerfile-input-expanded.log）。追加实际原创 Dockerfile 生成完成、计时／自定义工厂、结果／归档／分享／活动选择／重复、旧 JSON 字节往返、不回算、false／外语孤立标记、confidence、实际控制符准入、虚拟输入来源与尝试数。可控 streamPrompt 和隐藏词界是自有输入夹具，不作为真实语料或 AppKit 证据。

十三个完整实际模块的输入探针新增八组单语言 Dockerfile／代码前缀对照通过；此前八组插入、十组删除、八组普通插入、两组末 SPACE 批输入和十三组多语主语言输入仍通过（/tmp/typebar-dockerfile-input-source.log）。本轮单语言场景显式移除 Polyglot 适配标签。目标、DOM 哨兵、浏览器删除、FIFO／微任务和配置为明确自有适配，不声称浏览器事件循环、真实生成或设备等价。既有装饰、候选、方向的实际生成源探针仍通过（/tmp/typebar-dockerfile-input-generation-source.log）。

源码驱动、行为优先和根因调试技能限定改动；会话内决策、风险和迁移复核以旧记录、孤立标记、其他代码语言及新生成入口为反例，保留内容分类并采用可选快照。文档写作技能区分自动化与人工验收；不是独立评审。

文件冻结后完整串行门禁通过：客户端 2645 项零失败、零跳过，665.113 秒；服务端 145 项零失败，1.482 秒；805 条人工场景结构、固定参考／原创性／元数据审计及未开窗 macOS 应用包检查通过。完整日志 /tmp/typebar-dockerfile-input-full-gate.log；完整客户端与服务端捕获为 /tmp/typebar-dockerfile-input-client-tests.log、service-tests.log（相同前缀）。包捕获尾部不完整，最终包结果以完整门禁日志为准。

同轮十万词耐久实际通过 145.257 秒，旧 12000 次组合书写簇删除双投影 0.025547 秒；不证明 Dockerfile、多语或长期缓存的设备性能。门禁前后 Typebar 图形进程为零，真实背景成绩路径不存在，参考仍固定且干净，没有删除用户数据。

## 剩余验收

实体 Tab／Enter／Backspace／Option Delete、快捷键和 IME、GUI／VoiceOver、真实旧库与旧二进制降级、全部词提供器和 Funbox 组合、源内容和随机分布、原始 Unicode／live-cache、长期缓存与内存仍开放。完整重写还需要继续核对其他语言、主题和服务等兼容缺口，不因这次修复缩小范围或宣布等价。人工场景登记为待验收，完整 goal active；测试只用内存成绩库与未开窗包，不启动 Typebar、不播放音频、不写真实成绩或部署。
