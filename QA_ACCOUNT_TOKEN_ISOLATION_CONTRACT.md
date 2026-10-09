# QA 账户令牌隔离与单实例主窗口检查

完整原生重写仍在进行，固定只读参考为 `91bd24bb8513785c7364cbea29296ff7adafac41`。本增量修复测试安全边界，不提高原版功能兼容分类，也不复制原版产品代码或资产。

## 缺陷与最小修复

此前 `TypebarQAInMemoryStore` 只隔离 SwiftData。`AccountSession` 默认创建的 `AccountTokenStore` 仍查询固定 `app.typebar.desktop` Keychain service；启动恢复读取已有 scoped token 时，可能清除相同端点的旧 `remote-access-token`。独立 bundle ID 本身并不能隔离这个固定 service。

默认令牌存储现在读取实际 bundle 的同一显式 QA 标志。QA 使用实例内、按既有规范化端点分区的内存字典：读取缺失值、写入、清除及旧令牌迁移均不调用 Security API；新实例不继承令牌。非 QA 保留原 service、account 名、设备限定 accessible 属性、端点限制、先复制再删除及失败保留旧值供重试的行为。没有新设置、持久化格式、数据库迁移或服务协议。

抽取窄的 Keychain read／add／delete 注入边界，以假字典证明原行为和隔离；所有新测试均注入自有夹具，未读取、保存或删除真实凭据。`/tmp/typebar-qa-account-token-red.log` 六项出现 11 个预期失败（0.854 秒），三个普通路径测试已通过；加入内存分支后 `/tmp/typebar-qa-account-token-green.log` 隔离及相关 16 项零失败零跳过（0.020 秒）。

六项新测试覆盖：正式 scoped／legacy 值不可见且不被迁移删除；实例独立；端点别名和 scoped clear；缺失／false／字符串标志保持正式查询属性；正式迁移端点限制和复制后删除；写入失败保留旧值并允许重试及公开 save 错误。

同会话有界风险复核检查了默认 bundle 路径、QA 缺失值也不能回落 Keychain、正式查询和失败重试。不是独立安全审计。GUI 不登录账户，不以实际凭据验证风险。

## 唯一 QA 主程序检查

候选基于 `bd81b1d867c142588b52616aed806529c7c109e2` 加本轮两个源码／测试文件改动；二者在 `/tmp/typebar-qa-account-gui-frozen.sha256` 打包前后及退出后保持一致。正式旧提交本身不包含本次修复。

`/tmp/typebar-qa-account-gui-build.log` 打包终态退出 0；候选位于 `/tmp/typebar-qa-account-gui.jt8GrC/Typebar.app`，独立 bundle ID `app.typebar.qa.20261009.token-isolation`，QA 内存标志为 true。直接启动唯一可执行文件，临时端点参数为 `http://127.0.0.1:1`，不注册正式 URL handler，不登录账户，不使用正式数据库。运行日志 `/tmp/typebar-qa-account-gui-runtime.log`。

进程检查仅一个 `Typebar`，PID 13753。通过原生命令面板启用 letter Tape，检查字数／Swift 入口后使用自有三行自定义文本 `let answer = 42\nprint(answer)\nreturn answer`。完整主窗口的 AX 显示两个真实 Return 目标，截图显示三行高度内的原生词框与锁定光标。逐键输入 `let ` 后光标定位下一词；输入第一行并按 Return 后光标移到第二行，上一行仍保留。自动化 `equal` 键产生了不匹配字符，错误数为 1；不把本次检查当作正确成绩、实体键盘、IME、全部模式或像素等价证明。截图已在本次工具会话直接查看，未声称保存为仓库图片。

按 ⌘Q 正常退出，所属启动 session 15810 终态退出 0；随后 Typebar 进程为零，未重开候选。整个 GUI 检查期间不编辑冻结输入、不运行编译或测试。启动前的隔离由假 Keychain 行为测试证明，GUI 观察不能独立证明零 Security 调用。

## 冻结验收与剩余范围

七个文件冻结于 `/tmp/typebar-qa-token-final-frozen.sha256`，启动、中途与终态逐项一致。唯一门禁 session 57206 终态退出 0，主日志 `/tmp/typebar-qa-token-final-readiness.log`：原生 3,959 项零失败零跳过（949.766 秒），服务 501 项零失败零跳过（11.911 秒）；六项新隔离测试再次通过（0.003 秒），十万词耐久 178.861 秒，16 项隔离磁盘迁移 4.931 秒。原始 Contacts／CoreData 诊断和损坏存储夹具结果保留，不当作 XCTest 失败，也不宣称设备无诊断。

固定源码对照、53 页面／modal 表面、1,128 唯一人工场景结构、94 配置的 90 映射／3 部分／1 不适用、未启动包／严格签名／资源与原创长文字边界通过。结构审计不是全量人工验收；未启动包检查仅指本门禁，整个增量另有上文唯一一次 QA 启动。73 份原始日志位于 `/tmp/typebar-qa-token-final-logs.6Tu0MK`，210 张组件图位于 `/tmp/typebar-qa-token-final-images.2hf4gV`；终态后复看 `ordinary-tape-short-letter.png` 与 `ordinary-tape-corrected-return.png`，灰色字形及三行布局保留。GUI 截图仍只在本次工具会话中，不混入这 210 张组件图。

终态确认无 Typebar、编译或测试残留，才更新本合同、README、规范与盘点的结果；两个源码／测试文件及人工场景文档保持冻结哈希。参考 checkout 仍为干净固定 pin。复杂 composition replacement 的目标跨度／光标、hint 测量、任意纵横队列、原版字体／主题资源和实体设备仍开放；本次三行窗口检查不提升 tapeMode／CFG-02／MET-67 的部分状态。完整 goal 保持 active。
