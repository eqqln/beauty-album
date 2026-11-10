# 04 · IPA 端双向同步

> 目标：手机 App 与网站后台共用同一份数据。改一边，另一边刷新即可见。
> 新增文件：`BeautyAlbum/Services/SyncService.swift`、`BeautyAlbum/Views/ShopSyncView.swift`
> 修改文件：`Services/CloudAPI.swift`、`Services/Store.swift`、`Views/AccountView.swift`

---

## 一、为什么不给每个界面加网络请求

IPA 原本 15 个界面全部直接读写 `Store` 的本地数组，数据落在 `Documents/BeautyAlbum/data.json`。

如果在每个界面里插入网络请求，会带来三个问题：

1. 15 个界面 × 增删改 ≈ 50 处调用点，任何一处漏掉就会出现「这边改了那边没变」
2. 弱网时界面卡住，用户体验反而更差
3. 主界面和现有功能被改动，违背「不要动主界面」的要求

所以采用**数据层拦截**：`Store` 的每个写操作加一行 `SyncService.touch(...)`，只做登记，不发请求。真正的网络同步在「我的 → 店铺数据同步 → 立即同步」时统一执行。

好处：

- 界面代码一行没改，主界面完全不变
- 弱网、断网时本地照常可用，联网后一次同步补齐
- 冲突处理集中在一处，逻辑可审计

---

## 二、改动登记（`Store.swift`）

`Store` 的每个写方法末尾加一次登记。共 17 处：

| 方法 | 登记内容 |
|---|---|
| `addClient` / `updateClient` | `syncTouchClient(id)` |
| `deleteClient` | `markDeleted("customers", id)` |
| `addTeacher` / `updateTeacher` | `touch("teachers", id)` |
| `deleteTeacher` | `markDeleted("teachers", id)` |
| `addAppointment` / `updateAppointment` | `touch("appointments", id)` |
| `deleteAppointment` | `markDeleted("appointments", id)` |
| `addProduct` / `updateProduct` | `touch("products", id)` |
| `deleteProduct` | `markDeleted("products", id)` |
| `addAgent` / `updateAgent` | `touch("agents", id)` |
| `deleteAgent` | `markDeleted("agents", id)` |
| `addOrder` / `updateOrder` | `touch("agent_orders", id)` |
| `deleteOrder` | `markDeleted("agent_orders", id)` |

客户比较特殊：照片、步骤、笔记、收款、领用都是 `Client` 的内嵌数组，任何一处变动都会走 `updateClient`。所以 `syncTouchClient` 一次把 6 个模块全标脏：

```swift
private func syncTouchClient(_ id: UUID) {
    let s = SyncService.shared
    s.markDirty("customers")
    s.markDirty("photos")
    s.markDirty("steps")
    s.markDirty("notes")
    s.markDirty("payments")
    s.markDirty("claims")
    s.touch("customers", id)
}
```

> `updateClient` 是客户侧唯一漏斗 —— 所有子结构的修改都经过它，所以只需要拦一处。

---

## 三、同步服务（`SyncService.swift`）

### 3.1 状态

```swift
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var running = false
    @Published var progressText = ""
    @Published var lastSyncAt: Date?
    @Published var lastSummary: String?
    @Published var errorText: String?

    @Published var shopToken: String?
    @Published var shopName: String = ""
}
```

持久化在 `UserDefaults`：

| 键 | 内容 |
|---|---|
| `sync.shop.token` | 店铺账号 token |
| `sync.shop.name` | 店铺名（显示用） |
| `sync.watermark` | 上次同步时间（增量拉取的 since） |
| `sync.touch` | `"模块\|uid" → 时间戳`，冲突比较用 |
| `sync.imgurl` | `"clientUUID/文件名" → 云端 URL` |
| `sync.dirty` | 待推送的模块名 |

### 3.2 同步流程

```
1. 有删除待通知 → sync/delete
2. 本地照片没上传过 → upload 拿 URL，写进 imageURLs
3. 有模块标脏 → buildPayload() 构造数据 → sync/push
4. sync/pull(since: 上次同步时间)
5. merge() 合并进 Store，逐条比较时间戳
6. 云端有、本地缺的照片 → 下载回 Documents
7. watermark = 服务端返回的 server_time
```

关键点：**先推后拉**。本地改动先送上去，再拉全量，这样拉回来的包含自己刚推的数据，不会出现「推完又被旧数据覆盖」。

### 3.3 冲突处理：较新者胜

每条记录带 `updated_at`。服务端 `sync_push` 里比对：

```php
if ($exist && $serverTs > $clientTs + 1) {
    $skip++;   // 后台改得更晚，拒绝 App 覆盖
    continue;
}
```

App 端 `merge` 时反过来：

```swift
private func isLocalNewer(_ module: String, _ uid: UUID, server row: [String: Any]) -> Bool {
    guard let local = localTouch["\(module)|\(uid.uuidString)"],
          let s = date(row, "updated_at") else { return false }
    return local.timeIntervalSince(s) > 1
}
```

本地更新 → 这轮不覆盖，等下一次推送把它送上去。

### 3.4 结构展平

App 的数据是嵌套的（`Client` 里有 5 个数组），后台是扁平表。`buildPayload` 负责拆：

