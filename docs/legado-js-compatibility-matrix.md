# Legado JS 兼容矩阵（Swift 原生运行时）

本矩阵记录 SourceReadSwift 与 Flutter `LegadoJsEngine` 的高频交集，避免把“函数存在”误当作“行为已验证”。

## 已覆盖并有 XCTest

| 类别 | API/行为 | 验证 |
|---|---|---|
| 网络 | `java.ajax/get/post/fetch/connect/ajaxAll/head` | `LegadoNativeBridgeTests` mock response |
| 解析 | `java.getString/getStringList/getElements`，CSS/XPath/JSONPath | `LegadoNativeBridgeTests`、规则解析测试 |
| DOM | `org.jsoup.Jsoup`、JXNode、元素/属性/兄弟节点链 | `LegadoNativeBridgeTests` |
| 存储 | `java.put/get/remove/getStr/putJson/getJson` | `LegadoNativeBridgeTests` |
| 编码 | Base64、字节数组、Hex、MD5/SHA/HMAC、AES、charset-aware String bytes | `LegadoNativeBridgeTests`、JSCore tests |
| Java facade | `StringBuilder`、`HashMap`、`ArrayList`、`Pattern`、`URL` | `LegadoNativeBridgeTests` |
| Android facade | `Build`、`TextUtils`、`Base64` | JS prelude + runtime surface test |
| 模型 | source/book/chapter getter、variable map、VIP | model bridge tests |

## 设计约束

- JavaScriptCore 回调是同步的；外部网络只能通过 `RuleExecutionContext` 的 handler 注入。
- 文件/ZIP 访问保持在 `Documents/LegadoSandbox` 内，不读取或导出系统凭据。
- `java.net.URL.openConnection()` 返回现有连接链 facade，不绕过网络层。
- 未实现的 Android 专有能力应保持空值/可观测失败，不伪造真实登录、验证码或付费访问。

## 下一批兼容项

1. 更完整的 `java.util.regex.Matcher`（`start/end/groupCount`）。
2. Jsoup `Document` 的 `location`, `head`, `body`, `title` 与资源绝对 URL 回归。
3. 真实书源样本脱敏后的 search/detail/toc/content 端到端 fixture。
