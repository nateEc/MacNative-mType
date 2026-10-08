# 账户累计练习、活动与连续天数

## 好友统计对照、排序与资料入口增量

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`：只读核对完整 [FriendsList](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/connections/FriendsList.tsx)、DataTable、friends 查询、FriendSchema、getFriends DAL 与 aggregateWithAcceptedConnections。八列为姓名、关系修改时刻对应的时长、XP 等级、完成／开始、练习时长、连续天数、15／60 秒 PB；原版聚合加入本人对照，无 connectionId 的本人没有解除入口。好友 PB 在所有语言／配置中选最高规范 WPM，`>=` 同速取后一个完整对象，零速纪录仍可选；不是资料页摘要的严格正速／同速取先策略。

原创 `FriendComparisonRow` 每次建行只选择一次两档 PB，比较器不反复扫描纪录；排序用原始 XP、完成数、规范 WPM，而非展示等级／单位转换值。支持八列三态、多列 Shift 排序、稳定同值顺序、只保存排序描述的本机偏好和恢复默认。未知统计不冒充零、两个方向均置后，这是明确的原生适配，不宣称 TanStack 的动态首行类型推断／缺值排序完全等价。完整快照优先于旧 personalBests；`unknown` 参数不猜档。原版连续 1 天显示占位符，0 天保留；完成比例向下取整，零完成的无限重启比用 `∞` 本地化。

生产分组表单现在包含横向对照表、本人行和独立动作区，440 窄窗不删除列；等级附累计 XP、完成数附比例／重启比、连续附最长天数，PB 两位小数且遵守五种速度单位，点击查看语言／速度／Raw／准确率／稳定度／日期／配置。姓名打开既有 `PublicProfileLoadingView` 重读完整公开 DTO，不把轻量列表当完整资料；本人同样是公开资料，不展示私密概览。请求行补日期；消息入口保留为不同 destination，解除仍经既有确认和当前关系守卫。头像复用既有有界匿名 CDN 客户端，不用共享认证会话；离屏 fixture 无头像 URL，因此不联网。

设计技能促使采用围绕统计比较的单一横向表而非卡片堆叠；沿用系统文字／语义色／单宽数字，箭头与排序优先级编码真实状态，普通正文和数据分层，没有品牌资产或新装饰动效。SDK 本机 Swift 6.2.4／macOS 26.2 的 SwiftUI swiftinterface 与 NSEvent.h 确认 macOS 14 目标所需横向 ScrollView 和 class modifierFlags 签名；Apple 网页取 Markdown 时工具不支持其 content-type，未把未取得正文当 API 证据。组件编译／离屏运行通过，不代替真实键盘、Shift、滚动、弹层或 VoiceOver。

迁移安全与有界同会话决策复核（非独立审查）选择在既有认证 `GET /v1/connections` **增补可选 `ownerProfile`**：由令牌定位内部用户，复用与好友相同的公开轻量投影，不走私密 overview，不计算排行榜，不增加逐好友请求。回复 `private, no-store`；私密 activity／accountStreakClaim 不在投影中，原生快照还拒绝错本人 UUID 或意外私密 owner 数据。旧客户端忽略新增字段；新客户端连旧服务缺本人数据明确降级，旧统计缺 lifetime 标记显示未知。没有删除接口、数据回填、服务／SwiftData／归档迁移、部署或真实账户操作；回退客户端／服务无需数据回滚，但既有已提交关系操作不回滚。关系仍沿用上一增量的两次认证读取和全部守卫，不宣称事务快照。服务没有上游 Premium 资格，不伪造 Premium 标记。

行为先行 RED：`/tmp/typebar-friends-comparison-red.log` 实际编译成功、1 项预期失败，原响应确实缺 ownerProfile。原生初次定向 23 项通过（0.660 秒）；加生产图后第一次 `/tmp/typebar-friends-comparison-render-focused.log` 因命令未创建图片目录而写文件失败，保留该证据，不归咎生产代码；新隔离目录重跑 `/tmp/typebar-friends-comparison-render-verified.log` 38 项零失败／零跳过（32.644 秒），四张新增宽／窄／浅深色图 `/tmp/typebar-friends-comparison-focused-render.wf4vpR` 已逐张查看。服务首次 `/tmp/typebar-friends-comparison-server-focused.log` 暴露 AuthUserResponse 与 StoredUser 类型误用，按认证后实际用户查找修正；重跑 `/tmp/typebar-friends-comparison-server-verified.log` 7 项零失败／零跳过（0.070 秒），覆盖令牌身份、无缓存、未认证拒绝和历史删除后累计／PB／磁盘读取无写入。随后补旧客户端解码、私密 owner 拒绝／排除请求与屏蔽／多级排序和 PB 选择预计算，最终完整门禁另记，不把前次结果冒充后次执行。

QA 脚本 `check-source-friend-comparison.mjs` 执行完整实际 getFriends 以取得 PB 投影表达式，在有限自有 `$reduce/$cond/$gte` 解释器上跑 18 组新／旧快照，另执行完整实际 formatStreak／formatTypingStatsRatio；原生测试逐项对照选择的 UUID，脚本纳入完整门禁。解释器只处理声明的有限数值 fixture，未知操作直接失败，不冒称 MongoDB、BSON 一般排序、TanStack、Solid、浏览器或 HTTP 等价；格式化复用既有全域小数源码对照。52 页面矩阵补生产路径／测试符号；新增三项后 1,062 人工项仍仅结构盘点。完整好友模态／Premium／真实滚动与 VoiceOver、私信内部生命周期、其他全功能无损与主题身份等缺口保持开放；本轮零 Typebar 应用启动，整体 goal active。

最终冻结完整串行门禁退出 0：原生 3,600 项零失败／零跳过（816.710 秒），服务 498 项零失败／零跳过（11.249 秒）；实际十万词耐久 154.206 秒、16 项隔离磁盘冷读 4.937 秒通过。52 页面证据、1,062 人工结构、固定源码／原创边界及未启动应用包／scheme／严格签名通过。主日志 `/tmp/typebar-friends-comparison-complete-readiness.log`，56 份分项日志 `/tmp/typebar-friends-comparison-complete-logs.udRMUP`，64 最终图 `/tmp/typebar-friends-comparison-complete-render.4tNDSH`；四张新增对照图与更新后的管理深色表单已复查。15 份生产／测试／脚本／矩阵冻结哈希前后一致（`/tmp/typebar-friends-comparison-frozen.sha256`），运行期间没有编辑，结束后仅补三份结果文档。固定参考仍干净且提交一致。

日志继续保留既有 macOS AddressBook／CoreData XPC 连接诊断，以及隔离只读 SwiftData store 的 513 保存诊断；不把零断言失败当作系统警告修复。前述失败命令、局部提供者／源码适配器、模型与离屏图片均不代替实际滚动、Shift／持久化、确认／PB／资料弹层、真实网络与辅助功能；人工状态不升级，消息内部生命周期、旧服务统计完整性和整个无损重写继续待完成。零 Typebar 应用启动、goal active。

## 好友管理作用域与操作生命周期增量

只读核对固定 [FriendsPage／PendingRequests／FriendsList](https://github.com/monkeytypegame/monkeytype/tree/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/connections)、完整 connections 集合、friends 查询和后端 connections 控制器。原版收到请求可接受／拒绝／屏蔽，添加前排除本人和既有 pending／accepted／blocked，解除好友需确认；原生此前搜索结果无条件可添加，读取与任务没有账户生命周期保护。本增量保留收到、已发、好友、本人屏蔽四区以及全部已有操作和消息入口，补添加可用性、解除确认和私有状态边界，不复制上游代码／图标／资产。

`ConnectionsOwnerIdentity` 固定原始 endpoint、标准化账户范围和会话／服务器 ABA 代次；关系读取另固定内存关系修订和显式刷新 UUID。实际页面按 owner 身份重建私有状态；读取 `.task(id:)` 随关系操作更新，搜索输入改变取消旧等待并退休搜索 nonce；关闭取消页面拥有的搜索／提交等待。任务 nonce 防旧清理影响新任务，读取 generation 防同一 request 的迟到成功／失败覆盖较新读取。展示只接受当前范围和读身份，旧账户好友、屏蔽、搜索及提示不用于新页面。普通相同用户资料刷新不重建草稿／页面。

实际认证 GET 在一次捕获 endpoint／令牌下串行读取既有 connections／blocks；两次读取不是事务快照，本人屏蔽优先于旧关系，重复身份／本人关系行等非法快照报错。部分失败、旧服务缺接口和未知响应不显示为空关系，不保留可写旧列表。搜索沿用公开展示名查询，独立捕获服务器，不带认证；规范化使用现有 2–40 字符策略，无结果、重复结果和失败不伪造成员关系。本人和已知屏蔽不出现在可操作搜索结果，其他已知关系显示方向／好友说明，不重复添加。

五类提交按当前快照校验方向和对象，并在页面内互斥；未知、加载中、过期读身份或另一个提交时，提供者不被调用。真实网络方法自身在凭据读取前检查完整 read 身份，捕获该 endpoint，返回后检查取消与 owner 范围；send／accept 还要求回应为目标 UUID 和预期方向。成功仍通过既有 scoped 关系修订通知其他资料页，并刷新当前页；自己的成功改关系修订不是账户切换。取消／超时／丢失响应明确“可能已收到”，退休结果确认前开始的读取，必须后续刷新才恢复操作，不自动重试、不声称服务器回滚。跨页面或跨设备同时操作最终仍由自建服务裁决，不宣称本机互斥是分布式事务或幂等提交。

接口路径、请求／响应体、服务数据、SwiftData 和归档格式均不变；核对原生所有调用者后移除不再被页面使用的两条无作用域读方法，五条内部写方法要求显式读身份，防未来漏传守卫。旧客户端／服务契约不变，代码回退无数据迁移，但已提交的服务操作不回滚。本轮不部署、不读写真实关系／Keychain／Typebar 数据库。源码驱动、行为先行、原生设计、迁移安全及三轮有界同会话决策／风险复核促使下沉实际请求守卫、区分认证与关系修订并退休不确定结果前的读取；非独立审查。设计沿用系统字体、语义色和分组表单，以关系方向作为结构；窄窗把资料与动作分行，未知错误提供刷新方向，不另造品牌资产或装饰动效。

先行静态接线一项四处预期失败（0.570 秒，`/tmp/typebar-connections-management-red.log`）；旧 SwiftUI 私有状态无可注入提供者，故不把这项冒称旧运行时复现。新状态随后用实际 Swift 模型和自有异步提供者覆盖作用域／ABA、迟到成功与失败、双击／冲突操作、五类动作、取消和提交不确定性、搜索变更。首次编译因测试数组夹具漏 `try` 失败，保留 `/tmp/typebar-connections-management-focused.log`；仅修语法后 27 项两处失败源于切服务器按既有逻辑退出登录、后续夹具漏恢复用户，保留 `/tmp/typebar-connections-management-fixture-verified.log`。核对真实 setter 后只修 fixture，27 项零失败零跳过（0.504 秒，`/tmp/typebar-connections-management-verified.log`），未放宽生产守卫。下沉请求守卫后 43 项零失败零跳过（30.453 秒，`/tmp/typebar-connections-management-final-focused.log`）；最后真实写方法要求 read 修订后结果另记，旧绿灯不替代最终修订。

复用固定完整 hasConnection／按钮谓词／好友标记探针的 20 组实际输出，与管理页添加可用性逐组对照；适配器边界仍是自有集合／认证／props，不执行 TanStack DB／Solid／浏览器／上游乐观事务／HTTP。七张生产表单图只证明隔离离屏布局，无请求、点击、显示或激活窗口，解除确认弹层本轮未真实点击。新增三个场景均待验收，总 1,059 人工项仅结构盘点。好友完整列（时长、等级、连续、15／60 秒 PB、关系日期）、排序和资料跳转仍缺，原版自己行／状态的展示适配也需继续核对；消息页面内部网络生命周期、真实跨窗口／网络／VoiceOver／目标设备、主题精确身份及离线备份等仍开放。后文关于好友页守卫缺口为历史阶段，本增量只补上述作用域路径，绝不据此宣称 FriendsPage 或全功能无损完成，goal active。

真实写方法要求 read 修订后的相关 44 项零失败零跳过（30.475 秒，`/tmp/typebar-connections-management-scope-verified.log`）。随后对照旧页补回搜索“无匹配／找到数量”，与关系警告分开保存／展示，避免搜索成功或错误覆盖提交不确定警告；输入／身份变化仍退休旧反馈。增加回归后相关 45 项零失败零跳过（30.302 秒，`/tmp/typebar-connections-management-feedback-verified.log`），其中 17 项管理模型／实际入口提前拒绝／固定源码对照、14 项既有资料关系及 14 项生产组件渲染。七张新增图已查看，最终完整门禁另记。Swift 6.2.4／已安装 SwiftUICore 接口核对双参数 onChange 自 macOS 14 可用，平台下限保持 14；不根据最新网络文档改写既有 SwiftUI 路径。

最终冻结完整串行门禁退出 0：原生 3,592 项零失败／零跳过（811.409 秒），服务 495 项零失败／零跳过（12.121 秒）；实际十万词耐久 158.545 秒、16 项隔离磁盘冷读 3.320 秒通过。52 页面证据、1,059 人工结构、固定源码／原创边界及未启动应用包／scheme／严格签名通过。主日志 `/tmp/typebar-connections-management-complete-readiness.log`，55 份分项日志 `/tmp/typebar-connections-management-complete-logs.QsVlqk`，60 最终图 `/tmp/typebar-connections-management-complete-render.K6Jaij`；七张新增表单图已逐张复查，包括补回后的搜索反馈和不确定操作警告。6 份生产／测试／矩阵冻结哈希前后一致（`/tmp/typebar-connections-management-frozen.sha256`），运行中未编辑，结束后仅补三份结果文档。

源码 20 组对照执行的是完整实际资料页按钮／hasConnection／好友标记模块；不能冒称已执行完整 FriendsList 添加模态、展示名远程验证或上游 UI。既有服务接受／移除／屏蔽边界测试为 AuthStore 级证据，不升级成客户端实际 HTTP 链路验收。系统 AddressBook／CoreData XPC 警告及临时隔离只读 PB／归档 store 的保存诊断仍保留，不声称根因消失；单次耗时也不证明性能离群已解决。同会话有界风险复核未发现本增量其他阻断项，非独立评审。真实 SwiftUI scope 重建、确认弹层、跨页／网络／键盘／VoiceOver／设备与完整朋友表列／排序／资料跳转、消息内部生命周期和全功能无损仍缺证，人工项不升级、goal active。零 Typebar 应用启动、零部署，无真实 Typebar 数据库／Keychain／账户读取或修改。

## 公开资料关系与重复请求抑制增量

固定源码 [ActionButtons／AvatarAndName](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/UserDetails.tsx)、[connections 集合](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/collections/connections.ts) 和 user-flag-controller 表明：只有已认证、非本人、没有任何已知关系时显示添加入口；已接受关系才显示好友标记，待处理或 blocked 不冒充好友。原生此前无条件显示发送按钮，本增量以独立 Swift 状态／系统 Label 和 Button 补齐。待处理方向分开显示，并指引既有好友页接受／拒绝；已有好友、自己已屏蔽、加载／未知／失败不提供重复发送。举报入口继续保留。本人概览、本人公开页、未登录及匿名只读分享不读取登录关系；匿名分享仍不构造这一组件，不借当前令牌跨服读取。

`ProfileRelationshipIdentity` 固定目标 UUID、原始 endpoint、标准化账户范围、登录／服务器 ABA 代次、关系修订号和重试身份。认证 GET 沿用 `/v1/connections` 与 `/v1/blocks`，同一捕获 endpoint／令牌串行读取；每次挂起前后检查取消和当前范围。只保留视图内目标状态，不把好友／屏蔽列表写入公开 DTO、全局缓存、默认偏好、SwiftData 或磁盘。两次 GET 不是事务快照，已知本人屏蔽优先于旧关系；读失败明确未知，不推断无关系。对方是否屏蔽本人仍由服务泛化错误保护，不从本人屏蔽列表反推对方私有状态。

资料页 POST 同样绑定点击时范围，发送前要求最新关系修订；成功回应必须是目标 UUID 的 outgoingRequest，之后允许自己的成功使关系修订失效。双击、过期范围与已知关系在提供者／凭据读取前拒绝。请求取消或网络失败不代表服务端回滚：状态明确“可能已收到”，需显式刷新后才可重发，不自动重试。关闭／身份变化取消本地等待；操作 nonce 防止旧任务清理新任务或回写状态。加载 nonce 还防同一请求身份的迟到成功／失败覆盖新读取；错账户状态立即隐藏。

同应用六条成功好友操作（新资料页发送、既有发送／接受／解除／屏蔽／解除屏蔽）发布仅内存 `profileRelationshipRevision`。只有原作用域仍有效才发布，已打开资料页的实际 task 身份随之变化并重读；旧登录的迟到成功不刷新新用户。关系新鲜度与认证代次分开，既能拒绝读过程中发生变化的旧快照，也不会把自己的成功发送误判成账户切换。不宣称已全面改写既有好友管理页其他网络生命周期；该页面自己的加载／写入作用域仍需另行审查。没有后台轮询、持久缓存或新应用实例。

产品外 `check-source-profile-relationship.mjs` 只读执行完整实际 hasConnection、实际本人／添加按钮谓词及完整用户标记模块的好友投影；20 组认证／本人／无关系／双向 pending／accepted／blocked 与原生发送可用性、好友状态逐组对照。集合、身份、props 为明确自有适配器，不运行 TanStack DB、Solid、浏览器、HTTP、原版乐观事务或五分钟缓存。探针加入串行门禁，原实现／资产没有进入产品。原生稳定 UUID／显式新鲜读取与原版展示名、全局实时集合不是逐控制器同构；跨设备更新仍需刷新，不据有界探针宣称全部等价。

兼容性与回退：既有自建接口／请求体／响应／存储均不变，旧客户端不受影响；旧服务缺关系／屏蔽读取时显示失败和刷新，不回退为可写的“无关系”。回退代码不需数据迁移，但已发送的服务器请求仍保留。本轮不部署、不修改凭据或任何真实关系。设计沿用原生字体、语义色和状态文字，好友标记不是官方图标／品牌资产；源码驱动、行为先行、设计、迁移安全及同会话有界决策／风险复核促使补同应用刷新、写入不确定状态和双代次守卫，非独立评审。

先行接线测试一项四处预期失败（0.587 秒，`/tmp/typebar-profile-relationship-red.log`）。首轮聚焦编译因测试将 async 放入 XCTest 同步闭包而失败，保留 `/tmp/typebar-profile-relationship-focused.log`；按 root-cause-debugging 只改测试等待位置，并把取消测试放入独立子任务，不放宽生产协议。修正后相关 46 项零失败零跳过（25.534 秒，`/tmp/typebar-profile-relationship-verified.log`）；补同应用失效后相关 48 项零失败零跳过（24.799 秒，`/tmp/typebar-profile-relationship-final-focused.log`）。最后发送前新鲜度与成功自失效修订后，14 项关系模型／读取／写入／取消／迟到／源码对照零失败零跳过（0.422 秒，`/tmp/typebar-profile-relationship-scope-verified.log`）；使用自有提供者，不触碰真实 Keychain 或网络。源码 20 组通过日志 `/tmp/typebar-profile-relationship-source.log`。最终冻结门禁与图像结果另记。

最终冻结完整串行门禁退出 0：原生 3,574 项零失败／零跳过（809.670 秒），服务 495 项零失败／零跳过（10.980 秒）；实际十万词耐久 156.514 秒、16 项隔离磁盘冷读 7.477 秒通过。52 页面证据、1,056 人工清单结构、固定源码／原创边界、未启动应用包／scheme／严格签名通过。主日志 `/tmp/typebar-profile-relationship-complete-readiness.log`，55 份分项日志 `/tmp/typebar-profile-relationship-complete-logs.rJSvTR`；9 份生产／测试／脚本／矩阵冻结哈希前后一致（`/tmp/typebar-profile-relationship-frozen.sha256`），运行中未编辑，结束后仅补三份文档结果。此前独立补充的等级控件绑定测试本轮已包含在同一全量套件内。

最终 53 张图位于 `/tmp/typebar-profile-relationship-complete-render.uCISJQ`，新增八张关系状态图逐张检查，浅深色、禁用按钮和长失败文字均无明显裁切；组件渲染不发请求、不点击按钮、不激活窗口。系统 AddressBook／CoreData XPC 警告仍在，日志亦保留隔离临时只读 PB／归档 store 的保存失败诊断；不声称这些诊断根因已消除，也不把单轮耗时当成性能离群已解决。等级进度轨道的实际可见窗口绘制仍待验，未为截图替换系统控件。同会话有界风险复核未发现本增量其他阻断项，非独立评审。

新增三个人工项全部待验收，整体清单 1,056 项仅结构盘点。实际多窗口同步、按钮／关闭交互、VoiceOver／键盘、真实网络／后台恢复／目标设备与完整功能无损仍未证明；加入时长提示、主题精确身份、离线目录备份等缺口继续追踪，goal active。零 Typebar 应用启动，编译／测试串行，无真实 Typebar 数据库／Keychain／账户读取或部署。

## 等级进度与本人连续提示增量

只读核对固定 UserDetails、完整 levels／数字格式函数、完整 date-and-time 模块、Bar 百分比以及现有 snapshot／保存路径。公开和本人资料新增原生等级、两位小数百分比、当前等级 XP／所需 XP／升级差值和可展开精确整数详情；保留从等级 1 开始、首级 100 XP、之后每级递增 49 XP 的曲线。独立整数阈值二分避免平方根逆函数在大安全整数处提前升级；不修改奖励、总 XP 或排行榜。超出 JavaScript 安全整数域明确不可用，不补造等级。

本人认证概览追加可选 version 1 `accountStreakClaim`，最后保存时刻从不可删除的奖励记录投影，连续参考时刻从既有累计账本读取，未设置偏移与显式零分开。两种时刻不能合并：既有一次性日界线设置会更新时间，却不代表保存新成绩；历史筛选、可删除成绩、公开活动或本次客户端 lastAccountResult 均不能作为真值。现代保存沿用服务入账整秒，旧奖励保留原 finishedAt。只有 `/v1/profiles/me/overview` 设置该字段；公开详情、匿名搜索和好友列表默认不返回，既有 `private, no-store` 和认证 UUID 边界不变。

原生只在本人概览且登录 UUID 匹配时显示连续日状态、是否真正保存、下个日界线倒计时和过期时长。TimelineView 使用本机时钟纯计算，不按秒请求网络、不更新持久账本；连续天数仍按原服务规则在下次保存时更新。覆盖未保存、今日、昨日、过期、设置参考变化、半小时偏移、午夜切换、旧服务缺字段和设备时钟落后。未保存却设置过日界线仍显示“尚无已保存成绩”；参考时间不冒充实际保存。原版在未来记录时误报过期，原生明确时钟不一致，不推断领取。

产品外 `check-source-profile-progress.mjs` 执行固定原文件的完整等级／格式函数、完整日期模块与完整 extraStreakText 回调，使用真实固定 date-fns 3.6.0，自有 props／snapshot／时钟，不运行 Solid、浏览器、真实 HTTP 或上游测试。33 组等级／格式和 144 组连续日回调夹具与原生逐组核对；记录一个实际负等级内 XP 的提前升级反例，并以独立 BigInt 曲线验证修正。另证明原版上午六时对前两天成绩显示“18 hours ago”，实际应从失效日界线算六小时；原生不复制这一错误。不是全控制器／UI 同构或完整功能无损证明。

迁移只涉及认证只读响应的可选字段，无存储实体／SwiftData／归档变化、无新 endpoint、重放或奖励写入。旧客户端忽略新字段，新客户端连接旧服务显示不可用；非法新字段按协议报错，不默默忽略。代码回退不需数据回滚。服务测试涵盖空账户、偏移选择、删除历史后磁盘重读、读取前后文件字节不变、封禁本人及公开 HTTP 不披露。可见性守卫与既有账户概览会话／服务器 ABA 守卫共同防止错账户内容；不改变此前其他账户操作的并发模式。

行为先行：原生接线一项三个预期失败、服务 HTTP 一项两处预期解包失败，日志 `/tmp/typebar-profile-progress-native-red.log`、`/tmp/typebar-profile-progress-server-red.log`。补服务投影后相关 17 项通过，再补持久／封禁／空状态为 20 项零失败零跳过（0.142 秒，`/tmp/typebar-profile-progress-server-verified.log`）。固定源码探针通过，日志 `/tmp/typebar-profile-progress-source-verified.log`。原生首轮新旧资料 fixture 漏既有必填成绩数，已保留 `/tmp/typebar-profile-progress-native-focused.log`；仅补 fixture 的成绩数和 bestWPM，不放宽生产协议，最终重跑另记。

源码驱动、行为先行、原生设计、迁移安全及同会话有界决策／风险复核促使分离保存／参考时刻、记录并修正原版数值与过期错误；非独立外部评审。新增三项人工验收仍待唯一隔离候选；离屏渲染不证明键盘／VoiceOver、完整窗口、实际后台恢复／时钟变化或目标设备。原版加入时长提示、主题精确身份、离线目录备份、整个功能覆盖仍开放，goal active。零 Typebar 应用启动、零部署，不读真实账户数据库／Keychain。

最终冻结完整串行门禁退出 0：原生 3,558 项零失败／零跳过（809.219 秒），服务 495 项零失败／零跳过（11.040 秒）；本轮实际十万词耐久 154.456 秒、16 项隔离磁盘冷读 6.291 秒通过。52 页面证据、1,053 人工结构、固定源码／原创边界与未启动应用包／scheme／严格签名检查通过。主日志 `/tmp/typebar-profile-progress-complete-readiness.log`，54 份分项日志 `/tmp/typebar-profile-progress-complete-logs.Z51diB`；门禁前后 12 文件哈希全部一致（`/tmp/typebar-profile-progress-frozen.sha256`），运行中未编辑。最终 45 张图位于 `/tmp/typebar-profile-progress-complete-render.184uH4`；六张新增连续状态／等级图与两张本人整卡已逐张检查，长文换行和累计／PB／活动内容保留。

图像检查发现系统 ProgressView 的轨道没有出现在离屏缓存图里，不能以这些图宣称轨道绘制已验收。门禁终止后仅追加一项 QA 测试，不修改任何生产实现／脚本／矩阵：直接从实际生产组件查到唯一 NSProgressIndicator，确认未隐藏、非不定进度、尺寸正常，0／50／99／100／174 XP 的归一数值均匹配模型（包含升级归零）。该补充一项零失败零跳过（0.689 秒，`/tmp/typebar-profile-progress-control-binding.log`）；不把它合并为同轮全量 3,559 项。原冻结的其余 11 文件保持一致，新增测试后的哈希另存 `/tmp/typebar-profile-progress-binding-qa.sha256`。这证明系统控件绑定，不证明可见窗口绘制或真实 VoiceOver；未为截图替换系统控件，轨道实际外观仍待唯一隔离候选验收。

修复必填字段 fixture 后的相关 54 项零失败零跳过（23.330 秒，`/tmp/typebar-profile-progress-native-verified.log`）；首轮 54 项中两处 fixture 解码失败保留，不能冒称首轮通过。系统 AddressBook／CoreData XPC 警告仍存在，未读取通讯录内容、真实 Typebar 数据库或 Keychain，也未修改系统权限；一次通过不证明历史性能离群已解决。上述设计／决策／迁移／风险检查均为同会话有界检查，非独立评审；纯原生增量已验证但全功能无损、原版加入时长提示、主题精确身份、离线目录备份、真实网络／后台时钟／键盘／VoiceOver／最低设备仍有缺口。零 Typebar 应用启动、零部署，整个 goal active。

## 原生公开资料分享增量

固定 UserDetails 的完整复制回调按当前站点 origin 与展示名生成公开网页链接，成功通知、失败直接提供原链接；固定 route-controller 的资料 load 强制进入资料页，queries/profile 的完整查询模块按展示名读取、缓存一小时，未找到不重试，其他失败最多三次。产品外 `check-source-profile-share.mjs` 只读执行这些实际回调／路由对象／查询模块，以明确自有剪贴板、导航、查询和 HTTP 适配器覆盖八组复制成功／失败、完整资料成功及三种 HTTP 错误、缓存与重试选择；不运行浏览器、Solid、真实剪贴板或 HTTP。首次探针的独立对象解析失败已保留，包装为表达式后执行通过，没有改参考代码。原生代码和资产仍独立编写，不带入参考实现。

本人概览增加“复制公开资料链接”，包括封禁本人；只携带 HTTP(S) 服务地址和稳定 UUID，不携带姓名、邮箱、令牌或私有资料。`typebar://profile` 版本 1 严格校验字段、长度、凭据、端口、编码主机与路径；规范化主机大小写、默认端口、末尾斜线，保留反向代理前缀。这里明确适配为原生已安装应用链接，不是 Monkeytype 网站链接，也不提供未安装应用时的网页降级；稳定 UUID 避免改名失效。包含 Unicode／空格等不可分享的服务地址明确禁用复制，不偷偷换服务器。

