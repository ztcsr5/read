# Legado JS 兼容矩阵（Swift 原生运行时）

本矩阵记录 SourceReadSwift 与 Flutter `LegadoJsEngine` 的高频交集，避免把“函数存在”误当作“行为已验证”。

## 已覆盖并有 XCTest

| 类别 | API/行为 | 验证 |
|---|---|---|
| 网络 | `java.ajax/get/post/fetch/connect/ajaxAll/head`、`URLConnection` 属性/流/状态 | `LegadoNativeBridgeTests`、`LegadoStage10CompatibilityTests` mock response |
| 解析 | `java.getString/getStringList/getElements`，CSS/XPath/JSONPath | `LegadoNativeBridgeTests`、规则解析测试 |
| DOM | `org.jsoup.Jsoup`、JXNode、元素/属性/兄弟节点链 | `LegadoNativeBridgeTests` |
| 存储 | `java.put/get/remove/getStr/putJson/getJson` | `LegadoNativeBridgeTests` |
| 编码 | Base64、字节数组、Hex、MD5/SHA/RIPEMD160/HMAC、AES、charset-aware String bytes、RSA facade | `LegadoNativeBridgeTests`、`LegadoStage10CompatibilityTests` |
| Java facade | `StringBuilder`、`HashMap`、`ArrayList`、`Pattern/Matcher`、`URL/URI` | `LegadoNativeBridgeTests`、`LegadoStage10CompatibilityTests` |
| Android facade | `Build`、`TextUtils`、`Base64` | JS prelude + runtime surface test |
| 模型 | source/book/chapter getter、variable map、VIP | model bridge tests |

## 设计约束

- JavaScriptCore 回调是同步的；外部网络只能通过 `RuleExecutionContext` 的 handler 注入。
- 文件/ZIP 访问保持在 `Documents/LegadoSandbox` 内，不读取或导出系统凭据。
- `java.net.URL.openConnection()` 返回现有连接链 facade，不绕过网络层。
- 未实现的 Android 专有能力应保持空值/可观测失败，不伪造真实登录、验证码或付费访问。

## Stage 10 兼容闭环（本轮）

- 增强 `java.net.URL.openConnection()`：请求头、超时、请求方法、输入/输出流、响应状态与响应头均通过 `RuleExecutionContext` fixture 走同步桥接。
- 补齐 Java 集合/字符串/正则高频方法：`StringBuilder` 变更、`HashMap` entry `setValue` 与批量操作、`ArrayList` 索引/集合操作、`Matcher` 查找/替换/region 元数据。
- 修复 CryptoJS binary `WordArray` 的 `sigBytes` 截断与 Hex/Base64 stringify；新增 RIPEMD-160 与 RSA（Security.framework，PEM/DER/base64 key）桥接。
- 增加 Stage 10 离线 XCTest，覆盖 URL/URI、URLConnection、ByteArrayInputStream、集合、正则、缓存/window/document/source 元数据、Flutter 工具别名与二进制 WordArray。

## 下一批兼容项

1. 更完整的 `java.util.regex.Matcher`（`start/end/groupCount`）。
2. Jsoup `Document` 的 `location`, `head`, `body`, `title` 与资源绝对 URL 回归。
3. 真实书源样本脱敏后的 search/detail/toc/content 端到端 fixture。
