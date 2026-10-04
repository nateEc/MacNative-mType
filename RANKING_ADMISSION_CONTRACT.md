# 成绩榜单准入与历史快照

2026-10-05：独立 Swift 实现把 PB、日速度榜与周 XP 榜的准入判断分开，并冻结首次接受时的判断。账户奖励和练习时长照常累计，后来取得资格不会把未获准的奖励补进周榜。原生客户端投递匿名控制信息，本机 SwiftData、归档 26／设置 4 不变；整个重写 goal 仍 active。

## 原版依据与实现范围

固定只读 clone 为 `91bd24bb8513785c7364cbea29296ff7adafac41`。生产程序不读取、打包或执行参考代码、网页或资产。

- [结果控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 使用提交前的 user.timeTyping 严格大于 minTimeTyping 判断资格；开发环境仅豁免时长，不豁免 banned／lbOptOut。日速度榜另外要求 Funbox 可取得 PB、未中止、没有触发 stopOnLetter。周 XP 分支不受这些成绩条件限制，但要求账户资格、正 XP 及周榜启用。
- [用户 PB](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 与[完整 PB 工具](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/pb.ts) 检查修饰器、quote、按字母停止后低于 100% 的准确率；控制器跳过中止成绩的 PB 更新。PB 不受账户练习时长门槛影响。按单词停止不等于 stopOnLetter，原生端因此不再误排除非满分 PB。
- [Funbox 完整目录](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/funbox/src/list.ts) 的 48 个 canGetPb 标志逐项核对原生和服务目录。三个 Typebar 自有修饰器仍明确禁止 PB，不伪造原版身份；lazyLatin 是输入配置，不当作 Funbox。

服务在旧 practice 值上形成准入上下文，再计算候选累计与奖励，最终和结果一次原子保存。新 snapshot 放在已有奖励墓碑中，没有第二套 UUID 索引。PB 与日榜消费不同标志；Typebar 的 all／week 速度视图消费 PB 标志，仍不是原版完整的缓存／榜单配置实现。周 XP 只累计首次获准的新奖励；零 XP 不借用账户已存在的周榜名次。当前审核／隐私仍可立即隐藏榜单，冻结的拒绝不会在重试时变成准入。删除历史保留 snapshot；明确账户重置／删除才清除。

查询和回执仍额外使用 Typebar 当前资格筛选。因此提高部署门槛可以隐藏原先已获准的条目，快照保存本身不承诺永久公开资格；这一点尚不是原版 Redis 日榜／周榜查询的等价证明。日榜仍按 Typebar 结束日期与本机日界过滤，周界、旧公式奖励日期和原版接受时间／UTC 缓存行为需继续核对。

`TYPEBAR_RANKING_ENVIRONMENT` 缺失为 production，只接受 production／development；无效值拒绝启动配置。它是自建服务显式部署选择，不自动继承 NODE_ENV，也不冒充原版线上配置。原版实际 helper 使用 MODE=dev，源码探针对这一 helper 本身执行测试。生产 minTimeTyping 默认值及可配置范围保留已有 Typebar 合同。

## 投稿与升级边界

自建 v1 新增 resultRankingEvidence=available，报告 version=1、stopOnLetter、modifiers。客户端从已保存配置投影，按字母为 true、按单词为 false，混合语言带 polyglot；不发送提示文本、重放、按键身份、账户资格或准入决策。XP 与排名报告的修饰器集合必须一致，语言绑定、版本、未知／重复身份及显式 null 均严格拒绝。私有列表、详情及标签更新保留首次报告。

能力缺失或身份／版本／状态不匹配时，不能表示的按字母停止和受禁修饰器／polyglot 投稿在度量计算和 POST 前失败，保留本机成绩；安全旧形状沿用旧路径。队列和真实旧服务仍未做窗口验收。

旧奖励缺 snapshot 保持未知，并沿用原有 Typebar 查询行为，不补造历史环境或资格，不改旧 XP。旧客户端直接投递缺控制信息的报告仍是兼容路径，缺失 stopOnLetter 不构成已验证的原版控制证据。历史 PB 仍由剩余结果派生，不能据此声称永久 PB 生命周期已对齐。

损坏 snapshot 版本／范围／决策、与保留成绩不一致或显式 null 拒绝加载并保留原字节；纯读取不写盘。校验不是签名或反作弊。升级前停止唯一服务 writer 并保留完整原始 JSON；旧 writer 可以丢掉 snapshot，禁止混写或回写唯一升级文件。回退需要停服务并恢复完整升级前副本；真实旧发行二进制、生产恢复及滚动部署尚未验证。

## 验证与尚未完成的功能

初始反例记录 `/tmp/typebar-ranking-server-red.log`、`/tmp/typebar-ranking-client-red.log`，证实跨门槛提前准入、周 XP 回补、受禁修饰器／字母停止进入速度榜，以及原生单词停止 PB 误排除。实际源码探针执行完整 PB／Funbox 工具、用户 PB 函数和控制器资格分支，共 12,240 组与 48 个标志；只模拟数据库更新与配置传输，不执行完整控制器、MongoDB、Redis、请求间隔或反作弊。

最初新增服务 10 项、原生 6 项，含首次与重试、删除墓碑、重载、环境豁免、零 XP、匿名协议、旧形状、损坏与 HTTP。服务第一次全量 262 项出现 35 个旧资格预期断言；按源码更新资格断言，仅排序／展示／路由样例显式选择开发豁免。第二次 265 项只剩一项测试生成器的 5 秒 80 WPM 舍入错误，修正样例为 84 WPM，不放宽产品校验。原生定向 6 项已通过，后续加入下述第 7 项旧标志回归。

第一次可完整运行的原生门禁为 2940 项、540.037 秒，出现 1 个既有 PB 回归失败和 1 个未显式启用的耐力跳过，不计作通过。失败显示未规范化的旧布尔标志内存样例被漏判；PB 与投稿现在共享现有规则规范化定义的字母停止回退，保留原断言，另增第 7 项原生回归，不改历史分数或规则存储。日志 `/tmp/typebar-ranking-legacy-stop-readiness-red.log`、`/tmp/typebar-ranking-legacy-stop-client-red.log`。最终完整门禁显式启用 TYPEBAR_ENDURANCE_TESTS=1。

修复后定向 23 项（原生排名 7 项与现有 Pace 选择 16 项）零失败／零跳过，日志 `/tmp/typebar-ranking-legacy-stop-focused.log`；先行服务全量 265 项零失败／零跳过，日志 `/tmp/typebar-ranking-service-final.log`。

最终完整串行门禁通过：原生 2941 项零失败／零跳过，687.769 秒；服务 265 项零失败／零跳过，3.464 秒。十万词耐力实际执行并通过，148.619 秒；九项隔离磁盘迁移通过，3.603 秒。实际排名源码 12,240 组与 48 个标志、账户源码 507 组、869 条人工场景结构、未开窗应用包与原创性边界均通过。869 条仅表示清单结构完整，不表示人工验收。最终日志 `/tmp/typebar-ranking-release-readiness.log`、`/tmp/typebar-ranking-gate-release-client-tests.log`、`/tmp/typebar-ranking-gate-release-service-tests.log`；日志为本机会话证据，不作为仓库运行依赖。全程没有启动 Typebar 图形实例，未操作真实 Typebar 库或部署。

本资格阶段查询核对发现：[原版周 XP 服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/services/weekly-xp-leaderboard.ts) 的列表和名次 getter 使用 parseInt 投影公开 totalXp。后续 [周 XP 读取阶段](WEEKLY_XP_READ_CONTRACT.md) 已独立实现公开投影与双重名次，区分内部小数累计、奖励小数和公开显示。本资格探针本身不覆盖这些 getter，后续完整服务／Lua 探针才提供对应证据；缓存保留、更新排名和周界仍开放。

首次门禁因调用者重设 PATH 漏掉 rg，辅助串行扫描缺命令；该次自有 gate／测试已明确终止并保留 interrupted 日志，不计作通过。入口增加 rg 必需检查，缺工具会在任何 Swift 任务前退出；以保留原 PATH 的环境重新执行完整门禁。

会话内行为、源码、迁移、决策、根因和风险复核不是外部独立评审。本轮不开 Typebar 图形实例，不操作真实库或部署。完整日榜启用／15 与 60 秒及语言配置、全时 PB 分组／持久缓存与删除后 PB、提交间隔、反作弊、原版全站统计、奖励 UI、旧二进制、真实队列／设备／IME、macOS 14／Intel、主题身份和整体功能等价仍未完成，不能把准入差分升级为全功能验收。
