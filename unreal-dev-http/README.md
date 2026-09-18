# Unreal 客户端接入后端 HTTP 服务

> UE 端对接后端 REST API 时的契约检查与实现提醒：headers、响应 envelope、status code、`FAPIResponse` 映射，以及 C++ 侧的线程与对象生命周期注意事项。

## 什么时候用（必须调用）

- Unreal 项目要访问后端 HTTP service
- UE 客户端要接入 backend API、REST API 或 HTTP endpoint
- UE 的 Widget、Subsystem、Actor、Controller、GameInstance 需要读取或发送 JSON HTTP 数据
- 需要设计或审核 client/server HTTP integration，或确认 UE 端与后端对 status code、JSON body、headers、auth headers 的约定
- 需要调试 UE 端显示的 success / empty / offline / error 状态

## 不要用（护栏）

- 非 HTTP 的 Unreal 工作（本地动画、物理、材质、纯输入逻辑）
- 纯 UMG layout 或样式调整，没有后端请求
- 纯本地 gameplay，没有 client/server HTTP integration
- 纯后端任务，没有 Unreal 客户端接入或 UE contract 需求

**这不是实现请求**：调用本技能不代表要新增后端 endpoint，也不代表 `/data`、`/data/{id}`、`/data/action` 已经存在——除非后端实现计划明确要求，它们只算 proposed contract examples。

## 契约规则

**Base URL** 必须可配置，不能写死在 Widget 里。推荐放在 GameInstance、Subsystem、配置界面或 Blueprint 可配置项中，Widget 只保存相对 endpoint path。

**Headers**：JSON 请求建议带 `Accept: application/json`；有 JSON body 的请求必须带 `Content-Type: application/json`（两行原样照抄进请求头即可）。

**JSON response shape**：新通用后端推荐 envelope，已有 social endpoints 可以保留 flat JSON（例如 `{ "friends": [] }`），**不要**因为新推荐就去重写已有 API。

```json
{
  "code": "OK",
  "message": "Data loaded",
  "data": {}
}
```

**`FAPIResponse` 映射**：`StatusCode` ← 真实 HTTP status（`200`/`400`/`404`…）；`bSuccess` ← HTTP `200`–`299`；`Code` ← envelope 顶层 `code`；`Message` ← 顶层 `message`；`Data` ← 顶层 `data` 的序列化 JSON 值；`RawBody` 保存完整 response body（供 flat JSON、诊断、UI 展示）；`ErrorMessage` 保存本地请求失败、无响应、非成功 status code 等错误信息。

**Proposed endpoint examples**（仅是 contract 示例，不是已实现证明）：`GET /health` 检查后端可达；`GET /data` 通用读取；`GET /data/{id}` 记录详情；`POST /data/action` 用户动作。项目已有等价 endpoint 时以项目文档为准。

**HTTP status code**：用真实 status，不要所有错误都返回 `200 OK`（UE 侧通常从 status range 推导 `bSuccess`）。约定：`200`/`201`/`204` 成功；`400` validation error；`401` unauthorized；`403` forbidden；`404` not found；`409` conflict；`429` rate limited；`500` internal error；`503` service unavailable。

**CORS**：UE native HTTP 不受浏览器 CORS 限制，通常不需要 CORS。浏览器 debug client、admin tool、API explorer、本地 web frontend 可能需要——只开放实际使用的 origin、method 和 header。

## UE 实现检查清单

- 在 module `Build.cs` 中加入 `HTTP`、`Json`、`JsonUtilities`
- 可复用 HTTP client 优先放到 `UGameInstanceSubsystem`，不要把网络逻辑塞进单个 Widget
- 异步回调触碰 `UObject` 或 UI 前，先 dispatch 到 Game Thread
- 异步 callback 捕获对象用 `TWeakObjectPtr`，或在访问前做 validity checks
- Auth headers 必须显式，命名和来源写进 contract 或注释（如 `Authorization`、`X-User-ID`）
- UI 刷新前用 `/health` 或项目文档中的等价 endpoint 验证后端可达
- Base URL、endpoint path、auth 配置要能被环境或项目配置替换
- Widget 只负责显示状态和调用请求入口，不负责拼接硬编码生产 URL

## 验证清单

- Build UE editor target
- 运行 backend，或确认提供的服务正在运行
- 用 `curl` 或 HTTP client 测试 health endpoint
- 测试一个 success endpoint 和一个 error endpoint，确认 status code、body、headers 正确
- 在 UE UI 中验证 success、empty、offline、error 状态都能显示且不崩溃
- 关闭或断开 backend 后，再验证 UI 不会访问已销毁对象

## 注意事项 / 与其他技能的关系

- 不要把通用 contract 强行套到所有已有服务上（已有 social endpoints 继续返回 flat JSON 是允许的）
- 普通 UE C++ 与蓝图序列化问题按 `unreal-cpp-foundations` / `unreal-module-build`；输入与 IMC 问题按 `unreal-imc-mapping-verify`
- UMG 资产的自动搭建/手术走官方 MCP，按 `unreal-official-mcp-surgery`
