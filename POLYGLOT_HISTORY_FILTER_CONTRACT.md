# 历史中的独立 Polyglot 筛选

本机历史和账户历史新增独立的“Polyglot 多语混排”选项，支持与无修饰器和其他修饰器任一命中，也接通当前设置、本机预设、归档和账户预设。语言条件仍独立，不通过选择混合语言来替代修饰器条件。整体重写 goal 保持 active，功能矩阵仍部分兼容。

## 筛选含义

[固定参考的结果查询](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/collections/results.ts#L464) 对 Funbox 采用任一命中，none 仅匹配空集合；[当前设置入口](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/account/Filters.tsx#L433) 保留实际启用的每个 Funbox。Typebar 的混合语言配置表示 Polyglot，但它不是 TestModifier；历史投影增加独立的可选身份，不新增成绩存储字段。

本机从完成配置读取身份，账户从已有排名或经验元数据读取，未知不补 false。仅 Polyglot 不能归入“无修饰器”；未知身份不能冒充普通结果，已知伴随修饰器仍可命中。完全不限时保留未知结果。明确关闭 Polyglot 并非排除一切多语成绩：若该成绩同时命中另一个已选修饰器，仍按 OR 规则保留。

旧筛选缺少 includesPolyglot 时维持旧行为：原先完全不限仍不限，受限集合不自动增加 Polyglot。旧 JSON 不增加字段。编辑无修饰器或其他修饰器之前，先固定当时显示的 Polyglot 选择，避免两个独立控件互相改变。混合语言的当前设置快捷筛选明确选择 Polyglot，不把空 TestModifier 数组误作 none；普通配置保持旧含义。两处原生勾选框沿用既有布局，不增加网页或键盘监听。

## 保存和升级

本机预设的可选 includesPolyglot 只接受布尔值，显式 null、数字或字符串拒绝。显式 true 和 false 均要求归档最低 33；伪装成较低版本的字段在应用删除墓碑之前拒绝。旧归档继续读取，设置 5、偏好 v3、五实体和成绩 32 列不变。升级前备份完整本机数据库；旧应用可能忽略新筛选字段并重存不同选择，回退必须恢复升级前完整备份，不是无损降级。

账户文档无新字段时保持 v1，有明确选择时使用 v2；v2 必须包含合法布尔值，v1 携带该字段拒绝。列表封套仍 v1。保存 v2 前要求精确 Typebar v1 同时声明 accountFilterPresets=available 和 accountFilterPolyglot=available，否则不发送预设 POST，不静默降级。读取和删除仍沿用已有权限、作用域与代次保护；未确认修改不自动重试，也不承诺恰好一次。

服务升级先停写并备份完整 JSON，再启用唯一新版 writer；禁止新旧 writer 混写。旧 v1 文档原字节保留，v1 和 v2 可同库读取；旧服务不能打开 v2 文档，旧客户端也不能读取含 v2 的列表，因此保存首个 v2 之前须升级相关客户端。回退须恢复升级前备份；旧客户端与旧服务二进制未做实机降级验收。未部署服务或操作真实账户、钥匙串及用户数据库。

## 验证

修正夹具自身的语言身份和日期精度后，原生失败先行三项产生五个预期失败、零意外错误；服务 v2 保存产生一个预期失败。日志为 `/tmp/typebar-polyglot-filter-native-verified-red.log` 和 `/tmp/typebar-polyglot-filter-service-red.log`。最初无效身份被已有解码器正确拒绝，不算产品缺陷。

相关原生 55 项零失败零跳过（3.703 秒），包含 16 项磁盘迁移冷读；服务相关 13 项零失败零跳过（0.150 秒）。日志为 `/tmp/typebar-polyglot-filter-focused-final.log` 和 `/tmp/typebar-polyglot-filter-service-focused.log`。实际磁盘测试从历史存储声明构建隔离库，冷读后新 explicit false、旧筛选 blob 和原成绩字段保留；这些 writer 不是旧 GUI 二进制。首轮新测试因临时 ModelContainer 提前释放在 fetch 断言退出，单项重现后保留容器修正，单项及全组再通过；未跳过测试或修改生产逻辑来掩盖。

固定源码 QA 新增 32 组 none／Polyglot／Memory 选择与结果组合，并与原生查询逐项对照。既有 96 组统计、四时区、九组旧修饰器、192 组 PB／长度和六个自有引语边界保留。执行完整固定函数及自有 eager 查询适配，不等于实际 TanStack、Solid、DOM 或全部 Funbox 组合；参考代码只在 QA 动态读取，不进入产品。

服务测试实际执行进程内 HTTP 能力、合法 true／false、错误版本和非法类型，并检查混合 v1／v2 文件冷读不改字节、拒绝写入保留旧文件。原生能力属性及调用路径有测试和同会话风险复核，真实 URLSession 的发送前拒绝、网络失败与钥匙串路径仍待验收。行为优先、迁移、根因调试与风险复核限定以上边界，不是独立评审。

冻结后的完整串行门禁通过：客户端 3,429 项零失败零跳过（748.154 秒），服务 468 项零失败零跳过（10.624 秒）。十万词耐久 151.690 秒，16 项磁盘迁移／冷读 5.832 秒；1,016 个人工场景仅通过结构审计，固定源码、原创性和未开窗应用包／签名／资源检查通过。14 个代码／测试／脚本文件 SHA-256 前后一致。42 份日志保存在 `/tmp/typebar-polyglot-filter-final-logs.q2LDBZ`，总日志 `/tmp/typebar-polyglot-filter-final-readiness.log`；只读坏库与系统联系人诊断不等于 XCTest 失败。门禁后仅更新文档，没有修改已冻结的产品或测试。

## 人工验收范围

MANUAL_ACCEPTANCE 中 HIS-POLYGLOT-01 至 03 保持待验收：两处控件与当前设置、预设保存重开和旧服务拒绝。真实焦点、VoiceOver、双设备、macOS 14 和 Intel 仍开放。本轮零 Typebar 图形启动，不把无窗口测试或清单结构审计算作设备通过；完整功能等价未完成。
