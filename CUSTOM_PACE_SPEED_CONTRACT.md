# 自定义 Pace 小数与格式升级

自定义速度现在是非负有限 Double，不再取整或限制为 10–300 WPM。零及不足 1 的值可以保存，但不会产生可见 Pace 目标。此增量补设置／预设／归档路径，不代表完整光标动画或 Monkeytype 整体功能等价。

## 源码依据与独立实现

只读参考固定为 `91bd24bb8513785c7364cbea29296ff7adafac41`。生产 Swift 实现不导入原版代码或资产。

- [配置 schema](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/configs.ts#L353) 是非负 number，没有整数或 300 上限；这是静态检查，没有执行完整 Zod schema。
- [设置表单](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/settings/custom-setting/PaceCaret.tsx) 同值提交不变；修改时仅 off 切 custom，PB 等模式保留。[命令元数据](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/config/metadata.tsx) 指定 custom override、caret 设置组和不重开。两条原生入口共用校验，但保留各自模式规则；只刷新目标，不清空当前输入。TSX、InputField 和元数据仅静态取证，没有执行浏览器表单。
- 完整 pace-caret／collections/results／db 三模块探针新增十组 custom 夹具，总计 46 组通过。初始化按原版保留非负小数及巨大值，不足 1 返回无目标。Query DSL、标签 PB、认证、时钟、Caret 等仍是有界适配，不能视为浏览器端到端。

原版裸初始化可接受 Infinity；原生显式拒绝负数、NaN 和无穷值，作为安全差异，不声称非有限值完全等价。导入错误直接拒绝；程序内部非法赋值恢复默认 100。单位支持 WPM／CPM／WPS／CPS／WPH，拒绝换算溢出及正数下溢为零；使用完整 Double 字符串而非固定两位小数。初始单位不可表示时明确退回 WPM，未修改草稿直接保留原始 WPM，避免往返换算舍入。原生多单位编辑是补充能力。

## 持久化和切换合同

| 路径 | 新行为 | 回退边界 |
| --- | --- | --- |
| UserDefaults | 旧 integer 10–300 继续写 appSettings.v1；首次扩展值写 appSettings.v2，apply 在任何中间写入前选择新 key。之后始终写 v2，原 v1 字节不改 | 旧二进制只能读旧检查点；没有双写、自动反向合并或新旧偏好同步。隔离旧 writer 改 v1 不覆盖 v2 |
| 错误 v2 | 存在但损坏时不回读 v1、不在读取时重写坏字节，当前呈现默认值 | 完整损坏存储恢复尚未实现；随后用户写入可替换坏 v2，不声称无损恢复 |
| 全量归档 | 默认 24；全局或任意原始预设含扩展值最低 24，先检查再裁墓碑。被自动提升到 24 时保留记录 ID、墓碑和新格式字段 | 假装旧 1–23 的扩展值拒绝；真正旧 integer 95 可保持显式 23。不扩大其他历史格式降级规则 |
| 设置文档 | 默认 4；扩展值最低 4，实际 SettingsJSONCommandCodec 拒绝假旧 1–3 | 不声称直接调用原始 JSONDecoder 也执行 codec 的完整准入检查 |
| 预设 | 全设置／caret 组选项保留小数；非 caret 组不替换当前速度，definitionData 当前读者精确往返 | SwiftData 字段不改，但共享预设 JSON 的扩展值不兼容旧二进制。先备份并升级读者；真实旧库升级／降级未验 |
| 自建同步服务 | 不修改服务源码；隔离重启证明 opaque 格式 24 payload 字节保留和 owner 隔离，过期 transport revision 被拒绝 | transport revision 与归档格式不同；知道最新 revision 的旧 writer 仍可能覆盖新 payload。需升级全部共享客户端，不支持混合 writer 安全承诺 |

不重算历史速度、准确率或回放。旧已保存整数设置保持数值；包含扩展预设的归档和 v2 偏好不能喂给旧二进制。回退应先备份新数据，再明确恢复旧检查点；本轮没有执行真实备份恢复、旧二进制或真实数据库迁移。

## 行为证据

新增 19 项原生测试和 2 项服务测试。最初九项有效 RED 为 16 个失败断言、2 个旧 Int 解码异常；日期编码夹具和编译错误不计产品反例。首次扩展的 Double.max / 12 再乘 12 会舍入溢出，错误 NotNil 夹具已改为 max / 24，并单独断言 max / 12 拒绝。升级后裁掉 ID／墓碑的反例为 1 项测试、8 个失败断言，修复后当前定向 55 项全部通过。服务全量 164 项通过（1.752 秒）。

覆盖隔离 UserDefaults、非法数字、各单位边界、预设设置组、当前实体 definitionData、旧固定成绩、假旧格式、先验墓碑、自动提升后的元数据保留和 mode 命令规则。源码 46 组通过；服务仅隔离 AuthStore，不是真实 HTTP 客户端／部署或官方账号。日志在 `/tmp/typebar-custom-pace-*.log`，不是仓库交付资源。

首轮完整客户端执行 2781 项，1 项失败（667.528 秒），为 CustomDelimiter 的默认设置版本写死 3，单项已复现；当前默认是 4。更新默认断言并补显式旧 3 管道配置读取检查，不禁用测试、不放宽格式保护；修正后相关 78 项零失败（0.921 秒）。首轮十万词通过 145.101 秒、旧 12000 次组合字形删除双投影 0.025682 秒；失败门禁没有执行服务／打包，不计整体通过。

最终完整串行门禁：客户端 2781 项零失败、零跳过（666.109 秒），服务端 164 项零失败（1.800 秒）；827 条人工场景结构、固定参考／原创性／元数据审计和未打开应用包检查通过。实际十万词 passed 为 144.470 秒，旧 12000 次双投影 0.025721 秒。门禁期间没有编辑源文件／文档；其后仅补结果记录、清理服务测试末尾空行，并再跑相关测试、源码和清单检查，生产行为未改。最终相关客户端 78 项（1.021 秒）、服务新增两项（0.016 秒）通过。没有启动 GUI，没有向真实 Typebar 背景成绩目录写入；人工新增四条仍待实机。

最终门禁记录 `/tmp/typebar-custom-pace-readiness.log`，完整客户端／服务捕获为 `/tmp/typebar-custom-pace-gate-client.log` 和 `/tmp/typebar-custom-pace-gate-service.log`；package 捕获没有最终审计行，包验证以门禁成功退出和 `macOS app package check passed` 行为准。首轮完整失败日志为 `/tmp/typebar-custom-pace-gate-client-first.log`、`/tmp/typebar-custom-pace-readiness-first.log`，单项复现和定向绿灯分别为 `/tmp/typebar-custom-pace-delimiter-red.log`、`/tmp/typebar-custom-pace-delimiter-green.log`。AddressBook／CoreData XPC 环境诊断不算断言失败，也不算系统服务验收。

## 仍开放

完整逐词 Pace 动画、错误词修正、RTL／反转／blind／no-space、真实编辑／取消／IME／VoiceOver／窗口、旧库／二进制降级及服务混合 writer 安全仍未验。引语 ID、标签 ID／认证及 PB 快照时序差异仍见 [节奏结果选择合同](PACE_RESULT_SELECTION_CONTRACT.md)。官方 187 主题、一个挑战及内容／分布、XP 精确公式等整体缺口不因此关闭。

行为优先、源码驱动、迁移及会话内有界决策／风险复核约束实现，不是独立评审。原生 UI 沿用现有 Form／sheet，不生成浏览器壳。完整纯原生重写 goal 保持 active，功能清单不升级为全等价。
