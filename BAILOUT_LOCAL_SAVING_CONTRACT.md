# BailOut 本机保存和发布边界

合格的中止结果现在可以写入本机历史，保留中止状态、真实日期、测量时长和原始回放。未登录时仅在落盘成功后记录最新待认领 ID。PB 与挑战排除中止结果，普通均值和练习时长仍包含它。服务的中止状态协议尚未实现，因此所有 BailOut 成绩发布都在构造成绩 POST 请求前明确拒绝，不能伪装成完成成绩。这是分阶段修复，不代表整体功能等价完成。

## 源码依据与保存规则

固定只读参考为 91bd24bb8513785c7364cbea29296ff7adafac41。[实际 finish](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L887-L1092) 关闭 BailOut 的 AFK 拒绝，但仍检查时长、配置限制、重复、速度和准确率。合格的未登录结果保留待认领状态；登录结果进入正常保存流程，跳过挑战。生产实现为独立 Swift，不复制原版代码、词库或资产。

| 条件 | 原生本机规则 | 原版后端规则和当前边界 |
| --- | --- | --- |
| 最短测量时长 | 所有模式至少 1 秒；Zen 及无限 time／words 至少 15 秒 | quote 没有额外十五秒限制；其他 BailOut 模式要求至少十五秒 |
| 配置限制 | time 至少 15 秒，words 至少 10 词；0 表示无限。custom 的 word／section 至少 10，time 至少 15，finish 无额外配置门槛 | 有限模式可本机保留不足十五秒结果；不能因此放宽服务校验 |
| 重复 | 相同提示重测不保存，quote 除外 | quote 的重复状态在源 finish 中先清除 |
| 准确率 | 两位小数后至少 75%；明确退出排行榜的当前账户至少 50% | 原版后端对非退出账户检查 75%；前后端门槛不是同一函数 |
| 速度 | 非 words 至多 350；words 10 至多 420；其他 words 没有正速度上限，仍拒绝负值和非有限值 | 原版前端布尔条件存在这个差异，后端 WPM／Raw schema 上限仍是 420；自建服务既有校验未改 |
| 结果保存开关 | 关闭时不落盘、不生成认领 ID；结果与当前练习时间仍显示 | 原版未登录内存候选可独立于保存开关；原生认领依赖实际本机记录，这一差异仍保留 |

后端时长依据为 [isTestTooShort](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/validation.ts#L3-L48)。速度表覆盖可表达的常规原生配置；非 words 且 mode2 恰为字符串 10 的源布尔例外没有全组合等价证据。不是用理想化统一门槛代替原版规则，也不把前端无限制当作服务的安全策略。

同提示重复的完成／中止尝试会携带未完成练习时间，即使“太短”先成为展示原因；quote 不携带重复状态。落盘成功才清除账本和生成待认领 ID，首次保存与保存重试共用同一成功路径。落盘失败不能冒充已保存；不会修改真实用户库来验证错误路径。

## PB 挑战和统计消费者

原版 [结果 PB 资格](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/result.ts#L587-L622) 和后端 [PB](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts#L455-L466)、[速度排行榜](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts#L510-L536) 均排除 BailOut。此次前端 finish 和长度函数实际执行；完整后端保存、PB、榜单逻辑仅静态读取，不能当作已运行后端的证据。

本机结果／标签 PB 反馈和 PB 表已按 completed 排除；此次补上当前 PB 的样本状态及历史 PB 曲线／ID 排除。BailOut 数据点保留，但不提高 PB 线；在首个完成结果之前没有 PB，不伪造零。挑战评估器直接拒绝中止，主界面仍只验证 completed。普通近期均值、练习时间及已保存结果总数保留中止；当前进程与落盘记录按 ID 去重，不把“排除 PB”误写为“排除全部统计”。

控制栏、命令、双击快捷键说明、设置和结果／历史标签不再保证“中止必不保存”。未登录认领界面说明服务暂不兼容并禁用上传，保留在本机只清除候选指针，不删除结果。SwiftUI 接线仅源码和构建检查，尚未点击真实窗口。

## 数据兼容和升级限制

此次没有新增 SwiftData 字段、归档版本或服务能力。原有 outcome 已能保存 bailedOut；新计时证据仍按 [结束计时合同](TERMINAL_TIMING_CONTRACT.md) 使用可选字段和归档 23。旧结果不重算、不补造计时或认领状态，也不批量把先前未保存的尝试恢复为历史。

回滚到旧客户端可能再次把新中止记录误计入当前 PB 曲线或显示“未保存”，含计时字段的降级还可能丢证据；旧二进制不能作为兼容验收。真实旧库升级／降级、故障恢复及混合版本仍未实测。未访问真实账户、未部署服务、未写真实成绩库。

## 验证与剩余工作

Scripts/check-source-terminal-timing.mjs 在内存执行十个完整固定源模块，共 64 组自有夹具通过。执行实际存储、清理、计分、keydown、finish、后端长度和登录保存前缀；配置／身份、UI、timer-end、哈希及内存 503 请求端为明确适配。没有浏览器、实际成功保存、真实服务、输入法或设备等价承诺。新增适配只用于观察重复账本和 quote 状态清除，不把缺失适配当作产品失败。

BailoutSavingTests 新增 20 项。先行 15 项产生 50 个预期断言失败；样本开始保留 outcome 后，两项 PB 反例再产生四个失败。相关 77 项最终通过，覆盖真实物理计时、资格、内存 SwiftData、归档／CSV、PB／挑战、统计去重、认领和发布阻断。保存成功／失败政策有自动化，主界面实际磁盘失败和按钮重试仅代码接线。

最终完整串行门禁通过：客户端 2738 项零失败、零跳过（667.258 秒），服务端 152 项零失败（1.600 秒），816 条人工场景结构、固定参考／原创性审计与未打开 macOS 应用包检查通过。十万词实际执行 145.405 秒，旧回放 12000 次组合字形删除双投影实际执行 0.025936 秒。代码在测试／构建期间未编辑；真实 Typebar 背景成绩库路径在前后检查均不存在，未删除用户数据。

日志保留在 /tmp/typebar-bailout-readiness.log、/tmp/typebar-bailout-gate-client.log、/tmp/typebar-bailout-gate-service.log 和 /tmp/typebar-bailout-source.log。完整客户端日志仍有 macOS AddressBook／Core Data XPC 环境诊断，无 XCTest 断言失败；不能由绿灯推断系统服务、设备或真实数据库已验收。此增量由会话内决策和风险复核审查，不是独立评审。最强反例为无计时证据的中止误发、样本丢状态导致 PB 和落盘失败后过早清账；前两类有先行失败回归，最后一类主界面接线经代码复核，实际磁盘路径仍待隔离设备验收。

下一阶段需为服务增加明确 BailOut 语义和独立能力协商，支持合格发布及前后端不同的长度拒绝，排除服务 PB／速度榜但保留可累计练习和非 Zen XP，再测试重试、幂等、历史与混合版本。Pace 的 last／average／daily、弱项等其他消费者也仍需逐项源码对照；不能从本机 PB 修复推断它们已完全等价。完整内容、主题、所有组合、IME、VoiceOver、窗口与生命周期验收仍开放，goal 保持 active；本阶段没有启动 Typebar 图形实例。
