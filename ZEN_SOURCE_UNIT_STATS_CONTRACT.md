# Zen 无目标字段单位统计

后续普通已知源字段捕获、最终计分与末 SPACE 重入已另行实现；当前范围与证据见 ORDINARY_SOURCE_UNIT_STATS_CONTRACT.md。下方 ordinary 待办及门禁数字保留为 Zen 历史阶段，不代表新的覆盖已经通过设备或所有消费者验收。

固定只读参考 91bd24bb8513785c7364cbea29296ff7adafac41。独立 Swift 实现，不复制官方实现、主题或词库；完整重写 goal 仍 active，本增量只覆盖新 Zen 结果分类。

## 源合同与实现

[words-generator](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L429) 对 Zen 使用零词限及空词库；[初始化](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L369) 重置词目录，[addWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L572) 仅加空显示节点。[buildEventLog](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/data.ts#L36) 取该目录而不是最终输入作为 targetWords。上述初始化／生成路径只读取证，未运行完整 TestLogic。

[getChars](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts#L424) 对没有对应源目标的字段使用规范化输入本身；读取各字段最后源快照、首次桶顺序和最高非空字段。不能用最终渲染字形总数冒充 UTF-16 分类，也不能把停止键的 data 追加进 inputValue。

原生 RecordedInputFieldStats 现在同时接收有效 no-space 和 Zen 日志快照，改名后的 stored property 为 recordedFieldStats。Zen 以空源目录调用既有独立单位分类器：allCorrect 与 correctWord 均为分类读取到的输入单位；错误、多打、漏打为零。no-space 原算法及其整词信用不改变，ordinary／未知隐藏词界仍不新增分类。Zen 标准模式过滤器会排除需要目标目录的 no-space Funbox。

`🙂 é` 保存三原生字形及五源单位。四项原生 characterStats、typedCharacterCount、correctCharacterCount、WPM／Raw、准确率和 inputMetrics 保留原算法。UTF-16 分类只决定结果／详情／历史／无障碍及 CSV 的既有可选单位展示，不把 allCorrect 改作速度信用。退格、重入和新的练习会话以真实快照更新，不携带旧缓存；三十单位上限前拒绝的键没有插入事件，不能计入源文本。

## 数据边界与会话内有界复核

默认归档仍为 20，含 sourceUnits 的最低格式仍 19；伪装 1–18 拒绝。未改实体列、设置或服务协议，沿用 characterStatsData 的可选 JSON。独立自有旧 18 Zen 记录保留固定 17／29 WPM 和 77 准确率，不补造单位或回算，旧 CSV 单位列仍留空。真实旧库、降级、混合版本和跨设备未验证；旧程序可能忽略新 JSON 后覆盖，必须备份而非让旧二进制写唯一副本。本轮仅使用内存实体，无真实库写入或部署。

会话内决策／风险／迁移复核（不是独立评审）的反例：多单位输入不能覆盖原生字形；早期 ASCII 快照不能在后续 Unicode 转换时丢失；被停止的 Shift 尝试和输入上限不能成为接受单位；末字段删空后重入要替换快照；未知目录不能默认为已验证统计；旧档不得通过剥离新字段来假装可降级。相应回归覆盖上述边界，未改变普通模式的计分／空格提交合同。

Scripts/check-source-terminal-history.mjs 只读加载固定完整 stats／helpers／strings／numbers 四模块，新增十组自有 Zen getChars 输入输出：代理／组合符、拒绝键、全空字段、空 LF 槽、末 SPACE、韩文及 emoji、源空格规范化、删除／重入、Tab 与晚 Unicode。Korean 状态明确 false，若调用适配的 Hangul 拆音即报错；韩文字面 fixture 不证明有目标的 Korean 拆音等价。Config／类型是显式绑定，不运行物理输入 handler、真实浏览器／DOM／RAF／IME 或结果视图。旧六组历史与二十一组分类夹具保留。

## 验证与剩余工作

先行四项因 sourceUnits 缺失产生六处失败（0.429 秒），接入后四项零失败（0.006 秒）。十二项新增测试与相关测试合计八十三项零失败（0.391 秒）；后追加失败 minimum-burst／bailout 用例，最终十三项新增测试及相关扩展 117 项零失败（0.443 秒）。新增 INPUT-ZEN-SOURCE-UNIT-CLASS-01 只是待设备验收，不因自动化升级实机状态。

最终完整串行门禁客户端 2,349 项零失败（442.963 秒），服务端 131 项零失败（1.389 秒）；782 条人工清单只作结构核对，固定参考／原创性／元数据／页面／服务／布局／主题与挑战等审计及未打开应用包检查通过。当前详细日志 9gLK3o 在清理前取得十万词实际 passed 行 87.862 秒及旧 12,000 次双投影 0.024940 秒，不用历史轮次替代。门禁成功退出，参考固定且干净，Typebar 图形进程为零，真实背景成绩路径不存在；无 GUI、真实音频／库写入／部署，不把普通耐久或审计绿灯扩展成 Zen／混合性能或全部功能等价。

ordinary 结果源分类仍未捕获：[实际 helpers](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/helpers.ts#L123) 对错误末 SPACE 提交的 inputValue 使用 trimEnd，记录时的 lastWord／commitsWord／correct 与停止／保留分隔符必须分别取证，不能直接启用 no-space 缓存后宣称普通模式全等价。现有 QuoteSourcePolicy 边界空白表及 SavedTextInputHistoryPolicy 的历史进度投影不自动证明结果分类合同，后续需保留原始代理单位并对照源快照。有目标的 Korean 拆音、完整 flags／其他消费者、真实窗口／VoiceOver／IME／Firefox、真实旧库／降级、官方资源身份、部署和混合大规模性能继续开放。94 配置和部分 Funbox 的既有覆盖状态不升级；不启动 Typebar GUI、真实音频或外部服务。