主场景使用既有 `typebar` 注册与 SwiftUI onOpenURL、已有场景 external-events 优先处理，忽略 OAuth 等非资料主机；不主动创建、激活或显示应用窗口。保护中练习或已有工作表时延后呈现，仅保留一个最新待处理链接，相同有效目标去重；现有搜索资料工作表另有手动粘贴导入，不自动读剪贴板。确认页先显示目标服务器和 UUID，用户明确确认才发匿名请求；HTTP 允许自建局域网，但警告和取消／确认固定可见，长地址正文可滚动。此接线和隔离队列测试不证明 LaunchServices、真实多窗口／sheet 通知顺序或 OAuth 回调已实机验收。

分享读取与当前 AccountSession／Keychain 完全分开：临时 URLSession，清除注入的附加头、Cookie、凭据和缓存存储，GET 无认证，不跟随任何重定向，拒绝密码／客户端证书等认证挑战，系统 TLS 信任仍按默认验证，不绕过证书错误。响应字节流上限 8 MiB、请求／资源超时 15／30 秒，要求响应 URL 和 UUID 匹配；错误保留关闭及显式重试，不把搜索摘要伪装成完整资料，不自动缓存一小时或三次重试，这是显式原生网络边界而非逐控制器同构。关闭取消请求，代次守卫阻止迟到成功／错误回写。资料好友／举报入口禁用，不能借当前账户向链接内服务器发写操作；正文沿用完整公开 DTO。Discord 头像保留，以同一匿名读取器、256,000 字节上限和 image/png 请求 CDN，确认页提前披露；失败用原头像占位，不降级到共享带凭据会话。

