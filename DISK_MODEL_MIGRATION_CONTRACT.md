# 原生磁盘模型升级与备份验证合同

2026-10-06 [完成账户标签快照](RESULT_ACCOUNT_TAG_SNAPSHOT_CONTRACT.md) 已接通完成回调、本机保存、冷队列重试、归档与实际导入／合并；按固定源码纠正为完成时捕获，不是启动时冻结。新增可选第 32 列，五实体、设置 4 不变，归档 29、六个隔离 writer；旧未知不回填，已知空不继承新账户勾选，冲突与损坏拒绝，失败恢复原字节。定向 38 项及四个完整有界源码函数通过；完整串行门禁原生 3077／服务 432 项零失败、零跳过（695.899／9.799 秒），十万词 149.626 秒、12 项迁移 5.383 秒、923 场景仅结构及未开窗包通过；门禁后重复 UUID 先行七个失败断言并修正，相关 189 项再通过（1.757 秒），不冒充最终版本同轮全量。新增三条场景仍待单实例／真实网络／VoiceOver 验收，零 GUI。标签 Pace、缓存 PB 重建、目录备份、原版协议与设备等价仍开放，整体 goal active；以下为历史阶段，旧“启动冻结”表述以本合同为准。

2026-10-06 [稳定账户标签](ACCOUNT_TAG_IDENTITY_CONTRACT.md) 只新增自建服务状态字段和按账户／地址分区的本设备选择；五实体、31 列、五历史 writer、归档 28／设置 4 不变，账户目录不进入本机备份。旧缺失不凭文字猜 ID，显式损坏／有 ID 却缺目录拒绝，原子文件失败恢复；仍要求单 writer 停写升级与完整备份回退，不承诺旧 writer 保留新字段。最终十项磁盘迁移 4.412 秒，完整门禁原生 3066／服务 432 项零失败、零跳过（696.965／9.845 秒），未开窗包通过。零 GUI；下方为历史阶段。

2026-10-06 当前 [PB 归档与合并](LOCAL_PERSONAL_BEST_LEDGER_CONTRACT.md) 提高原生归档至 28，设置仍 4，五实体与 TestResultRecord 的 31 列不变；五个历史 writer 不变。新增真实 ledger-only 导入冷重开及只读 SQLite 保存失败回滚；完整门禁十项 schema 迁移 5.923 秒、原生 3058／服务 422 项零失败、零跳过，未开窗包和原创性通过。原生归档往返不是旧发行二进制、macOS 14／Intel 或真实双机升级证明；下方为历史阶段。

2026-10-06 当前 [本机 PB 账本](LOCAL_PERSONAL_BEST_LEDGER_CONTRACT.md) 新增第五实体，归档 27／设置 4 不变。第五个 writer 投影前一版 5f9e090723fc4be52bc9dee6148d7d14e66554ea 的四实体 schema，新增升级及删除历史后账本的独立进程／生产冷读取。current 为五实体，TestResultRecord 仍 31 列；完整串行门禁原生 3044／服务 420 项零失败、零跳过（700.056／9.767 秒），十万词 151.073 秒、十项磁盘迁移 4.671 秒、914 场景仅结构及未开窗包／原创性通过。下方四实体、三／四 writer 和七／九项数字均属历史阶段，不是当前 schema 或旧发行证明。

2026-10-06 当前 [引语身份合同](RESULT_MODE2_CONTRACT.md) 提高归档至 27，设置仍为 4；身份存于既有 quoteSourceData，不新增 SwiftData 列，四 writer 及 current 31 列投影不变。坏显式来源不能作为旧来源导出，原字节保留；本批内存验证和完整门禁九项隔离磁盘迁移通过（3.365 秒），原生全量 2975 项零失败、零跳过。不把旧阶段归档 26 或自动化当成实际用户库／旧发行升级承诺，goal 未完成。

