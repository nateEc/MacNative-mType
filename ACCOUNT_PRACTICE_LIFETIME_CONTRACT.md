# 账户累计练习、活动与连续天数

## 原生账户页独立概览

固定 [MyProfile](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/account/MyProfile.tsx) 在账户页把自己的 snapshot 交给 UserProfile，而不是筛选后的成绩集合；[UserProfile](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/UserProfile.tsx) 展示本人资料、累计统计、英语榜名次、PB 和私有活动。[ActivityCalendar](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/ActivityCalendar.tsx) 的账户分支使用本人 snapshot，不受公开 showActivity 限制；原版年度选择与私有历史请求是另外一条尚待对齐的路径，不以最近十二个月代替年度功能完成。

原生 AccountHistoryView 现在在已载入成绩／筛选之前独立展示本人概览：共享现有原生资料组件，不再把服务累计次数、时长、PB／排名误当成当前筛选子集。本人完成率按累计完成／开始向下取整，重启比使用同一个已验证一位 JS Number 中点策略；零开始或零完成不显示 NaN／Infinity。累计时长按原版先四舍五入秒，再显示不截断小时的 HH:mm:ss，而非公开卡旧有的分钟简写。现有单位／小数偏好、资料、徽章、连续天数、八档摘要、全部保存 PB 和 UTC 活动共用组件；本人封禁时仍可读自己的 PB／活动，但不会恢复公开详情或榜单资格。本人活动标题与 PB 标题不冒称公开；图表／过滤统计继续使用旧已载入集合，二者明确分区。

新增只读认证 `GET /v1/profiles/me/overview`：仅由 access token 决定本人身份，不接收任意用户 ID 或隐私绕过参数。沿用详细资料响应 shape，但只在这个认证入口附本人隐藏的近期活动；没有把私有数据加到登录 DTO、搜索、好友、通知或公开 endpoint。成功响应 `Cache-Control: private, no-store`，不返回邮箱、令牌、密码或输入回放。公开 endpoint 即使有本人 token、带 includePrivateActivity 查询也仍遵守公开可见性。读取同一个 AuthStore actor 内的累计账本、独立 PB 及现有排名，函数内不 await、不改盘，不从可删除历史复原累计值，不加新持久字段、缓存或奖励。

客户端复用已有的账户范围／会话 ABA／取消／响应 UUID 校验，再发送带凭据的固定路径；过期 scope 在取凭据前拒绝。真实视图任务身份还包含本人 metadata 与最新账户成绩 ID，资料／徽章／XP／新成绩变化重新读取，相同资料刷新不无谓重开。刷新、失败重试只改请求 revision；旧回应不能覆盖新服务器／账户／资料状态，退出立即隐藏本人数据。没有公共资料 fallback，不改全局 isWorking／状态、XP／成绩／标签缓存。新客户端配旧服务会明确读取失败，但历史筛选／图表仍可用；旧客户端配新服务不访问新增路由。此轮无数据迁移、回填、旧 writer 变化或部署，回退只移除界面和新只读路由，不需要恢复服务文件；更早已有迁移的降级限制不因此消失。SwiftData、归档 33／设置 5／偏好 v3、CSV 41 列保持不变。

有效服务 HTTP 先行两项／四断言失败（0.596 秒，`/tmp/typebar-account-overview-server-valid-red.log`），确认为新入口不存在；最初自有夹具漏填 lazyMode 的编译错误不算产品红测。原生实际账户页接线静态先行一项失败（0.670 秒，`/tmp/typebar-account-overview-native-red.log`），不是已经执行真实点击。服务首轮相关 24 项通过（0.170 秒，`/tmp/typebar-account-overview-server-focused.log`），该轮早于最后 no-store 响应修正，不替代最终证据。新原生八项首轮通过（0.461 秒，`/tmp/typebar-account-overview-native-focused.log`），涵盖真实读取守卫、metadata 任务身份、无副作用、取消／失败／重试和错账户。