无 SwiftData／归档／服务器持久字段、接口或迁移变化，不自动切换登录或改变账户发布设置，回退只移除新入口，无数据回滚。HTTP 仅指链接解析／确认流程允许；未添加全局 ATS 例外，系统策略拒绝不安全连接时仍显示网络失败，不宣称所有局域网 HTTP 实机可用。行为先行接线一项产生六处预期失败（`/tmp/typebar-profile-share-red.log`）；第一轮实际模型／内存 URLProtocol 传输 11 项通过（0.132 秒），之后相关 41 项零失败／零跳过（19.990 秒，`/tmp/typebar-profile-share-focused.log`），其中新增会话／任务认证挑战回调检查；之后补匿名图片 Accept、预取消与固定警告，最终结果另记，不用旧绿灯证明修订。URLProtocol 不开 socket，重定向／认证委托使用未恢复任务显式调用，不冒充系统实际网络链路。

最终聚焦首轮 50 项中四项失败（`/tmp/typebar-profile-share-final-focused.log`）：新完整网络 fixture 把 activity.lastDay 错写为数字，与既有服务 ISO-8601 编码不符。核对真实模型／服务编码器后只修 fixture，14 项分享模型／内存传输／委托零失败零跳过（0.131 秒，`/tmp/typebar-profile-share-fixture-verified.log`），未放宽生产契约。该 50 项运行的 39 张图保留 `/tmp/typebar-profile-share-final-focused-render.Jsy4gR`，五张新增 HTTPS／HTTP／长地址／无效／只读组件图均检查过，长地址警告已固定；不能把这次图像成功写成 50 项全通过。最终完整门禁结果另记。

