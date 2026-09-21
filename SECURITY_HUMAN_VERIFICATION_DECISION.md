# SEC-01 外部人机验证设计审查

## 结论

Typebar 将实现一个**可选部署、配置后强制执行**的 Cloudflare Turnstile 适配，而不是把进程内速率限制误称为人机验证，也不定义一个没有实际互操作实现的“通用 CAPTCHA”接口。它通过 Typebar 自建服务生成短期、单用途、一次性消费的挑战；macOS 使用 `ASWebAuthenticationSession` 打开该服务托管的挑战页，获得仅可提交一次的证明。服务端在任何用户写入前独立验证并消费证明，客户端从不拥有 Turnstile 私密密钥。

该能力不访问、代理或依赖 Monkeytype 的代码、域名、账户或密钥。Cloudflare Turnstile 是部署者主动选择和配置的独立第三方；未配置的旧／本地服务保留既有速率限制行为，但能力接口必须如实报告人机验证未启用，不能声称受保护。

## Claim 与契约

**Claim：** 当部署者完整配置 Turnstile 后，攻击者不能仅通过直接调用 Typebar 写 API 绕过挑战；一个已验证证明不能跨用途、过期重放或并发复用。失败、取消和第三方验证不可达时不得放行受保护写入。

| 类型 | 内容 |
| --- | --- |
| 已知事实 | 官方固定参考在密码创建账号、Google OAuth 首次补名创建账号、找回密码请求、用户举报、引语投稿和引语举报中提交验证码 token，并在服务器侧验证。 |
| 已知事实 | Typebar 已有 `ASWebAuthenticationSession`，并在 OAuth 中严格校验 `typebar://oauth/callback` 的 scheme、host、path 与 state。 |
| 已知事实 | Typebar 当前限速是进程内固定窗口；重启会清空，且不会验证人机证明。 |
| 设计约束 | 不持久化原始证明或第三方 token；不把私密密钥给 macOS；不改变未配置服务的既有注册／本地开发可用性。 |
| 部署前提 | 配置一对 `TYPEBAR_TURNSTILE_SITE_KEY`／`TYPEBAR_TURNSTILE_SECRET`，并配置允许的 Turnstile hostname；受保护的生产端点经 HTTPS 公开。 |
| 可观察属性 | 已配置服务在缺失、错误、过期、用途不符或已消费证明时拒绝写入；旧服务的能力字段缺失时原生客户端不请求新接口。 |

## 最小可审计协议

```text
macOS                    Typebar service                   Turnstile
  | POST /challenges purpose  |                                  |
  |-------------------------->| create opaque challenge          |
  |  relative verificationURL |                                  |
  |<--------------------------|                                  |
  | ASWebAuthenticationSession GET /web                           |
  |-------------------------->| HTML: widget(action,cData=id)    |
  |                            |<------- browser challenge ------>|
  |                            | POST token -> siteverify         |
  |                            |--------------------------------->|
  |                            | validate success/action/cData/host|
  | typebar://human-verification/callback?id&proof                |
  |<--------------------------| mark verified, issue opaque proof |
  | protected write { proof } |                                  |
  |-------------------------->| atomically consume(id, proof, purpose)
  |                            | only then execute write          |
```

协议对象：

- `HumanVerificationPurpose`：`registration`、`passwordResetRequest`、`profileReport`、`quoteSubmission`、`quoteReport`。
- `HumanVerificationProof`：挑战 UUID 加随机证明；只在内存和本次请求中存在。
- `HumanVerificationChallenge`：状态 `pending → verified → consumed`，5 分钟有效；验证成功后的 callback proof 只能消费一次。
- `POST /v1/human-verification/challenges` 只在提供方已配置时创建；响应返回**相对**挑战路径，客户端以当前服务 endpoint 解析，避免服务端猜测反向代理的公网 URL。
- `GET …/web` 仅提供 Typebar 自写的最小 HTML 容器；`POST …/complete` 在服务端请求 Turnstile `siteverify`，检查 `success`、固定 action、cData 与配置的 hostname，随后才重定向到固定 `typebar://human-verification/callback`。
- 受保护写接口把 proof 作为请求体字段传给服务端；服务端在执行写入前、同一 actor 临界区中消费它。密码注册和 OAuth 新用户注册同属 `registration` 用途；OAuth 身份绑定、已有账户登录、会话、密码重置完成和普通读取不在此范围内。

## 对抗性审查

### 1. 直接 API 调用、重放与并发

**反例：** 自动化客户端跳过 macOS 页面，或两条并发写请求复用同一已完成 token。

**证据：** 当前密码注册、OAuth 新用户注册、重置请求、资料举报、引语投稿与举报路由各自直接调用 store；仅客户端显示控件无法保护路由。

