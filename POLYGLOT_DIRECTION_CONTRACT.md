# 多语方向冲突与历史显示保护

后续的主语言代码输入增量见 [多语主语言代码输入与历史保护](POLYGLOT_CODE_INPUT_CONTRACT.md)。本文件保留本阶段的方向证据及当时尚未完成的范围。

新 Polyglot 会话在取词前核对生成主语言和所选语言的方向。只有主语言与全部所选语言方向相反时，才切换到第一种所选语言；双向组合保留主语言，并按它决定段落方向。切换后的主语言随会话、关闭 Polyglot 的返回选择、分享和归档保留。历史配置不补造方向标记，既有提示与成绩不重新生成或回算。本增量不宣告完整 Polyglot、浏览器或设备等价。

## 固定源码行为

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[withWords](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L693) 在所选语言全部 RTL 且主语言 LTR，或全部 LTR 且主语言 RTL 时，将 Config.language 写为第一种所选语言，发出持续 5000 毫秒的提示并抛出空消息 WordGenError；尚未构造联合池或抽取装饰值。所选语言双向混合时不切换，同方向的主语言即使不在所选集合内也保留。

[初始化错误恢复](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L481) 捕获生成异常后重新 init；完整初始化有三次重试上限。[生成返回值](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L629) 的 allRightToLeft 起初取主语言属性，Polyglot 分支只改 joiningScript，不把段落方向改为全部组件的方向；[显示初始化](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L558) 使用这个返回值。因此双向组合也可能以 RTL 为段落基准。

RTL 是可选语言元数据，未声明时按非 RTL 判断。本次只核对所用身份的名称与方向属性，不读取词值。源码配置 setter 会验证、保存并发事件；探针仅适配配置写入，不宣称执行了这些浏览器持久化步骤。

## 独立原生实现

PolyglotGenerationPreparation 在新会话工厂入口准备配置，不消费候选或装饰随机值。配置构造与解码既有规则已将组件规范化为至少两种；准备阶段保留组件顺序，冲突只改生成主语言，不将 mixedLanguages 切成单语言或移除 Polyglot。准备完成后只生成一个正确主语言的池，保留方向提示和已有预览提示。SwiftUI reset 在既有 No Quit 门控后开始新会话，并将会话主语言回写到本窗口的 polyglotReturnLanguage，再保存活动选择；修改组件仍只影响下一次重开。

新生成的混合配置显式记录有效 polyglotBaseLanguage，并将可选 polyglotUsesPrimaryDirection 标为 true。段落方向按主语言决定，任一 RTL 组件仍走原生字形附着的提示位置策略。标记只在新会话准备时写入：旧配置无主语言字段，或者上一阶段已记录主语言但没有标记，均保持历史的全组件 RTL 判断。解码、旧归档导入和原始目标重复不补标记，不重新生成历史文本。

这是配置 JSON 的可选加法，归档仍 22，不增 SwiftData 实体列、全局偏好键或服务协议。新的实际结果、分享与重复保留标记；旧结果往返保持相等。缺标记的旧二进制仍可能忽略新字段，降级后的新生成或呈现不保证等价；真实旧库与旧二进制共存未执行。

## 行为证据

先行 8 项测试有预期的 12 处失败，0.474 秒（/tmp/typebar-polyglot-direction-red.log），包括切换缺失、错误数字字形、双向 RTL 段落及保存主语言。初次实现后唯一失败为夹具比较未排序的 JSON 字节；固定 sortedKeys 后 25 项通过，0.057 秒。扩大夹具曾错误假定无限预览会发上限提示，核对既有策略后改为真实的 100001 词阈值；迁移复核加入方向标记后，上一阶段归档测试改为严格检查新会话唯一新增标记，其余字段不变。这些夹具失败不计为产品红测。

最终 13 项新方向测试零失败，0.017 秒；相关 95 项零失败，32.658 秒（/tmp/typebar-polyglot-direction-expanded-final.log）。覆盖双向保留、双向以 RTL 为基准、双向首词 RTL 而主语言 LTR、相反同向池按首语言切换、主语言不在所选池时保留、只建一池及精确随机消费、旧配置两代显示规则、旧结果归档、活动选择下一次生效、分享／重复标记与预览提示并存。旧多语有限完成及普通／英语／条目／缓存／前瞻回归也通过，各组重叠不相加。

源探针加入完整实际 WordGenError，合计十三模块；六组新方向对照通过（/tmp/typebar-polyglot-direction-source.log），此前二十组候选及所有普通／英语／缓存夹具仍通过。实际生成器验证拒绝发生在洗牌和抽取前、首语言写入与提示参数、第二次生成成功及主语言 RTL 返回。第二次调用是有界探针驱动，不是完整浏览器 init；语言属性、配置 setter、通知、洗牌、词值和 rank 为明确自有适配。原版代码只在只读参考中读入内存，不写入原生实现或包。

实现、测试和探针冻结后完整串行门禁通过：客户端 2614 项零失败、零跳过，664.187 秒；服务端 145 项零失败，1.443 秒；803 条人工场景结构、固定参考／原创性／元数据审计、未开窗 macOS 包资源检查通过。日志 /tmp/typebar-polyglot-direction-full-gate.log，清理前捕获客户端、服务端与包日志 /tmp/typebar-polyglot-direction-client-tests.log、service-tests.log、package-check.log（相同前缀）。

同轮十万词耐久实际通过 145.518 秒，旧 12000 次组合书写簇退格双投影 0.025094 秒；不证明多语联合池长期内存、浏览器或实机性能。门禁仅内存库客户端、串行服务测试和未开窗包；不启动 Typebar，不播放实际音频，不操作真实成绩、账户或部署。门禁前后图形进程为零、真实背景成绩路径不存在，参考源码固定且干净，没有删除用户数据；人工场景仍待设备验收。

源码驱动与行为优先技能限定变更；会话内决策、风险和迁移复核发现已有主语言字段的历史显示风险，采用可选方向标记保护它。根因调试区分夹具 JSON 顺序与产品行为，文档写作复核区分源码、自动测试和设备证据；不是独立评审。

## 剩余工作

语言加载失败、零／单有效语言的禁用恢复、真实配置 setter／通知五秒时序与初始化重试上限、浏览器 memoized 数组跨次反转、完整语料与 Shuffle／Zipf 分布、主语言为代码时的输入键、全部 Funbox 组合及自定义／引语／Zen／外部词提供器、旧整批辅助 API、原始捕获／Unicode／live-cache、GUI／IME／VoiceOver、真实旧库／降级、联合池长期内存、主题身份与服务部署仍开放。原生提示使用既有会话标签，可能在重复中保留，不宣称复现浏览器通知的消失时序。方向准备不能替代这些要求；兼容性矩阵保持部分覆盖，完整 goal active。
