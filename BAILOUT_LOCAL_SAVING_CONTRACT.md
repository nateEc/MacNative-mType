# BailOut 本机保存和发布边界

合格的中止结果可以写入本机历史，保留中止状态、真实日期、测量时长和原始回放。未登录时仅在落盘成功后记录最新待认领 ID。新增自建服务协议现可保存合格的中止成绩：明确协商 resultBailout，独立检查服务资格，在存储、历史和重复请求中保留状态。PB、挑战与速度榜排除中止结果，普通均值、练习时长及非 Zen XP 保留。下面分别说明本机与服务的门槛、兼容限制和验证范围；整体重写仍未完成。

## 源码依据与保存规则

固定只读参考为 91bd24bb8513785c7364cbea29296ff7adafac41。[实际 finish](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L887-L1092) 关闭 BailOut 的 AFK 拒绝，但仍检查时长、配置限制、重复、速度和准确率。合格的未登录结果保留待认领状态；登录结果进入正常保存流程，跳过挑战。生产实现为独立 Swift，不复制原版代码、词库或资产。

| 条件 | 原生本机规则 | 原版后端规则和当前边界 |
| --- | --- | --- |
| 最短测量时长 | 所有模式至少 1 秒；Zen 及无限 time／words 至少 15 秒 | quote 没有额外十五秒限制；其他 BailOut 模式要求至少十五秒 |
| 配置限制 | time 至少 15 秒，words 至少 10 词；0 表示无限。custom 的 word／section 至少 10，time 至少 15，finish 无额外配置门槛 | 有限模式可本机保留不足十五秒结果；不能因此放宽服务校验 |
| 重复 | 相同提示重测不保存，quote 除外 | quote 的重复状态在源 finish 中先清除 |
| 准确率 | 两位小数后至少 75%；明确退出排行榜的当前账户至少 50% | 原版后端对非退出账户检查 75%；前后端门槛不是同一函数 |
| 速度 | 非 words 至多 350；words 10 至多 420；其他 words 没有正速度上限，仍拒绝负值和非有限值 | 原版前端布尔条件存在这个差异，后端 WPM／Raw schema 上限仍是 420；自建服务的新中止分支采用 420，旧完成分支的 400／500 上限不改 |
| 结果保存开关 | 关闭时不落盘、不生成认领 ID；结果与当前练习时间仍显示 | 原版未登录内存候选可独立于保存开关；原生认领依赖实际本机记录，这一差异仍保留 |