**处理：** 把 proof 消费放进服务端 actor、在业务写入之前执行，并按 purpose 比较。记录从 `verified` 原子转为 `consumed`；第二次、过期或用途不符均为拒绝。分类：**可行动缺陷，纳入实现和并发测试。**

### 2. 伪造回调、错误站点和验证服务故障

**反例：** 恶意网页打开 `typebar://…`，将其他站点的 token 交给完成接口，或第三方校验超时／返回错误。

**证据：** `ASWebAuthenticationSession` 的回调 scheme 可被任意浏览器导航触发；因此 scheme 本身不是可信证明。官方同样只在服务器调用验证码验证 API 后才信任 token。

**处理：** callback 仅携带服务端已经标记为 verified 的随机 proof；完成接口强制检查 Turnstile 响应的 success、action、cData 和 hostname。任一校验、网络或配置错误都保持 `pending`／失败并返回失败，不生成 proof。分类：**可行动缺陷，纳入伪造 callback、hostname、provider 失败测试。**

### 3. 配置缺失、旧服务与降级

**反例：** 部署者只设置 site key 或 secret，或客户端对没有该能力的旧服务强行请求新路由；更糟的是服务端悄悄跳过验证却显示已开启。

**证据：** Typebar 已用 capabilities 表达可选邮件和 OAuth 配置，原生客户端也要兼容旧服务。

**处理：** 配置必须成对且 hostname 列表有效；不完整配置使服务启动失败。完整配置时 capabilities 将人机验证标为可用，并对五种用途、六条具体写入路径 fail closed。完全未配置时能力如实为计划中，写路由保留当前契约；原生客户端只在能力为可用时启动挑战。分类：**接受的兼容性权衡。** 它让本地／既有自建服务不突然失效，但生产部署必须显式配置才能获得官方同等的额外防滥用层。

### 4. 内存状态、重启与隐私

**反例：** 服务器重启、用户取消、macOS 回调泄露、或把 token／邮箱写入磁盘日志。

**证据：** 当前服务的速率限制也是进程内；重启后无法安全恢复第三方挑战状态。Typebar 的账号令牌已通过 Keychain 管理，邮件／重置码只存散列。

**处理：** 挑战状态仅内存保存，重启后全部失效并要求用户重新验证；callback proof 不写 UserDefaults、SwiftData、Keychain 或日志。挑战只含 UUID、用途、到期和状态，不含邮箱、展示名或报告内容。分类：**接受的可用性权衡，失败安全。**

## 实现与验收记录

1. 已实现 `HumanVerificationController`、Turnstile Siteverify 适配、服务托管的最小挑战页与固定 callback；配置由三项环境变量共同决定，局部配置会在启动时失败。
2. 已为密码注册、OAuth 新用户注册、密码重置请求、资料举报、引语投稿和引语举报编写服务端覆盖：缺 proof 拒绝、正确用途可写、重放拒绝；另有用途替换、到期、hostname 不符、配置不完整与 provider 故障的拒绝测试。OAuth 路由的缺 proof 拒绝后保留注册 transaction，验证成功后可完成，防止验证门禁本身消耗用户可重试状态。测试通过注入 Siteverify 结果，不向 Cloudflare 发送请求。
3. 已实现原生能力协商、仅 HTTPS endpoint 的相对挑战路径解析、固定 callback 三元组校验和各受保护请求的 proof 携带。旧服务或能力缺失时不会调用新路由。
4. 自动化验收必须以单个串行会话完成服务端完整套件与原生完整套件，且不得启动 GUI。真实部署仍须由部署者使用自己的 Turnstile 密钥和 HTTPS hostname 手工验证一次；配置说明只列环境变量和失败语义，绝不提交真实密钥。
5. 后续代码风险复核确认网页回调必须按浏览器的 URL 编码表单格式验收，服务端用该格式完成端到端测试；同时修正固定窗口限流桶未回收的问题。每个桶现在携带到期时间，只在最早到期时清理失效状态；注册、重置与人机验证入口的配额本身不变。
6. 固定参考源码复核确认 `GoogleSignUpModal` 在调用 `Ape.users.create` 前要求 captcha；因此 Typebar 的 OAuth 新用户注册不能因其统一提供方流程而绕开既有 `registration` proof。完整服务端 108 项与原生 651 项串行套件均已通过，且未启动 GUI。

## 残余风险

- Turnstile 是外部可用性与隐私依赖；部署者应在隐私说明中披露，并保留速率限制作为第二道防线。
- 内存挑战状态不跨多实例共享。因此初版必须明确限制为单服务进程；多副本部署前需要共享、原子且有 TTL 的挑战存储，不能依赖黏性会话作为安全保证。
- 这验证的是提供方给出的自动化防护信号，不是可证明的人类身份；不用于账户信誉、自动处罚或反作弊判定。