2026-10-04 最新增量见 [未完成练习证据合同](INCOMPLETE_PRACTICE_EVIDENCE_CONTRACT.md)：新增可选 incompletePracticeData，归档 26／设置 4；四 writer 包括第三代 before-incomplete 30 列和 current 31 列，九项真实磁盘测试已定向通过。迁移策略仍使用现有自动路径。本页下方两代历史、三 writer、current 30 列及七项测试描述保留为原阶段证据，不是当前 schema。完整 Monkeytype 原生重写 goal 仍 active；不是实际用户库、旧发行二进制、旧 SDK 或 macOS 14 的升级承诺。

## 被验证的模型

`Scripts/prepare-disk-model-fixtures.rb` 从本仓库固定历史提交机械提取四个 `@Model` 的存储声明，不提取计算属性、旧应用逻辑或 Monkeytype 代码／资产。未知声明立即失败，不静默省略。

| 投影 | 自有源码提交 | Result／Preset／Text／Filter 字段数 |
| --- | --- | --- |
| initial | bdbfae291c7a20a706a100c62a7c323681dfbf8f | 14／4／4／4 |
| before-elapsed | 9c5b477c6cd1a2ef5b4d34afbc3ef4013dc21cc7 | 29／4／5／4 |
| current | 当前工作树；manifest 同时记录 HEAD 和投影 SHA-256 | 30／4／5／4 |

三个无窗口命令行 writer 以 `Typebar` 模块名、原类名、实际原生架构及 macOS 14 编译目标串行构建。当前投影必须与实际生产模型的字段名、原名、类型、可选性、默认值、unique／transient／hashModifier 和唯一约束逐项相等；实际四模型没有关系字段。编译目标不是最低系统运行验证。测试在 macOS 26.1（25B78）和 Swift 6.2.4 执行；历史投影也由当前 SDK 编译，不能冒充过去 SDK 生成的实际模型哈希。