既有产品外图表 QA 增加执行固定完整 formatTypingStatsRatio 和 secondsToString，14 个累计比值／8 个秒数与新原生显示对照通过，包含十进制中点、大累计小时与零次数；不复用参考函数到产品，也不运行 Solid／DOM／官方 HTTP。原生界面仍为系统字体、语义色、等宽数字、可展开 PB 与可横滚日历，不新增图像／字体／动画资产。本轮使用源码驱动、行为先行、简化改动、原生设计、迁移安全及同会话有界决策／风险复核；不是独立审查。源、读取和组件证据不等于整页功能等价；年度活动选择、本人编辑／复制公开链接入口、私有徽章全部披露、连续状态提示、正式网络／键盘／VoiceOver／设备等仍开放，完整 goal active。

最终相关原生 129 项零失败／零跳过（28.531 秒，`/tmp/typebar-account-overview-final-related.log`）。首轮相关回归的两个失败来自新增页面证据误把服务路径列入 nativeEvidenceFiles；依照原有 Sources/Typebar 范围约束修正清单，不放松验证器。生产共享资料视图新增一个真实渲染测试：本人浅色、封禁本人深色均完整自适应高度，公开浅色与封禁公开深色仍是 420×620 sheet；不联网、没有头像请求，每项只持有一个从不显示并清理的测试窗口。首轮发现本人“全部公开纪录”及封禁说明不准确，修正生产文案后重跑。最终 25 张组件图保留于 `/tmp/typebar-account-overview-verified-render.S4cF5n`，四张新增整卡图已逐张检查；这不是实际账户页点击或 VoiceOver 证据。

冻结后完整串行门禁退出 0：原生 3,507 项（829.100 秒）、服务 487 项（11.472 秒）零失败／零跳过，包含最终无缓存／公共隐私查询断言；十万词耐久实际执行 159.595 秒，16 项隔离磁盘冷读 3.699 秒。52 页面证据、1,041 条唯一人工场景结构、固定参考／原创边界及未启动应用包／严格签名检查通过。12 个生产／测试／QA／映射文件哈希于门禁前后一致（`/tmp/typebar-account-overview-frozen.sha256`）；运行期间未编辑，之后仅补本文档证据。完整主日志 `/tmp/typebar-account-overview-final-readiness.log`，45 份分项日志 `/tmp/typebar-account-overview-final-logs.Wfv85g`；现成固定依赖仅供产品外源码 QA，未新增产品依赖或跳过源验证。参考 clone 保持固定提交且干净。零 Typebar 应用启动、零部署，不读取真实 Typebar 库或凭据。

完整原生日志仍出现系统 AddressBook/CoreData XPC 连接警告，上一完整基线也存在；这不是已定位根因或真实数据写入的证据。有界采样显示测试进程在执行挑战输入及多语言引语输入，而非据警告推断卡死；最初 PATH 里的 sample 脚本失败后使用 `/usr/bin/sample` 完成两次只读采样（`/tmp/typebar-account-overview-native-sample.txt`、`/tmp/typebar-account-overview-late-native-sample.txt`）。未检查通讯录文件、改变系统权限或作推测修复；警告来源继续开放。本轮挪威语大词库 15.489 秒，未复现上一基线约 896 秒的离群值，不据单轮认定性能问题解决。以下 2026-10-05 及旧门禁计数为历史记录，不覆盖本次增量。

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

上述历史阶段的行为、根因、迁移、决策与风险检查不是外部独立评审。当时列出的私有账户累计展示已由本文顶部增量部分补齐，尚不等于整页验收。完整控制器准入（提交前榜单资格、开发豁免、Funbox／stopOnLetter 等）、真实账户与奖励 UI、公共全站不筛选计数、内容／主题身份、实机／IME、macOS 14／Intel 和整体功能等价仍开放。公共统计仍遵守 Typebar 既有 opt-out／审核筛选，不冒充原版全站永久计数。