源码驱动、行为先行、原生设计、迁移安全及有界同会话决策／风险复核促使补齐头像匿名边界和固定警告，不是独立审查。新增三个人工项全部待验收，整体 goal active；原生链接仅完成这一增量，不代表原版全部功能已经无损。

最终冻结完整串行门禁退出 0：原生 3,547 项零失败／零跳过（803.531 秒），服务 491 项零失败／零跳过（18.406 秒）。十万词耐久本轮实际执行通过（151.742 秒），16 项隔离磁盘冷读通过（6.854 秒），52 页面证据、1,050 项人工清单结构、固定参考／原创性边界、未启动的应用包、既有 `typebar` scheme 及严格签名检查通过。主日志 `/tmp/typebar-profile-share-complete-readiness.log`，54 份保留分项日志 `/tmp/typebar-profile-share-complete-logs.Dw55ks`；11 份生产／测试／QA／映射冻结哈希前后一致（`/tmp/typebar-profile-share-frozen.sha256`），门禁运行期间未编辑，结束后仅补三份文档结果。新增源码复制／路由／查询探针也包含在完整门禁中。

全量套件重绘 39 张图到 `/tmp/typebar-profile-share-complete-render.uKUqxH`；五张新增分享图，以及新增复制按钮的本人浅色／封禁深色概览再次逐张检查，封禁编辑禁用但复制保留、HTTP 警告固定可见。每个渲染测试串行使用从不显示的隔离窗口并清理，无真实剪贴板、账户网络或应用激活；没有把离屏图升级为 LaunchServices／真实 sheet／辅助功能验收。之前的源码适配器解析失败与日期 fixture 失败日志均保留，不计为最终通过证据。

