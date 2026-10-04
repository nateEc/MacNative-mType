# 终止 XP 计量投稿与服务解析

2026-10-05：原生投稿可将已保存的终止计分单位、活动时长及配置身份，经明确能力发送到自建服务并保存在私有历史。服务有严格解析和计算输入适配器，但生产奖励仍使用旧公式。本阶段不重算旧 XP，不宣称奖励、账户、榜单、UI 或整个重写 goal 已完成。

## 源码依据与匿名字段

参考固定在 `91bd24bb8513785c7364cbea29296ff7adafac41`。依据 [前端完成事件](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts)、[结果 schema](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/results.ts)、[XP 函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 和 [Funbox 元数据](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/funbox/src/list.ts)。原版 XP 的全部改正判断采用最终四项计分统计，不能从累计尝试错误或可见字符数推断。

独立字段 `experienceEvidence` v1 含 `characterCounts` 四项数组、`scoringUnitBasis`、`durationSeconds`、`afkSeconds`、`punctuation`、`numbers` 和原生 `modifiers` 身份。四项分别为计分正确、错误、额外、遗漏，区分 UTF-16 和韩文拆分单位。没有提示、输入、回放、键码、邮箱、令牌、难度声明、最终 XP、倍率或每日奖励资格。

字段投影只读取结果已保存的 sourceUnits、inputMetrics、有效终止时长、AFK 和配置，不重新播放文本或使用当前设置。缺少明确单位或尝试历史时不生成完整证据。保留既有 AFK 值及模型的历史默认语义；这不证明任意旧归档曾明确记录 AFK，不能把匿名报告称作历史来源认证或反作弊。

## 能力协商与计数绑定

服务声明 `resultExperienceEvidence: available`，客户端只接受 typebar／v1／available。它是奖励切换前的加法扩展：旧服务、planned、partial、错误服务或版本沿用原投稿及旧 XP，不假装已经采用原版奖励。有新能力且有明确单位和尝试时，必须同时支持对应 v1 或 v2 输入指标与 practiceTiming，否则在指标工作和 POST 前拒绝并保留本机成绩。既有逐次未完成数组、独立时长、计时和 BailOut 的强制能力及暂时故障政策不改变。

原生校验计分正确等于已保存速度信用，位置匹配＋错误＋额外等于已保存原始单位；单位基础与指标版本对应，AFK 不超过有效时长，活动毫秒与时长减 AFK 的差仅允许一次毫秒舍入。服务要求匹配指标、原始 restartCount、语言身份和 practiceTiming；显式未知版本、null、缺字段、非法形状、非有限值、未知或重复修饰器不能变成字段缺失。

四项数组不能直接求和作为保留输入数。部分前缀中的空格可能同时计入速度信用和额外诊断，原版原始总数使用未包含在四项数组中的 allCorrect。服务因此校验计分正确＋错误、错误＋额外各自不超过保留单位，并绑定计分正确与指标信用；遗漏独立保留。真实原生分类器和服务反例覆盖 `[3,0,1,0]` 对应三个保留单位，不能为通过校验删掉额外诊断或取消速度信用。

沿用自建服务已有 180 万尝试、1000 次重开、3600 秒终止和聚合时间边界；四类单位每项上限 900 万，为韩文最多五倍展开留出空间。这些是 Typebar 的安全包络，不冒称原版 schema 上限。报告时长严格绑定既有有效时长，活动报告保留小数；协议没有扩大历史日期编码或准入容差。

## 服务目录与计算输入

独立目录为 48 个原版 Funbox 身份建立一一映射和数值难度。原生 polyglot 由已保存的 mixedLanguages 配置表示，不能从文本猜测；lazyLatin 属于输入规则，不作为 Funbox。symbolStream、correctBeforeAdvance、clearCurrentWordOnError 是明确自有扩展，没有原版 Funbox 身份／奖励，其独立难度为零；未知身份不是零难度回退。身份和数字是互操作事实，没有复制描述、源实现、网页或资产。

只读探针新增 `--emit-catalog`，实际执行固定完整 Funbox 元数据模块；服务测试核对全部 48 个身份、唯一性、数值和三项扩展。原版 XP 的 2137 组实际函数差分仍独立执行，未用硬编码夹具代替源码。

`ExperienceEvidenceAdapter` 将报告、精确尝试准确率、服务目录解析的难度、逐次未完成数组和既有聚合毫秒组成计算输入。定向测试实际调用独立计算模块得到 62 XP，但实际 AuthStore 回执仍为旧 18 XP。适配器不是完整准入或授权，生产调用者仍必须通过认证、AuthStore 校验和权威账户／配置检查；尚未用于保存奖励。

## 保存与迁移边界

StoredResult 和私有响应仅增加可选服务 JSON 字段，报告存在时保存原始次数。新数据使用既有 actor 事务及原子持久化；同一 UUID 保留首次报告，重载保持分数和小数，跨账户列表／详情不可读取。坏显式字段、计数、单位或时间绑定拒绝重载并保留原文件，保存失败回滚历史及练习计数，修复自有路径后可重试。

原生本机没有新列或字段，报告可从既有便携结果和归档恢复后再次投影；归档 26／设置 4、31 列结果模型、依赖及部署不变。旧未报告记录继续缺失，不回填难度或准确率，不改历史评分。先升级服务再由客户端协商使用新增能力；旧 writer 可能丢弃可选服务字段，混写／降级未保证，升级前保留闭库副本。坏行便携 JSON 排除告警和全应用恢复仍开放。

## 验证与未完成项

客户端先行两项实际失败（`/tmp/typebar-xp-evidence-client-red.log`），服务先行两项实际失败（`/tmp/typebar-xp-evidence-server-red.log`），均为行为断言而非编译失败。首轮客户端相关 31 项通过（0.048 秒），服务相关 55 项通过（0.570 秒）。扩展后客户端相关 60 项通过（0.148 秒）；服务 65 项中仅前缀空格反例失败，日志 `/tmp/typebar-xp-evidence-server-boundary.log`。修正错误守恒假设后服务 65 项通过（0.730 秒），原反例未改弱，日志 `/tmp/typebar-xp-evidence-server-corrected-focused.log`。客户端补真实分类器回归后 61 项通过（0.161 秒），日志 `/tmp/typebar-xp-evidence-client-corrected-focused.log`。

自动化包含真实会话改正、Emoji、终止空格、韩文单位、便携／归档再投影、隐私、能力、非法值、计数绑定、完整源码目录、计算适配、实际 JSON、重载、重复、跨账户、并发、坏文件、回滚及 XCTVapor 401／400／200。没有启动窗口、触及真实 Typebar 用户库、修改系统时间或部署。Swift 6.2.4、macOS 26.1，目标 macOS 14；当前 SDK 测试不证明最低系统、Intel 或旧发行二进制。

补保存失败后的练习计数断言后，最终相关服务 65 项通过（0.671 秒），零失败、零跳过，日志 `/tmp/typebar-xp-evidence-server-final-focused.log`；客户端新增十项、服务新增十二项。860 条人工场景仅结构核对，不是人工验收。

完整串行门禁客户端 2925 项通过（685.726 秒），服务 223 项通过（2.509 秒），均零失败、零跳过。十万词耐久 148.255 秒，隔离磁盘迁移九项 5.270 秒，客户端新增十项 0.027 秒，服务新增十二项 0.274 秒。独立 XP 二十三项 0.330 秒，其中 2137 组实际函数差分 0.321 秒；实际完整 Funbox 目录对照 0.228 秒。860 场景结构、源码边界及未开窗应用包检查通过，不提升人工验收状态。

门禁日志 `/tmp/typebar-xp-evidence-readiness.log`，完整客户端、服务、夹具准备和 manifest 分别保存在 `/tmp/typebar-xp-evidence-gate-client.log`、`/tmp/typebar-xp-evidence-gate-server.log`、`/tmp/typebar-xp-evidence-gate-disk.log`、`/tmp/typebar-xp-evidence-gate-disk-manifest.json`。门禁只清理自身临时目录及应用包，未另存完整 package-check.log；应用包以门禁尾部记录为准。

门禁后客户端相关 61 项再次通过（0.145 秒），服务相关 65 项再次通过（0.722 秒），均零失败、零跳过；日志 `/tmp/typebar-xp-evidence-postgate-client.log` 和 `/tmp/typebar-xp-evidence-postgate-server.log`。只读时序探针再次通过 104 组自有夹具与十个完整实际模块，日志 `/tmp/typebar-xp-evidence-postgate-source.log`，不将时序证据称作 XP 准入、成功保存、浏览器或 IME 等价。此后只补文档记录，没有改产品代码。

会话内决策、迁移、根因及风险复核不是独立评审。服务权威配置、时刻、账户累计及连续天数、不可变奖励快照、小数类型及账户／历史／榜单／UI、长期累计与删除政策仍须接入和验证；报告一致性不能替代原版完整控制器。新增人工场景全部待验收，不提升主题、挑战、内容身份或整体等价覆盖。
