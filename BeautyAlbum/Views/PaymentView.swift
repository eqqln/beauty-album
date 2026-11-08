import SwiftUI
import PhotosUI
import UIKit

struct PaymentView: View {
    let clientID: UUID
    @Binding var client: Client
    @EnvironmentObject var store: Store

    @State private var amountText = ""
    @State private var kind: PaymentQRKind = .wechat
    @State private var showAddRecord = false
    @State private var recordAmount = ""
    @State private var recordMethod = "微信"
    @State private var recordNote = ""
    @State private var showQRFull = false
    @State private var toast: String?
    @State private var showSetQuoted = false
    @State private var quotedDraft = ""
    @State private var qrPickerItem: PhotosPickerItem?
    /// 金额输入框的焦点，用于「确认」时收起数字键盘
    @FocusState private var amountFocused: Bool

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var qrImage: UIImage? {
        if !store.settings.payLink.trimmingCharacters(in: .whitespaces).isEmpty {
            let payload = QRCodeService.paymentPayload(
                shop: store.settings.shopName,
                amount: amount,
                clientName: client.name,
                link: store.settings.payLink
            )
            return QRCodeService.make(payload)
        }
        return store.paymentQRImage(kind: kind)
    }

    var body: some View {
        VStack(spacing: 14) {
            billCard
            amountCard
            qrCard
            recordSection
        }
        .sheet(isPresented: $showAddRecord) {
            addRecordSheet
        }
        .fullScreenCover(isPresented: $showQRFull) {
            qrFullScreen
        }
        .alert("设置应收金额", isPresented: $showSetQuoted) {
            TextField("例如 2980", text: $quotedDraft)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let v = Double(quotedDraft.replacingOccurrences(of: ",", with: "")) ?? 0
                client.quotedPrice = max(0, v)
                store.save()
            }
        } message: {
            Text("填写这位客户的套餐 / 疗程总价，App 会自动算出已付、未付和结清状态。")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: qrPickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        if store.savePaymentQR(image: img, kind: kind) {
                            flash("\(kind.title)已更新")
                        } else {
                            flash(store.lastError ?? "保存失败")
                        }
                    }
                } else {
                    await MainActor.run { flash("图片读取失败") }
                }
                await MainActor.run { qrPickerItem = nil }
            }
        }
        // 数字键盘上没有回车键，补一个「完成」收键盘
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { amountFocused = false }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: 账单

    private var billCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("应收总额")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(client.quotedPrice > 0 ? Fmt.money(client.quotedPrice) : "未设置")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.ink)
                        Button {
                            quotedDraft = client.quotedPrice > 0
                                ? String(format: "%.0f", client.quotedPrice) : ""
                            showSetQuoted = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.roseDeep)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 0) {
                moneyCell(title: "已付", value: client.paidAmount,
                          color: Theme.roseDeep, sub: "\(client.payments.count) 笔")
                Rectangle().fill(Theme.line).frame(width: 0.8, height: 34)
                moneyCell(title: "未付", value: client.unpaidAmount,
                          color: client.unpaidAmount > 0 ? Color(red: 0.80, green: 0.32, blue: 0.26) : Theme.muted,
                          sub: client.unpaidAmount > 0 ? "待收" : "—")
            }

            if client.quotedPrice > 0 {
                VStack(spacing: 5) {
                    ProgressBar(value: client.paymentProgress, height: 7)
                    HStack {
                        Text("已收 \(Int(client.paymentProgress * 100))%")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                        Spacer()
                        if client.overpaidAmount > 0 {
                            Text("多收 \(Fmt.money(client.overpaidAmount))")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if client.unpaidAmount > 0 {
                    Button {
                        amountText = String(format: "%.0f", client.unpaidAmount)
                        recordAmount = String(format: "%.0f", client.unpaidAmount)
                        recordMethod = kind == .wechat ? "微信" : "支付宝"
                        recordNote = "结清尾款"
                        showAddRecord = true
                    } label: {
                        Label("收清尾款 \(Fmt.money(client.unpaidAmount))", systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Theme.gradRose)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if client.paymentStatus == .paid {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                        Text("款项已结清")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Theme.roseDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.roseLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Button {
                        quotedDraft = ""
                        showSetQuoted = true
                    } label: {
                        Label("先设置应收金额", systemImage: "plus.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.roseDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Theme.roseLight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private var statusBadge: some View {
        let s = client.paymentStatus
        let color: Color = {
            switch s {
            case .paid: return Theme.roseDeep
            case .partial: return Color(red: 0.86, green: 0.58, blue: 0.24)
            case .unpaid: return Color(red: 0.80, green: 0.32, blue: 0.26)
            case .none: return Theme.muted
            }
        }()
        return Text(s.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func moneyCell(title: String, value: Double, color: Color, sub: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Theme.muted)
            Text(Fmt.money(value))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 9))
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 金额

    private var amountCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 数字键盘没有回车键，给一个明确的「确认」把键盘收起来
                Button {
                    confirmAmount()
                } label: {
                    Text("确认")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(
                            amount > 0
                            ? AnyView(Theme.gradRose)
                            : AnyView(Theme.muted.opacity(0.45))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach([98.0, 198.0, 298.0, 598.0], id: \.self) { v in
                    Button {
                        amountText = String(format: "%.0f", v)
                    } label: {
                        Text("¥\(Int(v))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.roseDeep)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.roseLight)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text(amount > 0
                     ? "二维码将按 \(Fmt.money(amount)) 生成"
                     : "输入金额后，二维码自动带上金额")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    recordAmount = amount > 0 ? String(format: "%.0f", amount) : ""
                    recordMethod = kind == .wechat ? "微信" : "支付宝"
                    recordNote = ""
                    showAddRecord = true
                } label: {
                    Label("记一笔", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.gradRose)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 二维码

    private var qrCard: some View {
        VStack(spacing: 12) {
            HStack {
                SectionHeader(title: "收款二维码")
                Spacer()
            }

            if store.settings.payLink.trimmingCharacters(in: .whitespaces).isEmpty {
                Picker("收款方式", selection: $kind) {
                    ForEach(PaymentQRKind.allCases) { k in
                        Text(k.title.replacingOccurrences(of: "收款码", with: "")).tag(k)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let img = qrImage {
                Button {
                    showQRFull = true
                } label: {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 230)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                if amount > 0 {
                    Text("客户扫码后支付 \(Fmt.money(amount))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.roseDeep)
                }
                Text(store.settings.payNote)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    PhotosPicker(selection: $qrPickerItem, matching: .images) {
                        Label("更换收款码", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.roseDeep)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Theme.roseLight)
                            .clipShape(Capsule())
                    }

                    Button {
                        showQRFull = true
                    } label: {
                        Label("放大展示", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.inkSoft)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Theme.cream)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.line, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundColor(Theme.muted)
                    Text("还没有上传\(kind.title)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.inkSoft)
                    Text("直接上传微信 / 支付宝收款码截图\n或填写商户收款链接，自动生成带金额的二维码")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)

                    PhotosPicker(selection: $qrPickerItem, matching: .images) {
                        Label("上传收款码", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Theme.gradRose)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 收款记录

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "收款记录", trailing: "\(client.payments.count) 笔 · \(Fmt.money(client.totalPaid))")

            if client.payments.isEmpty {
                Text("记下每笔收款，方便对账和回访")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .padding(.vertical, 6)
            } else {
                ForEach(client.payments.sorted { $0.createdAt > $1.createdAt }) { p in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Theme.roseLight).frame(width: 34, height: 34)
                            Image(systemName: p.method == "现金" ? "banknote" : "qrcode")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.roseDeep)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(p.method)\(p.note.isEmpty ? "" : " · \(p.note)")")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.ink)
                            Text(Fmt.dateTime.string(from: p.createdAt))
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Text(Fmt.money(p.amount))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.roseDeep)
                        Button {
                            client.payments.removeAll { $0.id == p.id }
                            store.save()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.muted)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 0.8))
                }
            }
        }
    }

    // MARK: 添加收款记录

    private var addRecordSheet: some View {
        NavigationStack {
            Form {
                Section("金额") {
                    TextField("0", text: $recordAmount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 20, weight: .semibold))
                }
                Section("方式") {
                    Picker("收款方式", selection: $recordMethod) {
                        ForEach(["微信", "支付宝", "现金", "银行卡", "其他"], id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("备注") {
                    TextField("项目名称、疗程期数等", text: $recordNote)
                }

                if client.quotedPrice > 0 {
                    Section("账单变化") {
                        HStack {
                            Text("当前未付")
                            Spacer()
                            Text(Fmt.money(client.unpaidAmount))
                                .foregroundColor(Theme.inkSoft)
                        }
                        HStack {
                            Text("本次收款")
                            Spacer()
                            Text(Fmt.money(Double(recordAmount) ?? 0))
                                .foregroundColor(Theme.roseDeep)
                        }
                        HStack {
                            Text("收款后剩余")
                            Spacer()
                            let rest = max(0, client.unpaidAmount - (Double(recordAmount) ?? 0))
                            Text(Fmt.money(rest))
                                .fontWeight(.semibold)
                                .foregroundColor(rest > 0
                                                 ? Color(red: 0.80, green: 0.32, blue: 0.26)
                                                 : Theme.roseDeep)
                        }
                    }
                }
            }
            .navigationTitle("记录收款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddRecord = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let v = Double(recordAmount) ?? 0
                        guard v > 0 else { showAddRecord = false; return }
                        client.payments.append(PaymentRecord(amount: v, method: recordMethod, note: recordNote))
                        store.save()
                        showAddRecord = false
                        if client.quotedPrice > 0 && client.unpaidAmount <= 0 {
                            flash("已记录 \(Fmt.money(v))，款项已结清")
                        } else if client.quotedPrice > 0 {
                            flash("已记录 \(Fmt.money(v))，还差 \(Fmt.money(client.unpaidAmount))")
                        } else {
                            flash("已记录 \(Fmt.money(v))")
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: 全屏二维码

    private var qrFullScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                if let img = qrImage {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 300)
                        .padding(18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                VStack(spacing: 6) {
                    Text(store.settings.shopName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    if amount > 0 {
                        Text(Fmt.money(amount))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text(store.settings.payNote)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    showQRFull = false
                } label: {
                    Text("关闭")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func flash(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { toast = nil }
    }

    /// 确认金额：收起键盘并提示
    private func confirmAmount() {
        amountFocused = false
        if amount > 0 {
            flash("已确认 \(Fmt.money(amount))，二维码已同步")
        } else {
            flash("先输入金额")
        }
    }
}