本轮零 Typebar 应用启动、零部署、未读取真实 Typebar 数据库或 Keychain。已有系统 AddressBook／CoreData XPC 警告仍在，未检查通讯录内容或修改系统权限；不把测试通过当成该警告根因已消除。挪威大词库两项本轮分别 14.780／11.662 秒，单轮耗时不证明历史性能离群已解决。固定参考 clone 仍干净。同会话有界风险复核未发现本增量其他阻断问题；实际 URL 唤起、多窗口／工作表顺序、TLS／ATS／代理、键盘／VoiceOver／目标设备与全功能无损仍缺证，整个 goal 保持 active。

## 本人资料编辑与私有徽章增量

实际读取固定 [UserDetails](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/UserDetails.tsx) 和 [EditProfileModal](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/modals/EditProfileModal.tsx)：本人页直接编辑简介、键盘、社交链接、选定徽章及公开活动，保存成功更新 snapshot／失效本人资料查询；失败不关闭或重置表单。名称／头像管理仍导向账户设置。本人徽章读取完整 inventory，而非访客披露后的子集，封禁阻止编辑而不抹掉本人库存。本增量独立实现这些用户路径，不复制 TSX、品牌徽章、图标资产或官方 ID。

`AccountProfileEditor.swift` 提取原有设置表单为唯一共享实现，设置与账户页使用相同字段、服务器校验与保存接口；常驻字段名、简介计数、进度、失败文字、可选空徽章和 Discord 头像开关保留。账户页打开独立可取消编辑 sheet，成功关闭并由实际账户快照身份变化触发重读；设置内保存留在原处。徽章公开开关沿用立即保存，不自动重置其他未保存字段，文字明确区分两种提交；sheet 挂在稳定概览层，不随加载分支销毁。本人私有徽章投影同时要求本人页与登录 UUID 匹配，不受 showAllBadges 或封禁过滤；公开页始终只用服务器公开 DTO，排行榜不变。