后端时长依据为 [isTestTooShort](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/validation.ts#L3-L48)。速度表覆盖可表达的常规原生配置；非 words 且 mode2 恰为字符串 10 的源布尔例外没有全组合等价证据。不是用理想化统一门槛代替原版规则，也不把前端无限制当作服务的安全策略。

同提示重复的完成／中止尝试会携带未完成练习时间，即使“太短”先成为展示原因；quote 不携带重复状态。落盘成功才清除账本和生成待认领 ID，首次保存与保存重试共用同一成功路径。落盘失败不能冒充已保存；不会修改真实用户库来验证错误路径。

## PB 挑战和统计消费者

原版 [结果 PB 资格](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/result.ts#L587-L622) 和后端 [PB](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts#L455-L466)、[速度排行榜](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts#L510-L536) 均排除 BailOut。此次前端 finish 和长度函数实际执行；完整后端保存、PB、榜单逻辑仅静态读取，不能当作已运行后端的证据。

本机结果／标签 PB 反馈和 PB 表已按 completed 排除；此次补上当前 PB 的样本状态及历史 PB 曲线／ID 排除。BailOut 数据点保留，但不提高 PB 线；在首个完成结果之前没有 PB，不伪造零。挑战评估器直接拒绝中止，主界面仍只验证 completed。普通近期均值、练习时间及已保存结果总数保留中止；当前进程与落盘记录按 ID 去重，不把“排除 PB”误写为“排除全部统计”。

控制栏、命令、双击快捷键说明、设置和结果／历史标签不再保证“中止必不保存”。未登录认领界面允许明确上传，但说明服务须支持协议并独立校验。拒收时保留候选和本机记录，保留在本机只清除候选指针。远程历史显示中止标签。SwiftUI 接线仅源码和构建检查，尚未点击真实窗口。

## 服务协议和资格

只有 apiVersion=v1、service=typebar 且 resultBailout=available 才可准备中止 POST。resultTerminalTiming 本身不授权中止发布；证据存在时仍须独立计时能力。缺能力、partial、错误身份或版本显式报错；能力查询的断网、503 等暂时失败原样交给重试政策，而不是吞成“不支持”。旧服务的 404 视为能力缺失，不伪装成完成成绩。完成成绩原有可选查询回退不改。

请求增加可选 bailedOut 和 customLimit。新中止为 true，普通完成和旧记录不补字段。customLimit 仅含 mode 和 value：word、section、time、none；none 必须为 0，值限定 JavaScript 安全非负整数，不发送自定义文本。只有 custom 中止携带该限制；缺失、负值、未知 mode、跨模式混入和损坏显式上下文均拒绝。新中止的请求、私有持久化、账户历史和幂等重放保留这两个字段；CSV 在末尾追加 bailed_out、custom_limit_mode、custom_limit_value，旧行留空。

服务对 time、words、custom、Zen 中止要求测量至少十五秒，quote 仍至少一秒；配置最低长度遵循上表。非退出排行榜账户的准确率按两位小数至少 75，退出状态读取已认证用户，不接受请求自报。WPM 和 Raw 不超过 420，继续验证字符计数、速度分母、日期与有效时间。仅明确中止绕过已配置 time 必须完整到期的检查；custom 用未再次按秒舍入的测量值，避免 14.999 秒被误救成 15。服务既有真实／测量时长上限仍为一小时，超过一小时的无限练习还没有完整服务等价。

中止不能成为公开 PB、重置后的新 PB、全局／日／周／好友速度排名或英语一分钟分布样本。即使账户已有完成成绩的日排名，中止回执也不返回它；XP 榜的账户资格与速度结果资格分开。累计成绩数、活动、有效练习时间和非 Zen XP 保留，Zen XP 为零。自有完成次数／速度徽章也仅从完成结果授予，练习类徽章仍按总练习计算。TypebarExperiencePolicy 仍是自建服务的透明近似 XP 公式，不是原版 XP、AFK、未完成奖励与每日 bonus 的完整重写；新中止以测量时长而非配置总时长计算，旧完成公式不回算。

首次接受的 UUID 保持原状态；重试或提交同 UUID 的合法完成形状不得覆盖中止或取得速度资格。待发送队列依旧只存 UUID 与账户／服务作用域，不缓存文字或凭据。支持的中止纳入重试读取；400／不支持停止自动重试，临时网络失败保留队列。按钮、登录状态变化及实际 URLSession 到运行服务的完整链路仍待隔离设备验收，不把政策夹具或进程内 HTTP 称为实机网络证据。

## 数据兼容和升级限制

此次不新增 SwiftData 字段或归档版本。原有 outcome 已能保存 bailedOut；新计时证据仍按 [结束计时合同](TERMINAL_TIMING_CONTRACT.md) 使用可选字段和归档 23。服务增加可选字段和独立能力，不做 backfill。旧结果不重算、不补造计时、限制或认领状态，也不批量把先前未保存的尝试恢复为历史。旧无物理观察的结果仍不补计时，发布时保留明确中止语义和旧分母，由服务独立验证。

升级顺序是服务先升级、客户端后升级，不混用二进制写同一状态文件。能力查询与 POST 并非原子版本协定，反向代理不得混合新旧写服务；查询后切回旧服务仍可能丢语义，这不是已验证的安全拓扑。回滚到旧客户端可能再次把新中止记录误计入 PB 或丢状态；旧服务可能拒绝非 Zen 计时，或忽略新字段并把 Zen 中止误计为完成。新状态不可直接交旧服务重写，回滚须恢复升级前副本或继续向前修复，不能承诺无损降级。真实旧库升级／降级、故障恢复及混合版本仍未实测。未访问真实账户、未部署服务、未写真实成绩库。

## 验证与剩余工作

Scripts/check-source-terminal-timing.mjs 在内存执行十个完整固定源模块，共 64 组自有夹具通过。执行实际存储、清理、计分、keydown、finish、后端长度和登录保存前缀；配置／身份、UI、timer-end、哈希及内存 503 请求端为明确适配。没有浏览器、实际成功保存、真实服务、输入法或设备等价承诺。新增适配只用于观察重复账本和 quote 状态清除，不把缺失适配当作产品失败。

BailoutSavingTests 新增 20 项。先行 15 项产生 50 个预期断言失败；样本开始保留 outcome 后，两项 PB 反例再产生四个失败。相关 77 项最终通过，覆盖真实物理计时、资格、内存 SwiftData、归档／CSV、PB／挑战、统计去重、认领和发布阻断。保存成功／失败政策有自动化，主界面实际磁盘失败和按钮重试仅代码接线。

较早本机保存阶段的完整串行门禁通过：客户端 2738 项零失败、零跳过（667.258 秒），服务端 152 项零失败（1.600 秒），816 条人工场景结构、固定参考／原创性审计与未打开 macOS 应用包检查通过。十万词实际执行 145.405 秒，旧回放 12000 次组合字形删除双投影实际执行 0.025936 秒。代码在测试／构建期间未编辑；真实 Typebar 背景成绩库路径在前后检查均不存在，未删除用户数据。

日志保留在 /tmp/typebar-bailout-readiness.log、/tmp/typebar-bailout-gate-client.log、/tmp/typebar-bailout-gate-service.log 和 /tmp/typebar-bailout-source.log。完整客户端日志仍有 macOS AddressBook／Core Data XPC 环境诊断，无 XCTest 断言失败；不能由绿灯推断系统服务、设备或真实数据库已验收。此增量由会话内决策和风险复核审查，不是独立评审。最强反例为无计时证据的中止误发、样本丢状态导致 PB 和落盘失败后过早清账；前两类有先行失败回归，最后一类主界面接线经代码复核，实际磁盘路径仍待隔离设备验收。

服务阶段新增 BailoutPublicationTests 八项、BailoutSubmissionTests 十项。先行客户端六项产生四个预期失败，服务七项产生八个失败；准确率原始比率反例又产生一处失败，能力查询吞掉断网／503 的反例产生两处失败，修复后相关客户端 54 项及服务全量 162 项通过。测试自有隔离文件重载、幂等与完成形状重复、好友榜、PB epoch、匿名 custom、边界精度、整秒进程内 GET／POST／历史和太短 400；没有调用实际原版成功保存或真实账户。

本次服务阶段完整串行门禁通过：客户端 2746 项零失败、零跳过（666.681 秒），服务端 162 项零失败（1.732 秒），819 条场景结构与固定参考／原创性审计、未开窗 macOS 应用包通过。十万词实际执行 144.956 秒，旧回放 12000 次组合字形删除双投影 0.025679 秒。代码和文档在门禁期间未编辑；完成后仅更新验证记录。图形进程始终为零，背景成绩库检查仍不存在，没有删除数据。

阶段日志在 /tmp/typebar-bailout-client-red.log、/tmp/typebar-bailout-service-red.log、/tmp/typebar-bailout-capability-red.log、/tmp/typebar-bailout-service-expanded.log、/tmp/typebar-bailout-client-green.log、/tmp/typebar-bailout-server-full.log 和 /tmp/typebar-bailout-service-source.log；保留失败阶段与修复阶段的区别。最终门禁在 /tmp/typebar-bailout-service-readiness.log，完整客户端日志在 /tmp/typebar-bailout-service-gate-client.log。门禁自动清理服务详细日志，随后串行 --skip-build 全量重跑 162 项零失败（1.598 秒），日志保留 /tmp/typebar-bailout-service-server-last-regression.log，不冒称它是门禁原日志。完整客户端日志仍含 Apple AddressBook／Core Data XPC 环境诊断，无 XCTest 失败，不能由绿灯推断系统服务或设备已验收。本次为会话内风险审查，不是独立评审。

下一阶段仍需 Pace 的 last／average／daily、弱项等消费者逐项源码对照，不能从 PB／服务修复推断它们完全等价。精确 XP、超一小时服务范围、完整内容、主题、所有组合、IME、VoiceOver、窗口、生命周期、真实旧库／降级和部署验收仍开放，goal 保持 active；本阶段没有启动 Typebar 图形实例。