| 模块 | 来源 |
|---|---|
| `customers` | `store.clients` 顶层字段 |
| `photos` | `store.clients.flatMap { $0.photos }` + `client_uid` |
| `steps` | `store.clients.flatMap { $0.steps }` + `client_uid` |
| `notes` | `store.clients.flatMap { $0.notes }` + `client_uid` |
| `payments` | `store.clients.flatMap { $0.payments }` + `client_uid` |
| `claims` | `store.clients.flatMap { $0.claims }` + `client_uid` |
| `teachers` | `store.teachers` |
| `products` | `store.products`（specs/images/usageSteps 转 JSON 或换行文本） |
| `agents` | `store.agents`（parentID → parent_uid，clientIDs → client_uids） |
| `agent_orders` | `store.agents.flatMap { $0.orders }` + `agent_uid` |
| `appointments` | `store.appointments` |

合并时反向重建嵌套结构：先按 `client_uid` 找到客户下标，再 upsert 进对应数组。

### 3.5 字段换算

| App | 后台 | 换算 |
|---|---|---|
| `Agent.discount: 0.6` | `discount: 65` | `× 100` / `÷ 100` |
| `Teacher.available: true` | `status: '在岗'` | 布尔 ↔ 枚举 |
| `Teacher.tags: ["a","b"]` | `tags: "a,b"` | 数组 ↔ 逗号串 |
| `Product.usageSteps: [String]` | `usage_steps: "a\nb"` | 数组 ↔ 换行串 |
| `Product.specs: [ProductSpec]` | `specs: JSON` | 结构 ↔ JSON |
| `Agent.clientIDs: [UUID]` | `client_uids: JSON` | 数组 ↔ JSON |
| `PhotoItem.phase: .before` | `phase: '使用前'` | 枚举 ↔ 中文 |
| `Product` 无顶层价格 | `price` | 取 `specs.map(\.price).min()` |

### 3.6 图片

图片不塞进 JSON，走独立通道：

**上传**（推送前）：遍历所有照片，本地文件存在但没 URL 的，`POST upload` 拿路径，记进 `imageURLs`。单张超过 11MB 跳过。

**下载**（拉取后）：云端有 `url` + `file_name`，本地文件不存在就下载，存成 `media/<clientID>/<fileName>`。

`imageURLs` 持久化在 UserDefaults，已上传的不会重复传。

---

## 四、云端接口（`CloudAPI.swift`）

新增 5 个方法。同步接口返回的是动态结构，不能用 `Codable`，所以加了一个 `callRaw`：

```swift
private func callRaw(_ route: String, method: String = "GET",
                     query: [String: String] = [:],
                     body: [String: Any]? = nil,
                     token: String? = nil) async throws -> Any
```

| 方法 | 路由 |
|---|---|
| `syncLogin(account:password:)` | `sync/login` |
| `syncPull(since:token:)` | `sync/pull` |
| `syncPush(_:token:)` | `sync/push` |
| `syncDelete(_:token:)` | `sync/delete` |
| `uploadImage(_:fileName:token:)` | `upload`（multipart） |

`uploadImage` 手写了 multipart 表单，因为原来只有后台网页端上传，App 端没有。

---

## 五、界面入口（`ShopSyncView.swift`）

放在「我的」页，`AccountView` 里 `siteCard` 之前插入一个 `ShopSyncCard()`。

**未登录**：

```
店铺数据同步
用网站后台的账号登录，手机和网站就会共用同一份数据。
[ 用店铺账号登录 ]
```

**已登录**：

```
店铺数据同步                          店主
上次同步 11-10 16:42
更新 客户 3、照片 5                    [ 立即同步 ]

 12      4      8      6      2     37
客户   导师   产品   代理   预约   照片

退出店铺账号
```

登录弹窗 `ShopLoginSheet`：账号（邮箱/姓名/手机号）+ 密码 → 「登录并同步」，登录成功后立刻跑一次全量同步。

同步中按钮位置变成 `ProgressView + "上传图片…" / "下载数据…" / "合并数据…"`。

---

## 六、编译与发布

Windows 编不了 iOS，走 GitHub Actions 的 macOS 机器：

```bash
# github.com 直连不通，只能走 API 直传
GH_TOKEN="<token>" python tools/push_api.py --owner eqqln --repo beauty-album
```

版本从 `1.1.0 (build 8)` 升到 `1.2.0 (build 9)`，`project.yml` 四处同步：

```
MARKETING_VERSION: "1.2.0"
CURRENT_PROJECT_VERSION: "9"
CFBundleShortVersionString: "1.2.0"
CFBundleVersion: "9"
```

`push_api.py` 的 `collect_files()` 读的是 `git ls-files`，所以新文件必须先 `git add`。

---

## 七、使用步骤

1. 装新版 IPA（1.2.0）
2. 打开「我的」→ 店铺数据同步 → 用店铺账号登录
   - 账号 `admin@meiyan.local`，密码 `admin888`
3. 登录后自动跑一次同步，卡片显示同步条数与时间
4. 之后在 App 里改任何数据，回到「我的」点「立即同步」即可上传
5. 在后台改任何数据，App 点「立即同步」即可下载

> 目前是手动触发。自动同步（回到前台/定时）留作后续优化，避免弱网时反复失败弹提示。

---

## 八、已知限制

- **同步是手动的**，不是实时。App 改了数据不点「立即同步」不会上传。
- **删除是硬删除**，App 删客户会连带后台删除。删之前建议先在后台「数据备份」留一份。
- **照片双向传输**：首次全量同步时照片多的店会比较慢（每张 200–500KB）。
- **冲突粒度是整行**，不是字段级。同一行两边同时改，后改的整行胜出。
- **未做增量字段同步**：`sync/push` 每次发送整行，不是 diff。