会话／服务器与退出重登 ABA 代次固定到编辑器，失效草稿在传输／凭据读取前拒绝；迟到成功、错误 UUID、取消和新会话错误不得覆盖新用户／状态。保存期间同账户资料若另行刷新，不覆盖新值，并明确提示服务端可能已保存、需刷新核对。独立忙碌状态代次只让本次资料请求释放自身占用，不清掉后来操作的忙碌标志；既有其他账户方法的全局并发模式不据此宣称全面重写。关闭时取消本地任务，但已到达服务器的 PATCH 可能已提交，取消不是网络事务回滚；徽章开关已立即保存的变更也不会因取消其他字段而撤销。普通字段草稿保留到明确保存／关闭，不持久保存草稿。

迁移边界：沿用 `PATCH /v1/profiles/me`，两个请求体仍分别只更新资料／选定徽章与 showAllBadges；不改变任何服务 DTO、存储字段、SwiftData 实体、归档、CSV、部署或凭据。旧服务错误保留草稿，旧客户端不受影响；回退代码不需数据回滚。保留 Typebar 现有字符长度与服务格式校验，没有把它冒称为 Zod UTF-16／社交用户名规则完全一致；原版全部校验、徽章目录和协议仍需另行对照。

行为先行接线一项产生四处预期失败（0.648 秒，`/tmp/typebar-owner-editor-red.log`）。首次相关 25 项零失败但一项缺参考环境跳过，不作完整证据；配置固定参考后，相关 35 项零失败零跳过（18.469 秒，`/tmp/typebar-owner-editor-render-focused.log`），包含九项生产组件渲染／实际 NSTextView 输入保留，初版 34 张图位于 `/tmp/typebar-owner-editor-focused-render.EtjBCF`。检查浅深色图后补充常驻字段标签；后续验证见最终记录，初版图片不作最终外观证据。会话内风险复核另以一项确定性失败证明旧资料操作会清除新操作忙碌状态（0.537 秒，`/tmp/typebar-owner-editor-busy-red.log`）；按 root-cause-debugging 定位到无所有权的 defer，增加本地代次守卫，不改所有其他操作的生命周期。

