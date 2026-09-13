---
name: unreal-dev-http
description: 必须在 Unreal 项目涉及后端 HTTP 服务、后端 API、REST API、HTTP endpoint 或客户端/服务器 HTTP 集成时调用。
license: MIT
compatibility: opencode
---

# Unreal Dev HTTP

## 定位

本 skill 用于 Unreal 客户端接入后端 HTTP 或 REST 服务时的契约检查和实现提醒。它总结后端 HTTP contract 的关键规则，帮助 UE 端、后端、UI 调试流程保持一致。

这不是实现请求。调用本 skill 不代表要新增后端 endpoint，也不代表 `/data`、`/data/{id}` 或 `/data/action` 已经存在。除非后端实现计划明确要求，这些通用 endpoint 只算 proposed contract examples。

## 必须调用场景

遇到下面任一情况，必须先调用本 skill：

* Unreal 项目要访问后端 HTTP service。
* Unreal 客户端要接入 backend API、REST API 或 HTTP endpoint。
* UE Widget、Subsystem、Actor、Controller、GameInstance 需要读取或发送 JSON HTTP 数据。
* 需要设计或审核 client/server HTTP integration。
* 需要确认 UE 端和后端对 status code、JSON body、headers、auth headers 的约定。
* 需要调试 UE 端显示 success、empty、offline、error 状态。

## 非调用场景和护栏

下面情况不要调用本 skill：

* 非 HTTP 的 Unreal 工作，例如本地动画、物理、材质、纯输入逻辑。
* 纯 UMG layout 或样式调整，没有后端请求。
* 纯本地 gameplay，没有 client/server HTTP integration。
* 纯后端任务，且没有 Unreal 客户端接入或 UE contract 需求。

不要把通用 contract 强行套到所有已有服务。已有 social endpoints 可以继续返回 flat JSON，例如 `{ "friends": [] }`。不要因为新通用后端推荐 `{ code, message, data }`，就重写或迁移已有 social API。

## 后端 contract 规则

### Base URL

Base URL 必须可配置，不能写死在 Widget 里。推荐在 GameInstance、Subsystem、配置界面或 Blueprint 可配置项中设置，然后让 Widget 只保存相对 endpoint path。

### Headers

JSON 请求应使用：

```http
Accept: application/json
Content-Type: application/json
```

所有 JSON 请求建议带 `Accept: application/json`。有 JSON body 的请求必须带 `Content-Type: application/json`。

### JSON response shape

新通用后端推荐使用 envelope：

```json
{
  "code": "OK",
  "message": "Data loaded",
  "data": {}
}
```

已有 social endpoints 可以保留 flat JSON shape，例如：

```json
{
  "friends": []
}
```

### `FAPIResponse` 映射

UE 侧响应对象应按下面规则理解：

* `StatusCode` 映射真实 HTTP status code，例如 `200`、`400`、`404`。
* `bSuccess` 来自 HTTP `200` 到 `299` 区间。
* `Code` 映射 envelope 顶层 `code`。
* `Message` 映射 envelope 顶层 `message`。
* `Data` 映射 envelope 顶层 `data` 的序列化 JSON 值。
* `RawBody` 保存完整 response body，用于 flat JSON、诊断和 UI 展示。
* `ErrorMessage` 保存本地请求失败、无响应、非成功 status code 等错误信息。

### Proposed endpoint examples

这些路径是 contract 示例，不是已实现证明：

* `GET /health`，检查后端是否可达。
* `GET /data`，通用数据读取示例。
* `GET /data/{id}`，记录详情示例。
* `POST /data/action`，用户动作示例。

如果项目已有等价 health endpoint 或业务 endpoint，以项目文档为准。不要声称 `/data` 或 `/data/action` 当前存在，除非后端实现计划或实际代码证明它们存在。

### HTTP status code

使用真实 HTTP status code。不要所有错误都返回 `200 OK`，因为 UE 侧通常从 HTTP status range 推导 `bSuccess`。

常见约定：

* `200`、`201`、`204` 表示成功。
* `400` 表示 validation error。
* `401` 表示 unauthorized。
* `403` 表示 forbidden。
* `404` 表示 not found。
* `409` 表示 conflict。
* `429` 表示 rate limited。
* `500` 表示 internal error。
* `503` 表示 service unavailable。

### CORS

UE native HTTP 不受浏览器 CORS 限制，通常不需要 CORS 才能调用后端。

浏览器 debug client、admin tool、API explorer、本地 web frontend 可能需要 CORS。为这些工具配置 CORS 时，只开放实际使用的 origin、method 和 header。

## Unreal 实现检查清单

实现 C++ HTTP 时检查：

* 在 module `Build.cs` 中加入 `HTTP`、`Json`、`JsonUtilities`。
* 可复用 HTTP client 优先放到 `UGameInstanceSubsystem`，不要把网络逻辑塞进单个 Widget。
* 异步回调触碰 `UObject` 或 UI 前，先 dispatch 到 Game Thread。
* 异步 callback 捕获对象时使用 `TWeakObjectPtr`，或在访问前做 validity checks。
* Auth headers 必须显式，命名和来源要写进 contract 或注释，例如 `Authorization`、`X-User-ID`。
* UI 刷新前，用 `/health` 或项目文档中的等价 endpoint 验证后端可达。
* Base URL、endpoint path、auth 配置要能被环境或项目配置替换。
* Widget 只负责显示状态和调用请求入口，不负责拼接硬编码生产 URL。

## 验证清单

完成 UE HTTP 集成后执行：

* Build UE editor target。
* 运行 backend，或确认提供的服务正在运行。
* 用 `curl` 或 HTTP client 测试 health endpoint。
* 测试一个 success endpoint 和一个 error endpoint，确认 status code、body、headers 正确。
* 在 UE UI 中验证 success、empty、offline、error 状态都能显示，且不崩溃。
* 关闭或断开 backend 后，再验证 UI 不会访问已销毁对象。

## 与其他 Unreal skills 的关系

* 普通 UE C++、输入、蓝图序列化问题仍按 `unreal-dev`。
* UMG 资产自动搭建仍按 `unreal-dev-umg`。
* 只要 UMG 或 gameplay 需要 HTTP backend，就同时参考本 skill。
