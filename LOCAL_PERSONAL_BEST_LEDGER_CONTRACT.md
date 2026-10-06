# 本机个人与标签最佳账本

本机 PB 和文字标签 PB 已从可删除历史分离。练习提示、结果反馈、Pace、个人最佳表及历史奖杯读取同一份 SwiftData 账本，删除历史不删除纪录。custom、zen 和无限模式也有独立分组。完整重写 goal 仍 active；原版账户标签 ID 和独立账本的归档同步尚未完成。

## 分组与接受

规则来自固定 `91bd24bb8513785c7364cbea29296ff7adafac41` 的 [PB 工具](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/pb.ts)、[用户 DAL](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 和 [前端本地 PB](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/db.ts)。mode、mode2、语言、难度、标点、数字、lazy 分组；custom／zen 各固定桶，无限 time／words 用零桶。合资格视觉修饰器不拆桶；引语、中止、混排和不合资格输入不授予 PB，stop-on-letter 使用精确准确率。

严格更高 WPM 才替换整条快照。同速保留首次保存的 UUID、Raw、准确率、稳定性和接受日期，不按较早客户端完成日期覆盖。新本机接受日期取保存时毫秒，完成日期单独保留。个人与每个标签独立比较，较慢个人成绩仍可能刷新标签 PB。活动标签 Pace 取匹配标签最高 PB，普通 PB 不受标签限制；平均／近十次／日最佳继续读历史。

Typebar 标签是最多五个本机文字标签，沿用不分大小写和重音的匹配，并非原版账户 ObjectID 目录。[源码历史标签更新](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/result.ts) 不重授标签 PB；本机后补或移除历史标签也不改变已接受账本。远程账户清空不清本机账本，两种身份分离。

活动标签建议和命令面板也读取保留的标签 PB 名称，删历史后仍可重新选择；这不等于独立账户标签目录。

## 保存与失败

新增第五实体 LocalPersonalBestLedgerRecord，固定单行 UUID，保存版本 1 JSON 数值快照与完整性标记。没有提示、回放、输入计数或凭据；标签名仅存本机。未知版本、缺必需字段、重复分组、非法数值及伪造旧接受日期拒绝。损坏账本触发启动恢复或保存错误，不用历史覆盖为空。

新成绩与账本同一 context、一次 save。重复已保存 UUID 不再次接受，冲突内容拒绝。本机删除和云归档 tombstone 删除都保留账本。导入只把实际插入成绩加入不完整基线，origin=importedHistory，接受日期未知；不以导入时间冒充原接受时间。本机完整重置删除数据并建立已知空账本，不再扫描旧历史。

实际只读 SQLite 保存失败暴露了当前 SDK 的内存 blob 回滚边界：磁盘未提交，已注册账本对象可能仍保留新值。保存与导入失败先 rollback，再显式恢复保存前账本字节；首次失败不留下账本或历史。这不替代磁盘事务，也不证明所有 I/O 错误类型。

另一个真实磁盘反例在最终提交处抛错，复现旧批量删除先落盘的六个失败断言。完整重置因此改用 [逐条标记删除](https://developer.apple.com/documentation/swiftdata/modelcontext/delete(_:))，四实体删除和账本清空在一次保存中提交，失败恢复旧账本；冷重开保留历史和 PB。背景／字体文件移除仍先执行，不承诺跨数据库、文件和设置的全局事务；大型库逐条加载的资源边界还需验收。

## 迁移与回退

旧四实体库自动增加第五实体，启动时仅冻结一次现存可解码历史，不重算。缺语言、修饰器、内容选项或参数不能从旧默认值补造分组。旧纪录 origin=legacyHistory，接受日期空，表格标旧历史日期。旧库包括已删空库均标历史不完整；全新库或完整重置后的已知空账本才可标完整。

归档仍 27、设置仍 4，独立账本尚不导出或同步；仅在账本中保留的已删除历史 PB 不能通过当前归档搬到另一台 Mac。迁移前应关闭 writer、备份完整库目录和 SQLite sidecar；禁止旧版打开升级库或两版混写。回退恢复升级前备份，备份后新增数据可能丢失，不承诺无损降级。

五个无窗口 writer 投影 initial、before-elapsed、before-incomplete、before-local-pb 和 current。新增前一版真实 schema 升级检查：四旧实体保留，账本保存后删除历史，由独立只读进程和实际生产模型冷读取。历史投影由当前 SDK 编译，不是旧发行二进制或 macOS 14／Intel 的升级证明，没有操作真实用户库。

## 验证与开放范围

两项先行分组测试复现十二个失败断言。十九项账本测试覆盖分组、首次同速、毫秒日期、删除冷重开、Pace／反馈、标签及建议、旧空库与缺配置、损坏、隐私、导入、重置、首次失败重试、实际只读 SQLite和最终重置提交失败。测试容器生命周期、归档参数顺序及非法数值夹具已修正，不降低产品断言。另新增一项真实旧 schema 升级测试。

最后定向五十二项零失败、零跳过，耗时 0.283 秒；完整门禁作为最终依据。现有 QA 执行固定 PB／Funbox 和 DAL 源码，不复制其代码或资产到生产。本会话风险复核不是独立评审或整体等价认证。

最终完整串行门禁原生 3044 项／服务 420 项均零失败、零跳过，分别 700.056／9.767 秒。十万词耐久 151.073 秒，十项真实磁盘迁移 4.671 秒。914 个唯一人工场景仅结构通过；固定源码、原创性、未开窗应用包及签名通过。记录 `/tmp/typebar-local-pb-readiness.log`，十五份详细日志保留于 `/tmp/typebar-local-pb-readiness-logs.1RldHq`；门禁正常清理自身临时目录。门禁后只更新文档，没有改生产或测试文件。

单窗口布局、VoiceOver、Query 更新、真实旧发行、macOS 14／Intel、跨设备账本同步、原版标签目录及全功能等价继续开放。本轮零 Typebar GUI，未部署服务。