产品外 `check-source-account-profile-editor.mjs` 从固定原文件读取实际 createForm 配置与完整 onSubmit 回调；包装只增加返回配置供取证，form／snapshot／传输／通知为明确自有适配器。32 组字段／选定徽章／活动开关对照，四种 HTTP 状态失败、不完整默认值、缺 snapshot 与服务规范化返回通过；原生草稿逐组核对自己的字段映射。未运行 Solid、TSX UI、TanStack Form 验证器、Zod、真实 HTTP 或浏览器，不以这份有界证据宣称整个编辑器等价；探针登记串行门禁。

最终标签与并发守卫修订后，相关 36 项零失败零跳过（17.928 秒，`/tmp/typebar-owner-editor-final-focused.log`）；新增编辑测试共 11 项，生产渲染类共九项。冻结十个实现／测试／门禁文件的哈希（不含随后补记的三份说明文档），完整门禁退出 0：原生 3,532 项零失败、一个可选耐久跳过（606.210 秒），服务 491 项零失败零跳过（9.976 秒），16 项隔离磁盘冷读 6.676 秒。随后同一冻结代码显式 `TYPEBAR_ENDURANCE_TESTS=1 swift test --skip-build --filter CustomSequentialStreamingTests.testOptionalHundredThousandWordEndurance`，该一项零失败零跳过、145.616 秒。不能把这两次运行合写成同轮全量零跳过。

最终主日志 `/tmp/typebar-owner-editor-verified-readiness.log`，53 份保留日志 `/tmp/typebar-owner-editor-verified-logs.FjCNuD`，耐久 `/tmp/typebar-owner-editor-endurance.log`，冻结清单 `/tmp/typebar-owner-editor-frozen.sha256`。第一次门禁在原生测试前因默认 Redis 8.6.1 不符固定 6.2.6 停止，记录 `/tmp/typebar-owner-editor-complete-readiness.log` 和 `/tmp/typebar-owner-editor-complete-logs.B5NZsm`；重跑只指定既有隔离 6.2.6 服务端二进制，CLI 仍用支持 JSON 的当前版本，不改源码或版本断言，不访问默认 Redis 实例。完整门禁中的有界编辑探针、52 页面证据、1,047 人工项结构、未开窗包／严格签名／原创边界通过；最终 34 张组件图位于 `/tmp/typebar-owner-editor-verified-render.UF2UCC`，新增五张浅深色／未保存刷新／封禁／失效编辑图逐张检查。十个冻结哈希在门禁及耐久后保持一致。既有系统框架警告和真实设备／性能边界不由一次通过证明消失。

设计／决策／迁移／风险复核均在本会话内完成，非外部独立评审。真实账户保存／取消、稳定 sheet 与概览重读、VoiceOver／键盘、最低 macOS／Intel、网络和完整窗口仍待唯一隔离候选验收。分享接收／服务器确认、连续提示／等级细节、主题精确身份、离线目录备份及整个原版功能覆盖仍开放；AccountPage 与完整 goal 保持 active／部分覆盖，不把本轮共享编辑与私有徽章当作完成整个重写。未启动 Typebar 应用或使用真实账户／数据库／Keychain。

## 本人年度活动增量

固定 [ActivityCalendar](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/ActivityCalendar.tsx)、[完整日历类](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/elements/test-activity-calendar.ts)、[DB 年份 getter](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/db.ts) 与 [认证年度控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/user.ts) 已实际读取。原版近期与当前年度使用 snapshot，旧年份单次认证读取后缓存；旧年入口受 premium 开关／资格限制。Typebar 沿用无付费设计，开放从加入年到当前年的年份，不引入付费资格、第三方服务或广告。

新增认证只读 `GET /v1/profiles/me/activity`，以 token 决定身份，返回本人稀疏年度账本及历史完整性，不接受任意用户 ID。成功响应 `private, no-store`；公开资料 DTO／接口不新增年度字典，隐藏公开活动或封禁不阻止本人查看。账本已独立于可删除成绩保存，读取不改文件、不回填、不重新计算 XP／连续天数。无新持久字段或迁移，SwiftData／归档／CSV 不变；旧客户端不调用新入口，新客户端配旧服务只在选年后明确失败可重试，近期和历史功能不回退成伪造年度数据。回退此增量无需恢复数据，既有旧 writer 降级限制仍适用；无部署或真实账户操作。

