# 历史筛选的 Shift 单选

本机历史和账户历史现在支持按住 Shift 点击模式、难度、时长、字数或引语长度，只保留该组的当前项。点击已勾选项也会保持它开启。普通点击仍逐项加入或移除，可以取消整组；其他筛选组、成绩和预设内容不会被顺带改写。

## 固定源码语义

[固定参考的 ButtonGroup](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/account/Filters.tsx#L193) 在 shiftKey 或 singleSelect 时将同组其他键设为 false，当前键设为 true；否则只反转当前键。本次接通五个仍使用多选勾选框的有限分组。日期、个人最佳、标点和数字保留原生单值选择器，不改变既有筛选语义。

语言、Funbox 和账户标签在该参考组件使用 Dropdown，并不经过上述 Shift 分支。原生语言、修饰器和标签保留原有逐项选择，不以这次增量宣称标签 Shift 等价；此前关于剩余 Shift 范围的描述应按此分组区分。

## 原生输入边界

共享绑定只在控件写入时读取 NSApplication 当前事件的 Shift 标记，不保存修饰键状态或增加键盘监听。没有应用或当前事件时按普通选择处理；其他修饰键不会触发单选。账户历史的语言和修饰器明确关闭该策略。两处历史使用相同绑定，原生勾选框及键盘可访问性结构保留，并提供 Shift 操作悬停提示。

仅改变当前窗口的筛选选择。归档 32、设置 5、偏好 v3、SwiftData 实体与列、服务协议及账户作用域护栏均不变；原有预设编码直接保存得到的集合，不增加格式或迁移。无真实账户操作或数据写入。

## 验证

先将原有逐项勾选行为抽取到共享绑定，六项失败先行回归产生六个预期失败，覆盖已选／未选项、激活时修饰键及实际匹配。补齐 Shift 分支后六项通过；追加默认无事件回退和源码对照，共八项新增测试。

QA 脚本从干净固定参考提取完整 ButtonGroup 点击回调及实际有限分组键，在隔离 VM 中执行 1,136 组选择状态／点击项／Shift 组合。原生绑定逐组对照结果，并核对五组原生枚举；extended 与 thicc 只在测试中映射。不执行整个 Solid 组件、浏览器事件分发或 macOS 真正鼠标输入，源码实现不会进入产品包。

相关 66 项零失败零跳过（2.127 秒）；日志为 `/tmp/typebar-history-shift-red.log`、`/tmp/typebar-history-shift-first-green.log`、`/tmp/typebar-history-shift-focused.log`。实际筛选匹配、其他组保持及 JSON 往返有回归。源码、行为优先和同会话风险复核指导实现，不是独立评审。

完整冻结串行门禁通过：客户端 3,420 项零失败零跳过（743.511 秒），服务 465 项零失败零跳过（10.436 秒）。十万词耐久 151.321 秒、15 项磁盘迁移／冷读 5.621 秒，1,013 个人工场景仅通过结构审计；固定源码、原创性和未开窗应用包／签名／资源检查通过。六个代码／测试／脚本文件的 SHA-256 在门禁前后相同。42 份日志保存在 `/tmp/typebar-history-shift-final-logs.P16WuA`，总日志为 `/tmp/typebar-history-shift-final-readiness.log`。系统联系人诊断及故意只读／坏库测试日志不等于 XCTest 失败。

## 待验收

真实 Shift 鼠标／键盘激活、VoiceOver、窗口焦点与两处界面的预设操作仍待唯一隔离候选验收。MANUAL_ACCEPTANCE 中 HIS-SHIFT-CHOICE-01 和 02 保持待验收；本轮零 Typebar 图形启动。功能矩阵的整体兼容状态及完整重写 goal 不因此关闭。
