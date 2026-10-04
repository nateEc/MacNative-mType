# 节奏目标选择和结束速度

原生 Pace 现在区分结束时的速度与可保存成绩：上一轮读取每次实际结束的精确 WPM，同词组重复链保留最快结束值；最近十次和滚动日最佳读取已保存的完成及中止成绩，PB 只读取符合资格的完成成绩。这是目标选择增量，不是完整光标动画或整个 Monkeytype 重写的等价声明。

## 固定源码规则

参考检出固定为 91bd24bb8513785c7364cbea29296ff7adafac41。生产实现由 Swift 独立编写；探针只在内存读取外部只读参考，不将源码或资产加入应用。

| 路径 | 原版依据 | 本轮实现 |
| --- | --- | --- |
| 上一轮 | [finish](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L829-L857) 在保存资格检查前调用 setter；[setter 和初始化](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/pace-caret.ts#L45-L120) 不取整、不夹到自定义编辑器范围 | completed、bailedOut、invalidAFK、failed 更新；active、abandoned 不更新。重复链按严格大于保留最快结束值；小数保留，低于 1 的目标关闭 |
| 最近十次 | [一次性查询](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/collections/results.ts#L627-L649) 先筛配置／活动标签，再按时间取十次；没有 BailOut 排除条件 | 纳入保存的中止值；精确 WPM 聚合后才取整，不先舍入每条记录 |
| 滚动日最佳 | [查询和配置筛选](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/collections/results.ts#L651-L700) 包含 timestamp 恰好等于当前时间减 24 小时的值 | 不按自然日；中止可成为最佳，最大精确值最后取整 |
| 普通 PB | [PB getter](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/db.ts#L161-L187) 匹配模式、mode2、标点、数字、语言、难度、lazyMode，并守卫当前 Funbox 资格 | 修复仅模式／语言的过宽匹配；候选也须通过原生已有 PB 资格，不接受中止或不合格 Funbox 历史；保留 PB 小数 |
| 活动标签 PB | [Pace 调用](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/pace-caret.ts#L85-L93) 和 [标签 getter](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/collections/tags.ts#L540-L595) 没有当前 Funbox 资格参数 | 当前不合格 Funbox 不阻止读取此前合格标签 PB；历史候选仍须合格，活动标签先筛选 |
| 重复模式优先序 | Pace 初始化先选配置模式，最后才处理 last 或重复标记 | 仅关闭普通 Pace 时使用重复链速度，不盖过自定义／PB／均值目标 |

原生“同类平均”和“今日同类平均”仍是补充模式，不冒充原版 average／daily。它们继续按模式和语言匹配，但也纳入已保存中止，排除未结束与失败记录。

## 精度和兼容边界

PaceGuideSample 从 CompletedTestResult 的已存 preciseWpm、preciseAccuracy 适配；旧记录沿用既有整数回退，不从文字、时长或回放重算。上一轮和当前目标改为进程内 Double，结果分数、服务协议、SwiftData 和归档 23 不变。升级后的节奏目标和旧成绩的派生显示可能不同，这是修正读取规则，不是旧记录重写。

位置投影在转 Int 前限制到提示尾部，避免巨大有限速度乘时长溢出。原生拒绝无穷速度，而原版初始化只排除 undefined、小于 1 和 NaN；这是明确的安全差异，不声称该退化值完全等价。

## 验证证据

先行九项原生测试有 24 个有效行为失败断言。最初 modifiers 工厂参数、扩展夹具 words 参数标签的编译错误均已修正，不计产品反例或绿灯。首轮实现相关 21 项零失败，扩展到十六项新增测试及相关 23 项，全部零失败（0.024 秒）。覆盖小数、低于 1、巨大值、重复 NaN 比较、配置合取、PB 资格及实际结果适配。

Scripts/check-source-pace-selection.mjs 使用 Node v24.19.0 执行完整固定 pace-caret、collections/results 和 db 三个模块，36 组自有夹具通过。Pace setter／init、实际查询构建和 PB getter 执行；标签 PB、mode2、配置、认证、时钟、Caret 和 Query DSL 是明确适配边界。DSL 执行源码查询条件，但不是实际 TanStack、持久化或浏览器；标签 PB 值来自自有适配器，不能声称执行了完整 tags getter。首次缺类型导入适配导致的加载错误不计行为证据。

Scripts/check-source-terminal-timing.mjs 的十个完整模块、64 组结束夹具仍通过；新增每次 finish 的 raw paceWpm 与实际结果 WPM 相等断言，覆盖 AFK／短时长／重复／中止等资格分支。该脚本的 Pace setter 为观测适配器；实际 setter 比较另由三模块探针验证，两个证据不能冒称同一个完整浏览器端到端测试。

完整串行门禁客户端 2762 项零失败、零跳过（666.176 秒），服务端 162 项零失败（1.939 秒）；823 条人工场景结构、固定参考／原创性审计和未打开应用包通过。十万词耐力实际 passed 为 144.835 秒；旧 12000 次组合字形删除双投影为 0.025830 秒。没有在 Swift 测试／构建／打包期间编辑文件。

完整门禁记录 /tmp/typebar-pace-readiness.log，完整客户端／服务日志分别保留为 /tmp/typebar-pace-gate-client.log 和 /tmp/typebar-pace-gate-service.log；package 捕获日志不完整，最终包检查以门禁日志的成功退出和通过行取证。先行、扩展和两个源码日志分别为 /tmp/typebar-pace-selection-red.log、/tmp/typebar-pace-selection-expanded.log、/tmp/typebar-pace-source.log、/tmp/typebar-pace-finish-source.log。客户端有 Apple AddressBook／CoreData XPC 环境诊断，但没有 XCTest 断言失败；不将诊断或绿灯当系统服务验收。

## 尚未完成

本合同上轮未扩大自定义编辑器的 Int、10–300 持久化；后续增量已经接入非负有限 Double、v2 偏好和归档 24／设置 4，当前证据及回退限制见 [自定义 Pace 合同](CUSTOM_PACE_SPEED_CONTRACT.md)。上文 23 版本和 36 组探针是上一阶段历史证据，不代表当前格式或本轮完整门禁。

引语 mode2 原版用 quote.id，原生成绩仍按提示文字匹配；ResultQuoteSource 只有来源类别和标题，不能拿标题伪造唯一 ID。原生标签按本机规范化名称匹配，原版按 ID；原版一次性成绩查询未认证时返回零，原生离线历史可用。PB 从本机历史推导，不是官方 PB 快照，官方删除／快照时序未证明相同。

完整逐词光标定时、错误词修正、RTL／反转／blind／no-space 组合、动画取消与资源生命周期、实机键盘／VoiceOver／窗口和真实旧库未验。本轮不启动 GUI、不写真实背景成绩、不部署，人工清单仅结构验证。会话内迁移、决策与风险复核不是独立评审；功能清单保持部分实现，goal active。
