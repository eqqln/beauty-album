import Foundation
import Combine
import UIKit

/// 店铺数据同步：把 App 本地 JSON 与网站后台的 MySQL 双向对齐。
///
/// 设计取舍：
/// - 主键统一用 UUID。后台每张表都有 uid 列存这个 UUID，所以两边能互相认。
/// - 冲突按「较新者胜」。本地每次改动记一个时间戳，推送时带上；服务端比对后
///   决定是否接受，避免手机旧数据把后台的新修改盖掉。
/// - 图片走独立通道：推送前先上传拿 URL，拉取时按 URL 下载回本地。
/// - 同步不改任何界面逻辑，只在数据层做增量对齐。
final class SyncService: ObservableObject {
    static let shared = SyncService()

    // MARK: 对外状态

    @Published var running = false
    @Published var progressText = ""
    @Published var lastSyncAt: Date?
    @Published var lastSummary: String?
    @Published var errorText: String?

    /// 已登录的店铺账号
    @Published var shopToken: String?
    @Published var shopName: String = ""

    var isLoggedIn: Bool { (shopToken ?? "").isEmpty == false }

    // MARK: 存储键

    private let kToken = "sync.shop.token"
    private let kName  = "sync.shop.name"
    private let kMark  = "sync.watermark"
    private let kTouch = "sync.touch"
    private let kImg   = "sync.imgurl"
    private let kDirty = "sync.dirty"

    /// "模块|uid" → 本地最后改动时间
    private var localTouch: [String: Date] = [:]
    /// "clientUUID/文件名" → 云端 URL
    private var imageURLs: [String: String] = [:]
    /// 有本地改动待推送的模块
    private var dirtyModules: Set<String> = []
    /// 已删除待通知云端的 "模块|uid"
    private var pendingDeletes: [String: Set<String>] = [:]

    private init() {
        shopToken = UserDefaults.standard.string(forKey: kToken)
        shopName = UserDefaults.standard.string(forKey: kName) ?? ""
        if let t = UserDefaults.standard.object(forKey: kMark) as? Double, t > 0 {
            lastSyncAt = Date(timeIntervalSince1970: t)
        }
        if let raw = UserDefaults.standard.dictionary(forKey: kTouch) {
            for (k, v) in raw {
                if let n = v as? NSNumber {
                    localTouch[k] = Date(timeIntervalSince1970: n.doubleValue)
                }
            }
        }
        if let raw = UserDefaults.standard.dictionary(forKey: kImg) {
            for (k, v) in raw {
                if let str = v as? String { imageURLs[k] = str }
            }
        }
        if let raw = UserDefaults.standard.array(forKey: kDirty) as? [String] {
            dirtyModules = Set(raw)
        }
    }

    // MARK: 改动登记（由 Store 调用）

    /// 标记某模块有本地改动，下次同步会推送
    func markDirty(_ module: String) {
        dirtyModules.insert(module)
        UserDefaults.standard.set(Array(dirtyModules), forKey: kDirty)
    }

    /// 记下某条记录的最后改动时间
    func touch(_ module: String, _ uid: UUID, at date: Date = Date()) {
        localTouch["\(module)|\(uid.uuidString)"] = date
        markDirty(module)
        flushTouch()
    }

    func touch(_ module: String, _ uid: String, at date: Date = Date()) {
        localTouch["\(module)|\(uid)"] = date
        markDirty(module)
        flushTouch()
    }

    /// 记录一条待通知云端的删除
    func markDeleted(_ module: String, _ uid: UUID) {
        pendingDeletes[module, default: []].insert(uid.uuidString)
        markDirty(module)
    }

    private func flushTouch() {
        var raw: [String: Double] = [:]
        for (k, v) in localTouch { raw[k] = v.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: kTouch)
    }

    private func flushImages() {
        UserDefaults.standard.set(imageURLs, forKey: kImg)
    }

    private func touchDate(_ module: String, _ uid: UUID, fallback: Date) -> Date {
        localTouch["\(module)|\(uid.uuidString)"] ?? fallback
    }

    // MARK: 账号

    @MainActor
    func login(account: String, password: String) async throws {
        let r = try await CloudAPI.shared.syncLogin(account: account, password: password)
        shopToken = r.token
        shopName = r.name
        UserDefaults.standard.set(r.token, forKey: kToken)
        UserDefaults.standard.set(r.name, forKey: kName)
        errorText = nil
    }