原生本人日历增加系统年份 Picker、刷新、错误重试、空年份与不完整历史提示。近期和本年不读年度接口，本年从已载入 snapshot 按 UTC 年内索引截取并补未来空日；旧年份成功响应只缓存在当前视图，切旧年份复用，手动刷新／新累计次数改变请求身份；服务器／退出重登 ABA、错 UUID、取消、旧年份迟到回调均守卫。年份列表也用 UTC 加入年与当前年，避免本地跨年标签与 UTC 日历冲突；这是对原版本地年选项的明确边界修正，不冒称时区完全同构。公开卡仍只显示近期日历。视觉继续使用系统字体、语义色、等宽日历格与横向滚动，不增加资产；共用资料日历强度改为仅用非 null 日期计算截尾分布，明确零仍参与，符合完整参考类而不是把未知空日补进阈值。

产品外 `check-source-account-activity-years.mjs` 执行完整固定日历类、数值工具及 DB getter，真实 date-fns 3.6.0／@date-fns/utc 1.2.0、隔离 UTC 时钟／认证／传输适配器；46 组年度日期／计数／强度投影覆盖平闰年、三种周首日、短数组、满年、全空与 9／10／11 个已知值的截尾边界。它还执行近期／本年无 HTTP、旧年份缓存一次、缺年与未认证路径，不运行浏览器、Solid 或真实账户 HTTP；已登记完整门禁。首次探针把满年错误推测成丢掉末日，实际执行反驳：短历史数组错后一日，完整 365 天数组的末日变成次年一月一日，日历跨年且丢掉原年早期值。最终探针保留这两条真实反例。原生按 DAL 的 UTC 年内零起日索引保留原日期与所有计数，明确修正而不复制参考历史 getter 的日期错误；不能把它宣传为逐 bug 一致。日历布局、时区与浏览器像素仍非完整等价证据。

有效服务先行两项产生三处预期 404 失败（0.625 秒，`/tmp/typebar-activity-year-server-red.log`）；原生本人接线静态先行一项失败（0.541 秒，`/tmp/typebar-activity-year-native-red.log`），不是点击验收。服务首轮相关 20 项通过（0.171 秒，`/tmp/typebar-activity-year-server-focused.log`），包括身份／隐私／认证、跨年闰日／末日、删除成绩后隔离磁盘重载及读取字节不变。源码探针日志 `/tmp/typebar-activity-year-source.log`（错误预期）及 `/tmp/typebar-activity-year-source-final.log`（修正反例后通过）；后续强度对照、原生及完整验证以最终实际结果另记。

本轮使用源码驱动、行为先行、简化实现、原生设计、迁移安全、根因定位和有界同会话决策／风险复核，非独立审查。本人编辑／复制公开链接入口、私有徽章全部披露、连续状态提示、实机年份交互／键盘／VoiceOver、网络与目标设备、整体重写等仍未验收，goal active。以下“年度活动尚缺”等为上一阶段历史记录，由本增量部分取代，不表示新人工项已执行。

本年快照补证前相关原生 55 项零失败／零跳过（28.785 秒，`/tmp/typebar-activity-year-native-final-focused.log`），其中年度模型／实际加载器 10 项、共用生产渲染 8 项；首轮 54 项通过后，截图确认星期列与月份头齐顶而高于日格一行，生产星期列补同高月份占位后重跑。该阶段 29 张图保留 `/tmp/typebar-activity-year-verified-render.nvEgWF`，四张新增年度浅／深／窄／空／不完整组件图已逐张检查，星期与日格已对齐；该测试一个从不显示的 NSWindow 串行复用并清理，不发网络请求。首轮图 `/tmp/typebar-activity-year-render.pCKVEg` 与日志 `/tmp/typebar-activity-year-native-focused.log` 不替代后续最终取证。界面不会因图像检查而获得真实年份选择／VoiceOver／设备验收；最后修订由下列完整门禁覆盖。

随后同会话决策复核发现本年仍依赖年度接口，会损失原版已载入快照的离线能力；补一项实际加载器先行回归产生两处预期失败（0.709 秒，`/tmp/typebar-activity-year-current-snapshot-red.log`），先中止正在跑的首轮完整门禁，再补实现，未在编译／测试期间编辑。该中止运行 `/tmp/typebar-activity-year-final-readiness.log`／`/tmp/typebar-activity-year-final-logs.CpEURl` 不算完整通过。修正本年快照、未来空日、上一年不带入本年与 UTC 选项后，年度 12 项零失败零跳过（0.393 秒，`/tmp/typebar-activity-year-snapshot-focused.log`），新增四组实际 ModifiableTestActivityCalendar.getFullYearCalendar 对照与无年度请求回归。本年不显示会误导的年度 API 刷新按钮，改用已有账户概览刷新；后续最终门禁覆盖此修订，不以上述 55 项证明最后修订。

最后冻结修订完整串行门禁退出 0：原生 3,520 项（848.310 秒）、服务 491 项（11.433 秒）零失败／零跳过。十万词耐久实际执行并通过（174.368 秒），16 项隔离磁盘冷读通过（6.592 秒）；52 页面证据、1,044 条唯一人工场景仅结构核对，固定参考／原创边界、未启动应用包及严格签名校验通过。46 份分项日志 `/tmp/typebar-activity-year-complete-logs.bXdxP7`，主日志 `/tmp/typebar-activity-year-complete-readiness.log`，46 年度／四本年源码证据也在该日志目录；12 冻结生产／测试／QA／映射哈希门禁前后一致（`/tmp/typebar-activity-year-final-frozen.sha256`），运行期间没有编辑，之后只补文档证据。最终完整套件重绘 29 张图 `/tmp/typebar-activity-year-complete-render.TV6UCO`，四张新增年度图再次逐张检查；并非只复用前轮截图。

零 Typebar 应用启动、零部署，没有读取真实 Typebar 数据库或 Keychain 凭据。系统 AddressBook/CoreData XPC 警告仍在，未据此改系统权限或检查通讯录；来源与性能不确定性继续沿用下节记录。本轮挪威语大词库 15.184 秒，单轮未复现旧离群耗时不等于已解决性能问题。固定 clone 仍干净。同会话有界风险复核已修正本年离线退化及星期视觉错位，未发现本增量其他阻断问题；真实 Picker／网络／键盘／VoiceOver／目标设备仍缺证。完整 goal active，不能把这次通过解释为原版全功能无损已经证明。

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
