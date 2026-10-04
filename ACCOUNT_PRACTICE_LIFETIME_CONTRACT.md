# 账户累计练习、活动与连续天数

2026-10-05：自建服务的累计计数、实际键入时长、UTC 活动和连续天数独立于可删除成绩保存。原生资料保留稀疏日期并说明旧历史不完整；SwiftData、归档 26／设置 4 不变。完整重写 goal 仍 active。

## 原版依据与生产行为

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`，只读检查实际 clone。独立 Swift 实现不复制源代码、网页、资产或账户数据。

- [结果控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 累计 `restartCount + 1` 次开始、一次完成，以及 `testDuration + incompleteTestSeconds - afkDuration`；删除历史不重置账户统计。完整证据使用这一时长，旧报告继续使用已验证 practiceTiming／terminalTiming／elapsedTime，最后才退回日期差。
- [用户持久化](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 按提交日期累计 UTC 年内活动；连续天数持久保存，提交时按同日／昨日／断日更新，读取不自动清零。设置日界保留长度与最长记录，并把上次时间设为当前时间；不重新解释历史。
- [公开资料和日历投影](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/user.ts) 的 showActivity 只控制日历，基础连续天数仍公开，包括受限账户。日历取当年稀疏数组及上一年尾部，最多 372 天，空日保留 null；结束日来自当年最后记录，而非读取日期。上一年单独存在及一月初可能少于 372 天。

账户状态与结果、奖励在同一次原子保存中提交；真实写盘失败全部回滚。首次 UUID 计一次，墓碑重试不复活历史、不重计统计。删除成绩保留累计状态及周榜资格时长；明确重置账户清零，删除账户移除状态。XP 使用同一候选状态的连续长度，旧奖励不回算。日界仍是 Typebar 一次设置策略；原版零偏移随后清除的特殊重新设置行为尚未对齐。

## 升级、隐私与恢复边界

新增服务文件 accountPractice v1。缺整个字段才迁移：只取剩余报告和既有奖励墓碑的已知次数／接受日期／冻结时长，已有开始次数取保守下界；无法确认的已删除旧时长不从 XP 猜测。迁移标记 practiceHistoryComplete=false 并在原生资料说明；纯读取不写盘，下一次成功变更才保存。新账户和明确重置后为 true；旧服务响应缺标记仍是未知，不假装完整。

显式 null、重复 UUID、孤立账户、版本／范围错误、活动计数或接受日期不一致、低于已知冻结报告的时长均拒绝加载，原文件字节不替换。校验不是防篡改签名；失去证据的旧历史仍无法精确恢复。客户端接受旧整数数组及新 null 日，只有绘图投影把 null 显示为空格，不改服务数据。

公开活动开关现在明确只隐藏日历，不隐藏累计统计或连续天数。原生增加说明但未做真实窗口验收；本机私有活动图仍使用本机日界和本机成绩，不能把两条数据源混为一谈。

升级前停唯一服务 writer 并保存完整原始 JSON，同时升级客户端：仅支持 `[Int]` 的旧客户端不能解析新的 null 日期数组，这不是已验证的滚动兼容部署。旧 writer 可丢掉新状态／奖励账本，禁止混写或覆盖唯一新文件；回退须停服务并恢复升级前完整副本。真实旧发行二进制、生产库恢复、完整应用备份及本机坏行 compactMap 导出缺口仍未验／未修。

## 可复现证据与剩余范围

507 组实际源码执行：360 连续天数、126 闰年／跨年／稀疏日历、16 累计增量、5 日界更新。只模拟传输与数据库捕获，执行原版函数及完整日期工具；日历用原版固定依赖 date-fns 3.6.0、@date-fns/utc 1.2.0 的实际 ESM，在 VM 内设测试时钟，不改系统时钟、不启动服务。门禁在自有临时目录准备依赖，禁用安装脚本；它们不是产品依赖。

服务新增 13 项及原生 4 项。初始行为红灯确认删除丢统计、按客户端日期重算、隐藏连续天数和无法解析 null；回归发现并修正旧投稿误用墙钟的问题。第二轮有界风险复核以三项实际失败反例补重复键、错日和低累计校验。另以 875 毫秒差异的实际反例修正生产入口：普通提交保存原版整秒接受时间，显式日界设置仍使用精确当前时间。日志 `/tmp/typebar-practice-lifetime-server-red.log`、`/tmp/typebar-practice-lifetime-client-red.log`、`/tmp/typebar-practice-service-first.log`、`/tmp/typebar-practice-corruption-red.log`、`/tmp/typebar-practice-service-final.log`、`/tmp/typebar-practice-timestamp-red.log`、`/tmp/typebar-practice-client-focused.log`。

最终完整串行门禁：原生 2934 项／服务 254 项零失败／零跳过（689.397／2.961 秒），十万词 148.115 秒、隔离磁盘迁移 9 项 4.908 秒，866 场景仅结构核对、未开窗应用包及原创边界通过。门禁后候选校验反例证明非法测试时钟会在内存误锁日界；将唯一服务字段赋值移到校验之后，原生代码未变，完整服务 255 项再次零失败／零跳过（3.057 秒），包含源码差分和新回归。未启动 GUI、部署或操作真实 Typebar 库。最终记录 `/tmp/typebar-practice-lifetime-readiness.log`、`/tmp/typebar-practice-lifetime-gate-client-tests.log`、`/tmp/typebar-practice-lifetime-gate-service-tests.log`、`/tmp/typebar-practice-lifetime-gate-disk-manifest.json`、`/tmp/typebar-practice-boundary-validation-red.log`、`/tmp/typebar-practice-lifetime-postgate-service.log`；临时门禁目录清理前已保留完整客户端／服务日志及磁盘清单。

本会话的行为、根因、迁移、决策与风险检查不是外部独立评审。完整控制器准入（提交前榜单资格、开发豁免、Funbox／stopOnLetter 等）、真实账户与奖励 UI、公共全站不筛选计数、私有账户累计展示、内容／主题身份、实机／IME、macOS 14／Intel 和整体功能等价仍开放。公共统计仍遵守 Typebar 既有 opt-out／审核筛选，不冒充原版全站永久计数。
