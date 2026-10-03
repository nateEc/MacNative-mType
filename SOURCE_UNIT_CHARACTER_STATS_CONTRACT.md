# 原版字符单位分类与原生展示

2026-10-03 后续 Zen 捕获：新 Zen 会话使用空源目录读取已记录字段单位，四项原生字形及速度／准确率算法保留；正式默认仍 20、单位统计最低仍 19，真正旧记录不补算。普通模式捕获及有目标 Korean 拆音仍开放，不把 Zen 空目标 fixture 当拆音证明。当前合同与验证见 ZEN_SOURCE_UNIT_STATS_CONTRACT.md；下方格式 19 与门禁数字为历史阶段。

固定参考 91bd24bb8513785c7364cbea29296ff7adafac41；独立 Swift 实现，不复用官方代码／词库／主题资产。完整重写目标仍 active，本增量不是整个产品的完成声明。

## 源码合同与独立算法

[countChars](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/strings.ts#L417) 用 UTF-16 位置比较；[getChars](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts#L424) 先规范源空格，读取原字段末快照、最高非空字段与首次词桶顺序，timed／bailout 可给活动词前缀信用，缺目标回退到规范输入。保存历史的 clearedNextWord 不抹掉计分桶。

[buildCompletedEvent](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L700) 将 correctWord／incorrect／extra／missed 交给 [结果页](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/result.ts#L473)，charTotal 则为 allCorrect + incorrect + extra。不能把首项偷换为所有匹配位置。

| 自有输入／目标 | 部分活动词 | allCorrect／correctWord／incorrect／extra／missed |
| --- | --- | --- |
| ax／abcd | 是 | 1／0／1／0／0 |
| ax／abcd | 否 | 1／0／1／0／2 |
| ab␠／ab␠cd | 是 | 2／3／0／1／0 |
| 末词回退后的 a／cd 两桶，对 ab／cd | 仅 cd | 3／2／0／0／1 |

原生 ResultUnitCharacterStats 独立 zip 已输入／目标的重叠单位，再分别计算尾部多打和漏打，不复制源循环。已知空目标和缺失目标不同；规范空格不改变单位总数；半代理单位保持原始单位，不经损失性 String 解码后比较。correctWord 可因部分词中的 SPACE 大于 allCorrect，因此校验只要求非负、总输入加法不溢出与信用不超过总输入，不设错误的 correctWord ≤ allCorrect 约束。

RecordedInputFieldStats 为新有效 no-space 会话累计该五项，并以同一个 correctWord 生成速度信用。失败无限字数也属于原 timed 合同，结果信用／新分类使用既有 ResultIntervalSamplingPolicy 门控；有限失败保持漏打。当前不为 ordinary／未知词目录或 Korean 补造同等证据。

## 消费者与迁移

ResultCharacterStats 旧 matched／incorrect／extra／missed 四项是原生字形描述，新增可选 sourceUnits 是单位快照，不改旧四项语义。结果页、详情页、历史行与无障碍共享原生标签／值策略：有单位快照显示 UTF-16 单位，并用 correctWord 作首项；旧记录显示旧字符描述。未打开应用，不以纯策略断言替代真实窗口／VoiceOver 验收。

CSV 在旧列后追加 source_matched_utf16_units、source_credited_utf16_units、source_incorrect_utf16_units、source_extra_utf16_units、source_missed_utf16_units。旧列位置和原义不动，缺快照的旧行新列为空而非零，提示和按键日志仍不导出。严格依赖 CSV 总列数的外部消费者需适配，不冒称零兼容影响。

默认正式归档 19，含单位快照最低 19，伪装 1–18 拒绝。真正旧档案不依据现有目录／日志重新分类或回算固定速度。独立自有 15 目录、16 位置、17 收缩、18 清空夹具继续证明最低版本及旧值不变，不能把新会话删字段再贴旧版本当历史证据。内存 SwiftData 和既有 characterStatsData JSON 往返通过，实体列、设置与服务提交协议未变；真实旧库、降级、旧二进制可能忽略可选字段后覆盖、混合运行仍未验。先备份，别交旧程序覆盖唯一副本；本轮未操作真实库或部署。

## 自动化证据与剩余工作

最终第二轮完整门禁客户端 2,306 项零失败（443.640 秒），服务端 131 项零失败（1.509 秒）；779 条人工清单仅结构检查通过。当前 YBB7I1 实际 100,000 词 passed 行在清理前读取，88.201 秒，旧 12,000 次双投影 0.025719 秒。固定参考／原始性／元数据、布局、页面与服务、主题与挑战身份及行为证据审计通过，未打开应用包构建／签名和资源边界通过；不升级未验身份。门禁成功退出，参考检出仍干净且固定，Typebar 进程为零，真实背景成绩路径不存在，没有真实库写入或部署。普通十万词测试不证明 no-space／混合性能。

十三项新原生测试：回退三读者、代理与原生字形、正确前缀／错前缀、失败无限／有限模式、版本拒绝／往返、真实旧 18 夹具、十四组常见分类、规范空格／半代理、缺目标与已知空词、多列 CSV／旧行空值、负值／溢出／超额信用拒绝、内存实体、未知目录与旧 JSON。

先行四项九处失败（0.462 秒）后转绿（0.018 秒），扩大首轮 176 项／31 处失败（1.410 秒）保留：是两个旧最低版本测试借用了包含新统计的当前会话；改为独立旧夹具后 177 项零失败（0.980 秒）。无限字数反例另有一项一处失败（0.445 秒）；修正后模式扩展 183 项零失败（1.008 秒），旧 12,000 次双投影 0.025292 秒。最终门禁结果见本节首段；下方首轮失败为历史证据。

完整门禁首轮客户端 2,306 项／14 处失败（442.188 秒），没有进入服务端或打包；当轮实际 100,000 词 87.222 秒、旧双投影 0.025309 秒保留为失败轮证据。目标词目录旧最低版本测试也借用了新会话；改为独立目录-only 版本 15 夹具，保留低版本拒绝与旧固定值后，续修 201 项零失败（1.136 秒），旧双投影 0.025552 秒。第二轮结果见本节首段，不删除首轮失败记录。

Scripts/check-source-terminal-history.mjs 在只读干净固定检出加载完整 stats／helpers／strings／numbers 行为模块，旧六组日志与新 21 组自有 UTF-16 夹具通过（16 组实际 countChars、5 组实际 getChars）。类型／Config／Korean 是显式适配，Korean 若调用即报错；未执行完整 TestLogic、DOM／RAF、真实 IME／Firefox 或结果视图。结果映射来自源码阅读，不是浏览器渲染证据。会话内有界复核，不是独立评审。

其他模式的单位快照捕获、Korean、完整事件 flags、其他曲线／声音／挑战／复制消费者、实机、真实旧库、官方资源身份、部署及 no-space／混合大规模性能仍开放；普通十万词耐久不证明这些路径。后续已对固定完整 replay-ui 取证，并仅对有效已捕获目录接入 FieldReplayPlan／ReplayTimelineView 与序号 seek；缺目录守卫仍保留，不从扁平提示猜词界。详见 NOSPACE_FIELD_REPLAY_CONTRACT.md。人工设备状态保持待验收，不因清单或测试绿色升级。
