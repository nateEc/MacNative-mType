# 官方账户资料与邮箱验证路径审计

固定参考：`91bd24bb8513785c7364cbea29296ff7adafac41`。本记录仅审计用户可观察的账户资料和验证行为；Typebar 不复制 Monkeytype 的网页代码、账号数据、样式或资产。

| 固定参考路径 | 用户可见行为 | Typebar 原生映射 | 自动化证据 |
| --- | --- | --- | --- |
| `components/pages/account/MyProfile.tsx` | 在账户页把当前账户快照交给个人资料卡；没有账户时显示空状态。 | “设置 → 自建账户”显示当前登录身份，并可编辑公开显示名、简介、键盘说明、GitHub、X、HTTPS 网站、公开活动、Discord 头像和公开徽章；公开资料阅读页保持邮箱、令牌与本机练习内容私密。 | `testRemoteAccountUserDefaultsLegacyServersToPasswordAndDecodesOAuthMethods`、`testLegacyPublicProfileResponseDefaultsMissingHighestConsistencyToZero` |
| `components/pages/account/VerifyNotice.tsx` | 未验证邮箱时显示提示并允许重发验证邮件。 | 未验证状态在同一原生账户设置中明确显示；用户可发送邮件、粘贴一次性验证码并确认，成功后重新读取当前资料并显示已验证状态。 | `testRemoteAccountUserDefaultsLegacyServersToPasswordAndDecodesOAuthMethods` |

## 边界

网页参考依赖其账号会话；Typebar 的可见等价界面只针对用户主动配置的自建服务账户。验证请求和确认只在用户操作时向该服务发出，令牌按服务地址保存在钥匙串，公开资料不会返回邮箱、令牌、提示或本机回放。

## 验证

- 固定参考源码已核对 `MyProfile.tsx` 和 `VerifyNotice.tsx` 的页面职责。
- 2026-09-22 完整 `swift test`：644 项、0 失败、161.925 秒。CoreData/AddressBook XPC 提示是既有测试环境噪声，XCTest 汇总为准。
- 未对真实邮件服务或浏览器会话做端到端人工测试；本轮遵守“不启动多个 Typebar”的约束，不启动 Typebar 图形界面。
