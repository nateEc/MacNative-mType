# 官方好友关系功能映射审计

固定参考提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。

## 本次覆盖

参考项目的 `frontend/src/ts/components/pages/connections/PendingRequests.tsx` 将收到的请求分为接受、拒绝与屏蔽三种动作：它导入三种连接操作，并在请求行分别调用它们。`FriendsList.tsx` 还覆盖搜索、发送、已有好友移除及状态提示。

Typebar 的原创 SwiftUI `ConnectionsView` 将这些可见意图映射为：

| 参考行为 | 原生实现 | 验证 |
| --- | --- | --- |
| 收到请求：接受 | `acceptConnection` | 既有连接关系覆盖 |
| 收到请求：拒绝 | `ConnectionActionPolicy` 仅对 `.incomingRequest` 展示“拒绝”，并调用 `removeConnection` | `testConnectionActionPolicyOffersRejectionOnlyForIncomingRequests`；`testIncomingConnectionCanBeRejectedWithoutBlocking` |
| 收到请求：屏蔽 | `blockUser` | 既有服务端屏蔽语义 |
| 已发送请求取消、好友解除 | 同一 `removeConnection` 动作 | 服务端双向关系查找 |

`server/Sources/TypebarServerCore/AuthStore.swift` 的 `removeConnection` 只删除当前账户与目标账户之间的关系；`blockUser` 是独立操作，才会写入屏蔽集合并清理私信。`server/Sources/TypebarServerCore/Routes.swift` 将受令牌保护的删除请求交给前者，因此“拒绝”不会隐式转化为“屏蔽”。

## 重写边界与隐私

此实现只根据固定参考观察可见行为，不复用其 TypeScript、路由代码、文案或资产。网络调用面向 Typebar 自建服务；拒绝请求不新增归档、同步、公开资料字段、提示、回放、邮箱或令牌暴露。

## 验证记录

- 服务端目标测试：`swift test --filter HealthRouteTests/testIncomingConnectionCanBeRejectedWithoutBlocking`，1 项通过。
- 原生完整测试：`swift test`，645 项通过、0 失败，耗时 161.221 秒。
- 静态验证：`git diff --check`。

尚未执行 GUI 人工验收：当前任务遵守不启动 Typebar 图形进程的约束。后续可在单一实例中确认收到的请求行同时显示“接受 / 拒绝 / 屏蔽”，并验证“拒绝”后双方请求消失而“已屏蔽”列表保持不变。
