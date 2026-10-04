# 逐次未完成练习投稿与远程历史

2026-10-04：原生捕获的逐次准确率／活动秒数现已进入投稿、服务存储、重载和私有远程历史，采用明确 v1 能力协商。这个数据链是原版 XP 接入的前置条件，不是奖励切换：现有简化 XP、账户总分、榜单和结果 UI 保持旧路径，旧结果不补造准确率、不回算分数。原生重写 goal 仍 active。

## 固定源码与独立协议

依据只读固定 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 [结果 schema](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/results.ts)、[前端结转状态](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/states/test.ts) 和 [结果控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts)。原版 completed event 含逐次准确率与秒数，XP 非空数组逐项计算；前端次数与聚合来自同一数组。原版控制器还有服务时间覆盖、结果间隔与完整准入链，本阶段未宣称实现这些规则。

Typebar 独立协议 `incompletePractice` v1 只有 `attempts` 内的 `accuracy` 与 `seconds`，复用本机快照，不包含提示、输入、回放、键码、账户声明、最终 XP 或每日奖励资格。结构和字段名属于自建协议，不是 Monkeytype HTTP API。没有参考实现或资产入仓。

## 能力和客户端入口

服务 `GET /v1/capabilities` 声明 `resultIncompletePractice: available`。新证据同时要求 apiVersion v1、service typebar、该能力与 `resultPracticeTiming` 都 available；partial、planned、缺失、错误服务或版本不能授权。原生在指标计算和 POST 前验证，不能向旧服务静默丢掉数组。显式空数组也要求协商，历史缺失仍按旧投稿行为处理。

断网、503 与取消在新证据能力查询中传播，保留既有重试／取消语义。旧服务 404 是能力缺失，随后给出升级提示并保留本机成绩。AccountSession 原账号／endpoint 检查、计算后的凭据守卫和队列政策保持不变；私有接线经代码与编译验证，未运行真实窗口、队列或公网服务。

本机原始聚合秒数不重算，逐次百分位与聚合毫秒化分开。稿件保留原始 restartCount 与 practiceTiming；不能将新数组检查失败改成字段缺失。极大聚合数值用 `Int(exactly:)` 转换舍入后的毫秒，避免 Double(Int.max) 在 64 位向上舍入后直接强转崩溃。该边界由风险复核发现；没有为了产品 RED 故意崩溃应用或编造已复现的崩溃日志。

## 服务校验与保存

准确率有限且 0–100，秒数有限且非负；未知版本、null、缺字段、非法值及超过 1000 项均拒绝解码。新字段显式出现时 restartCount 必须出现，不能默认零。AuthStore 语义准入要求数组项数等于次数、practiceTiming v1 存在；逐次秒数之和与聚合毫秒仅允许每项 0.005 秒、一次毫秒舍入 0.0005 秒和有限浮点误差。空数组要求次数及聚合秒数为零。

沿用自建服务已有 0–1000 次数和 `count * 3_600_000` 聚合毫秒上限；不是原版 schema 限制，也没有给每项额外加 3600 秒硬上限。本阶段不扩展旧总投稿容量或时间限制，不声称所有原版事件已准入。终止活动毫秒仍在本次有效终止时长内；新存储重载也检查该约束。匿名客户端报告不是反作弊或真实键盘的证明。

StoredResult 增加可选数组与可选原始次数。旧无新证据记录不保存／回填新次数，不猜测旧准确率；新结果在既有 actor 和原子持久化事务保存。重复 UUID 保留首次数据；持久化失败用既有 committedState 恢复内存状态，修复自有测试路径后可重试一次。私有列表、详情及 decoder 保留数组和次数；跨账户不能通过 UUID 查询。公共榜单输出和 XP 函数不变。

坏显式字段、缺次数／时长、数量或秒数冲突拒绝重载，原文件不变，不创建空历史。本阶段只有可选服务 JSON 字段，无新 SwiftData 列；归档 26／设置 4、依赖与部署不变。旧 writer 对新字段的保存能力未验证，不能承诺旧二进制重写升级文件安全；保留升级前闭库副本，完整降级与恢复仍待验。