Apple 的 [ModelContainer 文档](https://developer.apple.com/documentation/swiftdata/modelcontainer) 描述自动迁移，并要求超过自动迁移能力时提供 SchemaMigrationPlan。本次实测现有自动路径，不因新增可选字段就推断所有旧库都安全，也不在没有反例时添加推测性生产迁移。

## 七项可观察检查

`DiskModelMigrationTests` 使用实际生产四模型和现有 `DataStoreStartupPolicy`，不是内存库或只有 JSON 往返：

1. 当前 schema 投影与每个生产存储描述符相等。
2. initial 旧 writer 创建真实 SQLite；新模型自动打开，四实体、ID、日期、原始 blob 和旧分数保留；新增字段不回填。
3. before-elapsed 同样升级；写入日期倒退但独立测量 16.125 秒的新结果，保存／释放实际容器，再由独立的当前投影只读进程验证实际保存的 blob 字节及真实结束日期；实际生产模型再次打开得到同一结果。损坏显式时长 blob 再保存／重读仍损坏，不降级成旧日期分母导出。
4. 旧 Zen 尾部证据与小数分数连续打开／保存后不回填、不重新计分。
5. 历史不透明坏 blob 在迁移及无关标签保存后保持原字节；坏记录不被自动修复或变成可导出记录。
6. 旧 writer 已退出、当前模型尚未打开时复制整个自有库目录（包含存在的 SQLite sidecar）；升级源副本并写新记录，再将旧备份恢复到另一自有临时目录。旧 schema 的只读进程读出原 schema／全部旧行，主 SQLite 字节不变。没有让旧 writer 打开升级后的库。
7. 故意写坏的自有 SQLite 启动失败，返回原 URL 和诊断，原文件字节不变；不替换为空库。该测试的 SQLite 26／CoreData 259 日志是预期诊断。

第 2／3 项同时执行两代升级的完整写入／冷读取路径。当前投影独立进程不是实际应用冷启动；实际生产消费者在 XCTest 中释放并重开容器。所有 fixture 内容、日期和 ID 自有，不使用用户数据库。

## 备份与安全边界

数据库位于 Foundation 临时目录下唯一 `typebar-disk-migration-<UUID>` 子目录，测试结束只清理自己创建的目录。CloudKit 明确关闭，autosave 关闭，旧 writer 已终止才复制。准备脚本要求新的绝对输出路径和同用户拥有的 `typebar-*` 父目录，拒绝复用已有输出；不删除旧输出。不启动 Typebar GUI，不改变真实系统时间，不写 Application Support。

这验证的是闭库备份恢复，不是数据库降级，也不是完整应用回退。UserDefaults、钥匙串、同步／发布队列、墓碑、其他文件和版本共存没有被一起恢复。不能用该证据建议只替换 SQLite 就回退整个应用。实际旧发行二进制及其 SDK 模型、macOS 14／Intel 实机、实际用户库副本、混合 writer、真实窗口重启与完整恢复流程仍待验。

## 执行与证据

这是迁移能力的探索性验证：先验证现有实现，观察到反例才改生产代码。本轮没有生产行为失败或生产修复。准备过程中 Ruby 2.6 不支持 `filter_map`、测试 Swift 编译错误已修正，不记为产品 RED。冷读取断言曾误将保存 blob 与重新编码 JSON 比较；JSON 键顺序不同造成伪失败，改为捕获写入时的真实字节后严格比较。生产代码没有为测试改变。

修正断言后的定向 81 项零失败／零跳过，1.299 秒：`/tmp/typebar-disk-model-cold-corrected.log`。三 writer 原生架构准备记录：`/tmp/typebar-disk-model-final-prepare.log`。完整串行门禁已通过，客户端 2866 项零失败／零跳过（686.780 秒），服务端 175 项零失败／零跳过（1.635 秒）；同一门禁十万词实际通过 148.207 秒，新增七项实际通过 4.658 秒。846 条人工场景只做结构检查，未开窗应用包、固定源码及原创性／元数据审计通过；不记录为人工或设备验收。

本轮日志：`/tmp/typebar-disk-model-readiness.log`、`/tmp/typebar-disk-model-gate-client.log`、`/tmp/typebar-disk-model-gate-server.log`、`/tmp/typebar-disk-model-gate-fixtures.log` 和 `...-gate-manifest.json`。client／server 完整日志在门禁清理前复制；应用包检查由门禁末尾通过行证明，没有单独完整包检查日志。门禁后同一相关 81 项再次零失败／零跳过，1.298 秒：`/tmp/typebar-disk-model-postgate-focused.log`。

坏库的 SQLite 26／CoreData 259 是第七项的预期失败输入；全量运行另有系统 AddressBook／XPC 诊断，不归因于本次迁移测试或当成产品 RED。最终 XCTest 通过数及门禁退出状态是成功依据。本轮无 Typebar GUI，真实后台队列目录仍不存在，生产模型／迁移策略无改动，完整功能等价 goal 仍 active。

推荐执行包含耐久检查的完整门禁：

```sh
TYPEBAR_ENDURANCE_TESTS=1 zsh Scripts/check-native-rewrite-readiness.sh /absolute/pinned/monkeytype-reference
```

门禁先串行准备三个 writer，再将 `TYPEBAR_DISK_FIXTURE_ROOT` 传给客户端测试；客户端仍使用 `TYPEBAR_QA_IN_MEMORY_STORE=1`，只有这些测试显式打开自己的临时磁盘库。独立跑测试时先用 `mktemp -d -t typebar-disk-probe` 创建父目录，再以其新的子目录运行准备脚本，传同一路径为 fixture root。没有该变量时六项 fixture 依赖检查明确跳过；正式门禁必须准备成功且零跳过。编译、测试、服务测试及应用包构建全部串行，不在它们运行时改动源码，不打开应用包。

新增人工验收场景仍待验收；自动化证据不提升主题、挑战、内容身份或整体功能等价覆盖。