    @MainActor
    func logout() {
        shopToken = nil
        shopName = ""
        UserDefaults.standard.removeObject(forKey: kToken)
        UserDefaults.standard.removeObject(forKey: kName)
        UserDefaults.standard.removeObject(forKey: kMark)
        lastSyncAt = nil
        lastSummary = nil
    }

    // MARK: 主流程

    /// 一次完整同步：推送本地改动 → 拉取云端变更 → 合并进本地
    @MainActor
    func syncNow(store: Store) async {
        guard let token = shopToken, !token.isEmpty else {
            errorText = "请先用店铺账号登录"
            return
        }
        if running { return }

        running = true
        errorText = nil
        defer {
            running = false
            progressText = ""
        }

        do {
            // 1. 删除
            if !pendingDeletes.isEmpty {
                progressText = "同步删除…"
                var payload: [String: Any] = [:]
                for (m, ids) in pendingDeletes { payload[m] = Array(ids) }
                _ = try? await CloudAPI.shared.syncDelete(payload, token: token)
                pendingDeletes.removeAll()
            }

            // 2. 图片先上传
            progressText = "上传图片…"
            try await uploadPendingImages(store: store, token: token)

            // 3. 推送本地改动
            if !dirtyModules.isEmpty {
                progressText = "上传数据…"
                var payload: [String: Any] = [:]
                for m in dirtyModules {
                    let rows = buildPayload(module: m, store: store)
                    if !rows.isEmpty { payload[m] = rows }
                }
                if !payload.isEmpty {
                    _ = try await CloudAPI.shared.syncPush(payload, token: token)
                }
                dirtyModules.removeAll()
                UserDefaults.standard.set([String](), forKey: kDirty)
            }

            // 4. 拉取云端
            progressText = "下载数据…"
            let since = lastSyncAt.map { Self.iso($0) }
            let raw = try await CloudAPI.shared.syncPull(since: since, token: token)
            let data = raw["data"] as? [String: Any] ?? [:]
            let serverTime = (raw["server_time"] as? String).flatMap { Self.parseISO($0) } ?? Date()

            progressText = "合并数据…"
            let changed = merge(data: data, store: store)
            try await downloadMissingImages(store: store, token: token)

            lastSyncAt = serverTime
            UserDefaults.standard.set(serverTime.timeIntervalSince1970, forKey: kMark)

            lastSummary = changed.isEmpty
                ? "已是最新，没有新数据"
                : "更新 " + changed.joined(separator: "、")
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: 构造推送数据

    private func buildPayload(module: String, store: Store) -> [[String: Any]] {
        switch module {
        case "customers":
            return store.clients.map { c in
                [
                    "uid": c.id.uuidString,
                    "name": c.name,
                    "phone": c.phone,
                    "note": c.note,
                    "quoted_price": c.quotedPrice,
                    "stage": c.currentStageTitle,
                    "progress": Int((c.progress * 100).rounded()),
                    "created_at": Self.iso(c.createdAt),
                    "updated_at": Self.iso(touchDate("customers", c.id, fallback: c.createdAt))
                ]
            }

        case "photos":
            var out: [[String: Any]] = []
            for c in store.clients {
                for p in c.photos {
                    let key = "\(c.id.uuidString)/\(p.fileName)"
                    out.append([
                        "uid": p.id.uuidString,
                        "client_uid": c.id.uuidString,
                        "phase": p.phase == .before ? "使用前" : "使用后",
                        "tag": p.tag,
                        "caption": p.caption,
                        "file_name": p.fileName,
                        "url": imageURLs[key] ?? "",
                        "created_at": Self.iso(p.createdAt),
                        "updated_at": Self.iso(touchDate("photos", p.id, fallback: p.createdAt))
                    ])
                }
            }
            return out

        case "steps":
            var out: [[String: Any]] = []
            for c in store.clients {
                for (i, s) in c.steps.enumerated() {
                    var row: [String: Any] = [
                        "uid": s.id.uuidString,
                        "client_uid": c.id.uuidString,
                        "title": s.title,
                        "done": s.done ? 1 : 0,
                        "note": s.note,
                        "sort": i,
                        "updated_at": Self.iso(touchDate("steps", s.id, fallback: c.createdAt))
                    ]
                    if let d = s.doneAt { row["done_at"] = Self.iso(d) }
                    out.append(row)
                }
            }
            return out

        case "notes":
            var out: [[String: Any]] = []
            for c in store.clients {
                for n in c.notes {
                    out.append([
                        "uid": n.id.uuidString,
                        "client_uid": c.id.uuidString,
                        "content": n.content,
                        "created_at": Self.iso(n.createdAt),
                        "updated_at": Self.iso(touchDate("notes", n.id, fallback: n.createdAt))
                    ])
                }
            }
            return out

        case "payments":
            var out: [[String: Any]] = []
            for c in store.clients {
                for p in c.payments {
                    out.append([
                        "uid": p.id.uuidString,
                        "client_uid": c.id.uuidString,
                        "amount": p.amount,
                        "method": p.method,
                        "status": "已收款",
                        "note": p.note,
                        "created_at": Self.iso(p.createdAt),
                        "updated_at": Self.iso(touchDate("payments", p.id, fallback: p.createdAt))
                    ])
                }
            }
            return out

        case "claims":
            var out: [[String: Any]] = []
            for c in store.clients {
                for k in c.claims {
                    var row: [String: Any] = [
                        "uid": k.id.uuidString,
                        "client_uid": c.id.uuidString,
                        "product_uid": k.productID.uuidString,
                        "product_name": k.productName,
                        "spec_name": k.specName,
                        "quantity": k.quantity,
                        "claimed": k.claimed ? 1 : 0,
                        "note": k.note,
                        "created_at": Self.iso(k.createdAt),
                        "updated_at": Self.iso(touchDate("claims", k.id, fallback: k.createdAt))
                    ]
                    if let d = k.claimedAt { row["claimed_at"] = Self.iso(d) }
                    out.append(row)
                }
            }
            return out

        case "teachers":
            return store.teachers.map { t in
                [
                    "uid": t.id.uuidString,
                    "name": t.name,
                    "title": t.title,
                    "phone": t.phone,
                    "intro": t.intro,
                    "tags": t.tags,
                    "available": t.available,
                    "sort_index": t.sortIndex,
                    "photo": store.teacherImageURL(t.id).lastPathComponent,
                    "created_at": Self.iso(t.createdAt),
                    "updated_at": Self.iso(touchDate("teachers", t.id, fallback: t.createdAt))
                ]
            }

        case "products":
            return store.products.map { p in
                [
                    "uid": p.id.uuidString,
                    "name": p.name,
                    "brand": p.brand,
                    "category": p.category,
                    "intro": p.intro,
                    "stage": p.stage,
                    "usage_steps": p.usageSteps,
                    "images": p.imageNames,
                    "price": p.specs.map(\.price).min() ?? 0,
                    "stock": p.totalStock,
                    "specs": p.specs.map { ["name": $0.name, "price": $0.price, "stock": $0.stock] },
                    "created_at": Self.iso(p.createdAt),
                    "updated_at": Self.iso(touchDate("products", p.id, fallback: p.createdAt))
                ]
            }

        case "agents":
            return store.agents.map { a in
                [
                    "uid": a.id.uuidString,
                    "name": a.name,
                    "phone": a.phone,
                    "wechat": a.wechat,
                    "region": a.region,
                    "level": a.level.rawValue,
                    "discount": Int((a.discount * 100).rounded()),
                    "parent_uid": a.parentID?.uuidString ?? "",
                    "client_uids": a.clientIDs.map { $0.uuidString },
                    "note": a.note,
                    "joined_at": Self.iso(a.joinedAt),
                    "created_at": Self.iso(a.joinedAt),
                    "updated_at": Self.iso(touchDate("agents", a.id, fallback: a.joinedAt))
                ]
            }

        case "agent_orders":
            var out: [[String: Any]] = []
            for a in store.agents {
                for o in a.orders {
                    out.append([
                        "uid": o.id.uuidString,
                        "agent_uid": a.id.uuidString,
                        "product_uid": o.productID?.uuidString ?? "",
                        "product_name": o.productName,
                        "spec_name": o.specName,
                        "quantity": o.quantity,
                        "unit_price": o.unitPrice,
                        "paid": o.paid,
                        "note": o.note,
                        "created_at": Self.iso(o.createdAt),
                        "updated_at": Self.iso(touchDate("agent_orders", o.id, fallback: o.createdAt))
                    ])
                }
            }
            return out

        case "appointments":
            return store.appointments.map { a in
                [
                    "uid": a.id.uuidString,
                    "teacher_uid": a.teacherID.uuidString,
                    "teacher_name": a.teacherName,
                    "client_uid": a.clientID?.uuidString ?? "",
                    "client_name": a.clientName,
                    "phone": a.phone,
                    "service": a.service,
                    "date": Self.iso(a.date),
                    "duration": a.durationMinutes,
                    "status": a.status.rawValue,
                    "note": a.note,
                    "created_at": Self.iso(a.createdAt),
                    "updated_at": Self.iso(touchDate("appointments", a.id, fallback: a.createdAt))
                ]
            }

        default:
            return []
        }
    }

    // MARK: 合并云端数据

    @discardableResult
    private func merge(data: [String: Any], store: Store) -> [String] {
        var changed: [String] = []

        // 客户
        if let rows = data["customers"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")) else { continue }
                if let idx = store.clients.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("customers", uid, server: r) { continue }
                    store.clients[idx].name = str(r, "name")
                    store.clients[idx].phone = str(r, "phone")
                    store.clients[idx].note = str(r, "note")
                    store.clients[idx].quotedPrice = dbl(r, "quoted_price")
                    stamp("customers", uid, r)
                } else {
                    var c = Client()
                    c.id = uid
                    c.name = str(r, "name")
                    c.phone = str(r, "phone")
                    c.note = str(r, "note")
                    c.quotedPrice = dbl(r, "quoted_price")
                    c.createdAt = date(r, "created_at") ?? Date()
                    store.clients.append(c)
                    stamp("customers", uid, r)
                }
                n += 1
            }
            if n > 0 { changed.append("客户 \(n)") }
        }

        // 照片
        if let rows = data["photos"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")),
                      let cuid = UUID(uuidString: str(r, "client_uid")),
                      let ci = store.clients.firstIndex(where: { $0.id == cuid }) else { continue }
                let phase: PhotoPhase = str(r, "phase").contains("后") ? .after : .before
                let url = str(r, "url")
                let fname = str(r, "file_name")

                if let pi = store.clients[ci].photos.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("photos", uid, server: r) { continue }
                    store.clients[ci].photos[pi].tag = str(r, "tag")
                    store.clients[ci].photos[pi].caption = str(r, "caption")
                    store.clients[ci].photos[pi].phase = phase
                } else {
                    var p = PhotoItem()
                    p.id = uid
                    p.fileName = fname.isEmpty ? "\(uid.uuidString).jpg" : fname
                    p.phase = phase
                    p.tag = str(r, "tag")
                    p.caption = str(r, "caption")
                    p.createdAt = date(r, "created_at") ?? Date()
                    store.clients[ci].photos.append(p)
                }
                if !url.isEmpty, !fname.isEmpty {
                    imageURLs["\(cuid.uuidString)/\(fname)"] = url
                }
                stamp("photos", uid, r)
                n += 1
            }
            if n > 0 { changed.append("照片 \(n)") }
            flushImages()
        }

        // 步骤
        if let rows = data["steps"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")),
                      let cuid = UUID(uuidString: str(r, "client_uid")),
                      let ci = store.clients.firstIndex(where: { $0.id == cuid }) else { continue }
                if let si = store.clients[ci].steps.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("steps", uid, server: r) { continue }
                    store.clients[ci].steps[si].title = str(r, "title")
                    store.clients[ci].steps[si].done = int(r, "done") == 1
                    store.clients[ci].steps[si].note = str(r, "note")
                    store.clients[ci].steps[si].doneAt = date(r, "done_at")
                } else {
                    var s = StepItem()
                    s.id = uid
                    s.title = str(r, "title")
                    s.done = int(r, "done") == 1
                    s.note = str(r, "note")
                    s.doneAt = date(r, "done_at")
                    store.clients[ci].steps.append(s)
                }
                stamp("steps", uid, r)
                n += 1
            }
            if n > 0 { changed.append("步骤 \(n)") }
        }

        // 笔记
        if let rows = data["notes"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")),
                      let cuid = UUID(uuidString: str(r, "client_uid")),
                      let ci = store.clients.firstIndex(where: { $0.id == cuid }) else { continue }
                if let ni = store.clients[ci].notes.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("notes", uid, server: r) { continue }
                    store.clients[ci].notes[ni].content = str(r, "content")
                } else {
                    var note = TextNote()
                    note.id = uid
                    note.content = str(r, "content")
                    note.createdAt = date(r, "created_at") ?? Date()
                    store.clients[ci].notes.append(note)
                }
                stamp("notes", uid, r)
                n += 1
            }
            if n > 0 { changed.append("笔记 \(n)") }
        }

        // 收款
        if let rows = data["payments"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")),
                      let cuid = UUID(uuidString: str(r, "client_uid")),
                      let ci = store.clients.firstIndex(where: { $0.id == cuid }) else { continue }
                if let pi = store.clients[ci].payments.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("payments", uid, server: r) { continue }
                    store.clients[ci].payments[pi].amount = dbl(r, "amount")
                    store.clients[ci].payments[pi].method = str(r, "method")
                    store.clients[ci].payments[pi].note = str(r, "note")
                } else {
                    var p = PaymentRecord()
                    p.id = uid
                    p.amount = dbl(r, "amount")
                    p.method = str(r, "method").isEmpty ? "微信" : str(r, "method")
                    p.note = str(r, "note")
                    p.createdAt = date(r, "created_at") ?? Date()
                    store.clients[ci].payments.append(p)
                }
                stamp("payments", uid, r)
                n += 1
            }
            if n > 0 { changed.append("收款 \(n)") }
        }

        // 产品领用
        if let rows = data["claims"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")),
                      let cuid = UUID(uuidString: str(r, "client_uid")),
                      let ci = store.clients.firstIndex(where: { $0.id == cuid }) else { continue }
                if let ki = store.clients[ci].claims.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("claims", uid, server: r) { continue }
                    store.clients[ci].claims[ki].quantity = int(r, "quantity")
                    store.clients[ci].claims[ki].claimed = int(r, "claimed") == 1
                    store.clients[ci].claims[ki].note = str(r, "note")
                } else {
                    var k = ProductClaim()
                    k.id = uid
                    k.productID = UUID(uuidString: str(r, "product_uid")) ?? UUID()
                    k.productName = str(r, "product_name")
                    k.specName = str(r, "spec_name")
                    k.quantity = max(1, int(r, "quantity"))
                    k.claimed = int(r, "claimed") == 1
                    k.claimedAt = date(r, "claimed_at")
                    k.note = str(r, "note")
                    k.createdAt = date(r, "created_at") ?? Date()
                    store.clients[ci].claims.append(k)
                }
                stamp("claims", uid, r)
                n += 1
            }
            if n > 0 { changed.append("领用 \(n)") }
        }

        // 导师
        if let rows = data["teachers"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")) else { continue }
                let tags = (r["tags"] as? [String]) ?? []
                if let ti = store.teachers.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("teachers", uid, server: r) { continue }
                    store.teachers[ti].name = str(r, "name")
                    store.teachers[ti].title = str(r, "title")
                    store.teachers[ti].phone = str(r, "phone")
                    store.teachers[ti].intro = str(r, "intro")
                    store.teachers[ti].tags = tags
                    store.teachers[ti].available = bool(r, "available")
                    store.teachers[ti].sortIndex = int(r, "sort_index")
                } else {
                    var t = Teacher()
                    t.id = uid
                    t.name = str(r, "name")
                    t.title = str(r, "title")
                    t.phone = str(r, "phone")
                    t.intro = str(r, "intro")
                    t.tags = tags
                    t.available = bool(r, "available")
                    t.sortIndex = int(r, "sort_index")
                    t.createdAt = date(r, "created_at") ?? Date()
                    store.teachers.append(t)
                }
                stamp("teachers", uid, r)
                n += 1
            }
            if n > 0 { changed.append("导师 \(n)") }
        }

        // 产品
        if let rows = data["products"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")) else { continue }
                let usage = (r["usage_steps"] as? [String]) ?? []
                let imgs = (r["images"] as? [String]) ?? []
                var specs: [ProductSpec] = []
                if let rawSpecs = r["specs"] as? [[String: Any]] {
                    for s in rawSpecs {
                        var sp = ProductSpec()
                        sp.name = str(s, "name")
                        sp.price = dbl(s, "price")
                        sp.stock = int(s, "stock")
                        specs.append(sp)
                    }
                }
                if let pi = store.products.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("products", uid, server: r) { continue }
                    store.products[pi].name = str(r, "name")
                    store.products[pi].brand = str(r, "brand")
                    store.products[pi].category = str(r, "category")
                    store.products[pi].intro = str(r, "intro")
                    store.products[pi].stage = str(r, "stage")
                    store.products[pi].usageSteps = usage
                    store.products[pi].imageNames = imgs
                    if !specs.isEmpty { store.products[pi].specs = specs }
                } else {
                    var p = Product()
                    p.id = uid
                    p.name = str(r, "name")
                    p.brand = str(r, "brand")
                    p.category = str(r, "category")
                    p.intro = str(r, "intro")
                    p.stage = str(r, "stage")
                    p.usageSteps = usage
                    p.imageNames = imgs
                    p.specs = specs
                    p.createdAt = date(r, "created_at") ?? Date()
                    store.products.append(p)
                }
                stamp("products", uid, r)
                n += 1
            }
            if n > 0 { changed.append("产品 \(n)") }
        }

        // 代理
        if let rows = data["agents"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")) else { continue }
                let level = AgentLevel(rawValue: str(r, "level")) ?? .first
                let discount = Double(int(r, "discount")) / 100.0
                let parent = UUID(uuidString: str(r, "parent_uid"))
                let clients = ((r["client_uids"] as? [String]) ?? []).compactMap { UUID(uuidString: $0) }

                if let ai = store.agents.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("agents", uid, server: r) { continue }
                    store.agents[ai].name = str(r, "name")
                    store.agents[ai].phone = str(r, "phone")
                    store.agents[ai].wechat = str(r, "wechat")
                    store.agents[ai].region = str(r, "region")
                    store.agents[ai].level = level
                    if discount > 0 { store.agents[ai].discount = discount }
                    store.agents[ai].parentID = parent
                    store.agents[ai].clientIDs = clients
                    store.agents[ai].note = str(r, "note")
                } else {
                    var a = Agent()
                    a.id = uid
                    a.name = str(r, "name")
                    a.phone = str(r, "phone")
                    a.wechat = str(r, "wechat")
                    a.region = str(r, "region")
                    a.level = level
                    a.discount = discount > 0 ? discount : level.defaultDiscount
                    a.parentID = parent
                    a.clientIDs = clients
                    a.note = str(r, "note")
                    a.joinedAt = date(r, "joined_at") ?? Date()
                    store.agents.append(a)
                }
                stamp("agents", uid, r)
                n += 1
            }
            if n > 0 { changed.append("代理 \(n)") }
        }

        // 拿货
        if let rows = data["agent_orders"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")),
                      let auid = UUID(uuidString: str(r, "agent_uid")),
                      let ai = store.agents.firstIndex(where: { $0.id == auid }) else { continue }
                if let oi = store.agents[ai].orders.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("agent_orders", uid, server: r) { continue }
                    store.agents[ai].orders[oi].quantity = int(r, "quantity")
                    store.agents[ai].orders[oi].unitPrice = dbl(r, "unit_price")
                    store.agents[ai].orders[oi].paid = dbl(r, "paid")
                    store.agents[ai].orders[oi].note = str(r, "note")
                } else {
                    var o = AgentOrder()
                    o.id = uid
                    o.productID = UUID(uuidString: str(r, "product_uid"))
                    o.productName = str(r, "product_name")
                    o.specName = str(r, "spec_name")
                    o.quantity = max(1, int(r, "quantity"))
                    o.unitPrice = dbl(r, "unit_price")
                    o.paid = dbl(r, "paid")
                    o.note = str(r, "note")
                    o.createdAt = date(r, "created_at") ?? Date()
                    store.agents[ai].orders.append(o)
                }
                stamp("agent_orders", uid, r)
                n += 1
            }
            if n > 0 { changed.append("拿货 \(n)") }
        }

        // 预约
        if let rows = data["appointments"] as? [[String: Any]], !rows.isEmpty {
            var n = 0
            for r in rows {
                guard let uid = UUID(uuidString: str(r, "uid")) else { continue }
                let status = AppointmentStatus(rawValue: str(r, "status")) ?? .pending
                if let ai = store.appointments.firstIndex(where: { $0.id == uid }) {
                    if isLocalNewer("appointments", uid, server: r) { continue }
                    store.appointments[ai].teacherName = str(r, "teacher_name")
                    store.appointments[ai].clientName = str(r, "client_name")
                    store.appointments[ai].phone = str(r, "phone")
                    store.appointments[ai].service = str(r, "service")
                    store.appointments[ai].date = date(r, "date") ?? store.appointments[ai].date
                    store.appointments[ai].durationMinutes = int(r, "duration")
                    store.appointments[ai].status = status
                    store.appointments[ai].note = str(r, "note")
                } else {
                    var a = Appointment()
                    a.id = uid
                    a.teacherID = UUID(uuidString: str(r, "teacher_uid")) ?? UUID()
                    a.teacherName = str(r, "teacher_name")
                    a.clientID = UUID(uuidString: str(r, "client_uid"))
                    a.clientName = str(r, "client_name")
                    a.phone = str(r, "phone")
                    a.service = str(r, "service")
                    a.date = date(r, "date") ?? Date()
                    a.durationMinutes = max(15, int(r, "duration"))
                    a.status = status
                    a.note = str(r, "note")
                    a.createdAt = date(r, "created_at") ?? Date()
                    store.appointments.append(a)
                }
                stamp("appointments", uid, r)
                n += 1
            }
            if n > 0 { changed.append("预约 \(n)") }
        }

        if !changed.isEmpty {
            store.clients = store.clients
            store.teachers = store.teachers
            store.products = store.products
            store.agents = store.agents
            store.appointments = store.appointments
        }
        return changed
    }

    /// 记下服务端这条的时间，作为下次冲突比较的基准
    private func stamp(_ module: String, _ uid: UUID, _ row: [String: Any]) {
        if let d = date(row, "updated_at") {
            localTouch["\(module)|\(uid.uuidString)"] = d
        }
    }

    /// 本地这条比服务端新 → 本轮先不覆盖，等推送把它送上去
    private func isLocalNewer(_ module: String, _ uid: UUID, server row: [String: Any]) -> Bool {
        guard let local = localTouch["\(module)|\(uid.uuidString)"],
              let s = date(row, "updated_at") else { return false }
        return local.timeIntervalSince(s) > 1
    }

    // MARK: 图片

    /// 把本地还没上传过的照片传上去
    private func uploadPendingImages(store: Store, token: String) async throws {
        for c in store.clients {
            for p in c.photos {
                let key = "\(c.id.uuidString)/\(p.fileName)"
                if let u = imageURLs[key], !u.isEmpty { continue }
                let url = store.photoURL(clientID: c.id, fileName: p.fileName)
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                if data.count > 11 * 1024 * 1024 { continue }
                if let path = try? await CloudAPI.shared.uploadImage(data, fileName: p.fileName, token: token) {
                    imageURLs[key] = path
                }
            }
        }
        flushImages()
    }

    /// 云端有、本地缺的照片下载回来
    private func downloadMissingImages(store: Store, token: String) async throws {
        for c in store.clients {
            for p in c.photos where !p.fileName.isEmpty {
                let key = "\(c.id.uuidString)/\(p.fileName)"
                let local = store.photoURL(clientID: c.id, fileName: p.fileName)
                if FileManager.default.fileExists(atPath: local.path) { continue }
                guard let path = imageURLs[key], !path.isEmpty else { continue }
                let full = path.hasPrefix("http") ? path : (CloudAPI.shared.baseURL + path)
                guard let u = URL(string: full) else { continue }
                guard let (data, _) = try? await URLSession.shared.data(from: u) else { continue }
                let dir = store.clientDirectory(c.id)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: local)
            }
        }
    }

    // MARK: 工具

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f.string(from: d)
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return df.date(from: s)
    }

    private func str(_ d: [String: Any], _ k: String) -> String {
        if let s = d[k] as? String { return s }
        if let n = d[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private func int(_ d: [String: Any], _ k: String) -> Int {
        if let n = d[k] as? NSNumber { return n.intValue }
        if let s = d[k] as? String { return Int(s) ?? 0 }
        return 0
    }

    private func dbl(_ d: [String: Any], _ k: String) -> Double {
        if let n = d[k] as? NSNumber { return n.doubleValue }
        if let s = d[k] as? String { return Double(s) ?? 0 }
        return 0
    }

    private func bool(_ d: [String: Any], _ k: String) -> Bool {
        if let b = d[k] as? Bool { return b }
        if let n = d[k] as? NSNumber { return n.boolValue }
        return false
    }

    private func date(_ d: [String: Any], _ k: String) -> Date? {
        guard let s = d[k] as? String, !s.isEmpty else { return nil }
        return Self.parseISO(s)
    }
}
