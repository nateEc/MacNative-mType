# 周 XP 时长 活动时间与资料快照

Typebar 周 XP 列表与个人名次现在公开缓存的累计键入秒数及最后活动毫秒，原生界面显示时长和本地活动日期。新获准投稿保存当时的徽章与头像，不用查询时的当前资料替代历史快照。旧来源保留未知，不回填。本阶段不表示 premium、完整缓存恢复、原版奖励体系或整体纯原生重写已完成。

## 原版源码规则

固定参考提交为 91bd24bb8513785c7364cbea29296ff7adafac41。[原版成绩控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 在获准且 XP 为正时，将名称、徽章、Discord 标识与头像、premium、累计活动秒及 Date.now 毫秒交给周榜。[完整周榜服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/services/weekly-xp-leaderboard.ts) 在写入时累加旧条目的时长，再替换其余资料；缺 optional 字段的新写入清掉旧值，不在查询时读取账户更新。

[原版周榜表格](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/leaderboard/Table.tsx) 显示 XP、键入时长及最后活动日期。时长先 Math.round，再以始终显示小时和分钟的冒号格式展示；超过一天继续累计小时，不按天截断。日期按浏览器本地时区展示。[完整日期工具](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/date-and-time.ts) 和数字工具是 QA 的只读执行参考，不是生产依赖。

## 独立实现与协议

四个周 XP 列表／名次端点添加可选 timeTypedSeconds Double 与 lastActivityTimestamp 整数毫秒。内部继续使用已冻结的接受分区与缓存活动时间；不使用 JSON Date 的整秒时间来覆盖毫秒。重试不再累加时长或刷新活动时间，历史删除保留缓存；缓存过期或清除仍按前一阶段合同。

每个缓存条目增加可选 profileSnapshot version=1。新投稿总是保存已知快照，包括没有徽章／头像的空快照；真正旧条目缺字段保持未知，不用当前资料回填。选择／清除徽章或改头像本身不刷新快照，下一次新的获准投稿才替换。快照、秒数与活动时间随奖励和结果原子保存，失败回滚后重试只入账一次。

Typebar 继续使用自主设计的徽章，不复制原版徽章资产或权益。头像快照只有在当前账户仍明确允许头像且仍有有效 Discord 身份时显示；关闭开关或解除绑定立即隐藏。此隐私护栏比原版陈旧缓存读取更严格，保留并明确为未对齐差异。premium 权益、原版徽章编号和完全一致的展示标志仍未实现，不添加固定 false 来假装存在完整权益机制。

旧奖励兼容路径没有可信周榜活动数据。只有旧来源或混合旧／新正分数时，时长与活动时间均缺失；不把部分新缓存的时长标为全周总时长，也不从终身时长或私有成绩反推。旧缓存已经有可信时长／活动毫秒、但缺资料快照的情况保留时间值，徽章／头像未知。

## 原生界面与兼容

原生列表保留系统色和字号，右侧 XP 下显示时长，姓名下显示活动日期；个人名次也显示同一数据。时长保留原版非负半秒舍入和 HH:MM:SS 规则，零为 00:00:00，未知为 —。活动日期使用本地化系统格式与当前时区，不声称字面英文日期与原版相同。名称仍是资料入口，徽章与头像继续沿用既有控件。

新原生解码接受缺失／null 表示未知，但拒绝错误类型、负或过大的时长、分数毫秒及不安全日期。旧原生可忽略新增字段，新原生连接旧服务显示未知。SwiftData 列、归档 26 与设置 4 不变，没有操作真实用户库。

服务缓存字段是可选增量，缺失可加载，显式 null、未知快照版本、非法头像或超界展示字段拒绝且不覆盖原文件。验证只是结构与既有奖励上界检查，不是资料快照签名。旧服务 writer 会丢失不认识的快照，不能新旧混写；升级前完整备份、单 writer 切换，回滚需原副本或向前修复，不承诺无损降级。

## 验证与剩余工作

服务红阶段三条预期失败、原生两条预期失败已确认。最初测试夹具改变时长未同步 WPM，先修正夹具才复现有效行为反例；生产成绩校验未放宽。服务接线一度使用公开响应而非存储账户，编译失败单独保留，不算行为证据。修正后先行服务全量 300 项通过，7.407 秒，零失败／零跳过。

真实隔离 Redis 6.2.6 中的完整服务与四个完整 Lua 的十二步比较扩展到徽章与头像替换／清除。QA 将临时数字徽章编号映射为自有测试值，只比较数据更新，不据此声称实现原版权益。完整前端日期与数字工具执行十八个边界时长样例，与独立 Swift 格式化逐项比较；date-fns 3.6.0 与固定 frontend package 匹配。未启动浏览器或 Typebar GUI，未改宿主机时间。

四端点 HTTP、毫秒保留、重试／历史删除、头像更新与隐私／解除绑定、旧未知快照／显式损坏均有自动化。混合旧奖励与保存失败／重载另有回归。最终串行门禁结果另记录。原生视图目前只验证代码与编译，不冒充实际渲染、500 点宽度、大字体或 VoiceOver 通过。

复核服务全量 302 项通过，6.804 秒，零失败／零跳过；原生 metadata 与名次定向十项通过，0.326 秒，包含十八个实际前端工具样例。日志分别为 `/tmp/typebar-week-metadata-service-reviewed.log` 与 `/tmp/typebar-week-metadata-native-reviewed.log`。结构清单为 881 条，新场景仍待验收。

完整门禁首次在服务证据清单根目录校验处停止，尚未执行全量测试；移除误列在该清单中的原生 Tests 路径，保留实际原生测试及既有校验规则。失败日志另存为 `/tmp/typebar-week-metadata-manifest-rejected.log`，不能将此失败计作已通过。

修正后的完整串行门禁通过：原生 2951 项，687.217 秒；服务 302 项，6.857 秒，均零失败／零跳过。十万词逐词耐久 148.723 秒，九项隔离磁盘迁移 3.363 秒。十八个前端时长样例、十二步真实 Redis 缓存差分、原有 20,724 组日期／控制器样例及其余源码检查、881 条人工场景结构和未开窗应用包／原创边界均通过。CoreData XPC 警告按最终 XCTest 汇总判断，不当作独立结论。主日志 `/tmp/typebar-week-metadata-final-readiness.log`；完整测试副本 `/tmp/typebar-week-metadata-final-client-tests.log` 与 `/tmp/typebar-week-metadata-final-service-tests.log`。使用本轮独立临时父目录，代码在门禁中冻结，结束后仅补记文档。无 Typebar GUI、真实用户库、系统时钟修改或部署。

真实单窗口人工场景、macOS 14／Intel、旧发行程序升级、premium、每周奖励队列与 brackets、好友同分、PB 缓存、公开统计、规模与进程时钟回拨恢复，以及全部功能等价仍开放。goal 保持 active。