## 验证记录与开放项

客户端先行两项产生两个有效失败断言，日志 `/tmp/typebar-incomplete-publication-client-red.log`；服务先行两项产生三个有效失败断言，日志 `/tmp/typebar-incomplete-publication-service-red.log`。不是编译失败，未改弱断言。首次客户端相关 48 项通过（0.151 秒）；补终止约束与整数上界后相关 49 项通过（0.139 秒），含新增 10 项，日志 `/tmp/typebar-incomplete-publication-client-final-focused.log`。服务首轮相关 53 项通过（0.644 秒），日志 `/tmp/typebar-incomplete-publication-service-first-green.log`。补隔离、并发及 HTTP 错误分支后，测试夹具隐式捕获非 Sendable XCTest 实例导致 Swift 6 编译拒绝；改为在 async let 前捕获值类型时刻，没有弱化并发检查或修改产品逻辑。修正后相关 55 项通过（0.481 秒），含新增 11 项（0.056 秒），日志 `/tmp/typebar-incomplete-publication-service-corrected-focused.log`；此前编译失败不计作行为 RED 或通过证据。

测试使用实际原生投稿准备器、请求／远程历史 decoder、AuthStore、自有临时 JSON 和 XCTVapor 路由，覆盖空／未知、精度／顺序、隐私、边界、能力／断网／取消、旧记录、原 18 XP 不变、重载、重复、坏文件保持、失败回滚、账户隔离、并发及 HTTP 401／400／200。Swift 6.2.4、macOS 26.1，目标 macOS 14；最低系统、真实窗口、实际旧发行服务及 TLS／部署未运行。会话内有界决策、迁移与风险复核不是独立评审，协议测试不替代原版完整控制器或整体等价。

完整串行门禁客户端 2915 项通过（688.093 秒），服务端 211 项通过（2.201 秒），均零失败、零跳过。十万词耐久 147.935 秒，隔离磁盘迁移九项 5.221 秒，客户端新增十项 0.013 秒，服务新增十一项 0.055 秒；独立 XP 二十三项 0.326 秒，其中 2137 组实际源码差分 0.317 秒。857 条人工场景仅结构核对，未开窗应用包与源码边界检查通过。门禁日志 `/tmp/typebar-incomplete-publication-readiness.log`；完整客户端、服务、夹具准备与 manifest 分别保存在 `/tmp/typebar-incomplete-publication-gate-client.log`、`/tmp/typebar-incomplete-publication-gate-server.log`、`/tmp/typebar-incomplete-publication-gate-disk.log` 与 `/tmp/typebar-incomplete-publication-gate-disk-manifest.json`。门禁只清理自己的临时夹具和应用包；没有另保存完整 package-check.log，包检查以门禁尾部记录为准。

门禁后客户端相关 49 项再次通过（0.150 秒），服务相关 55 项再次通过（0.447 秒），均零失败、零跳过；日志 `/tmp/typebar-incomplete-publication-postgate-client.log` 与 `/tmp/typebar-incomplete-publication-postgate-server.log`。此后只补文档验收记录，没有改产品代码。文档技能用于保留历史阶段与当前状态的边界，避免将已保存的匿名证据等同于奖励或全功能验收。

只读时序源码探针再次通过 104 组自有夹具及十个完整实际模块，日志 `/tmp/typebar-incomplete-publication-postgate-source.log`；没有将时序探针称作投稿协议等价、成功保存、浏览器或 IME 验收。857 场景结构及源码边界复核再次通过。

后续仍需完整 XP 匿名计量／Funbox 身份、服务权威配置／时刻／累计／连续天数、不可变奖励快照、小数类型及账户／历史／榜单／UI、长期累计与删除政策；坏行 JSON 排除告警和完整备份恢复仍开放。新增人工场景全部待验收。串行编译和测试，未启动 Typebar GUI、写真实用户库、改系统时间或部署。
