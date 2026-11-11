import SwiftUI
import UIKit

enum CompareMode: String, CaseIterable, Identifiable {
    case side = "并排"
    case slider = "滑块"

    var id: String { rawValue }
}

struct CompareView: View {
    let clientID: UUID
    @Binding var client: Client
    @EnvironmentObject var store: Store

    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var mode: CompareMode = .side
    @State private var slider: CGFloat = 0.5
    @State private var toast: String?
    @State private var didInit = false
    @State private var fullScreen = false

    // 左右翻页
    @State private var pageIndex: Int = 0
    @State private var dragX: CGFloat = 0
    @State private var isDragging = false
    @State private var dragOnHandle = false

    private var beforePhotos: [PhotoItem] { client.beforePhotos.sorted { $0.createdAt > $1.createdAt } }
    private var afterPhotos: [PhotoItem] { client.afterPhotos.sorted { $0.createdAt > $1.createdAt } }

    /// 一组对比 = 一张使用前 + 一张使用后（都按时间倒序，按下标一一配对）
    private var pairCount: Int {
        guard !beforePhotos.isEmpty, !afterPhotos.isEmpty else { return 0 }
        return max(beforePhotos.count, afterPhotos.count)
    }

    /// 防止照片被删后下标越界
    private var safeIndex: Int {
        guard pairCount > 0 else { return 0 }
        return min(max(0, pageIndex), pairCount - 1)
    }

    private func pairBefore(_ i: Int) -> PhotoItem? {
        guard !beforePhotos.isEmpty else { return nil }
        return beforePhotos[min(max(0, i), beforePhotos.count - 1)]
    }

    private func pairAfter(_ i: Int) -> PhotoItem? {
        guard !afterPhotos.isEmpty else { return nil }
        return afterPhotos[min(max(0, i), afterPhotos.count - 1)]
    }

    private var beforePhoto: PhotoItem? {
        beforePhotos.first { $0.id == beforeID } ?? pairBefore(safeIndex)
    }
    private var afterPhoto: PhotoItem? {
        afterPhotos.first { $0.id == afterID } ?? pairAfter(safeIndex)
    }

    private func url(_ p: PhotoItem?) -> URL? {
        guard let p else { return nil }
        return store.photoURL(clientID: clientID, fileName: p.fileName)
    }

    var body: some View {
        VStack(spacing: 14) {
            if beforePhotos.isEmpty || afterPhotos.isEmpty {
                EmptyHint(
                    icon: "rectangle.split.2x1",
                    title: "需要各一张照片才能对比",
                    subtitle: "当前 \(store.settings.beforeLabel) \(beforePhotos.count) 张 · \(store.settings.afterLabel) \(afterPhotos.count) 张\n请先在「相册」中补充照片"
                )
            } else {
                modeBar
                preview
                picker(title: store.settings.beforeLabel, photos: beforePhotos, selection: $beforeID, phase: .before)
                picker(title: store.settings.afterLabel, photos: afterPhotos, selection: $afterID, phase: .after)
                exportRow
            }
        }
        .onAppear(perform: initSelection)
        .fullScreenCover(isPresented: $fullScreen) {
            CompareFullscreen(before: url(beforePhoto),
                              after: url(afterPhoto),
                              beforeLabel: store.settings.beforeLabelSafe,
                              afterLabel: store.settings.afterLabelSafe,
                              mode: mode)
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
                    .padding(.bottom, 12)
            }
        }
    }

    private func initSelection() {
        guard !didInit else { return }
        didInit = true
        pageIndex = 0
        beforeID = beforePhotos.first?.id
        afterID = afterPhotos.first?.id
    }

    // MARK: 翻页

    /// 切到第 i 组（同时更新两个选择器的选中项，保证缩略图高亮跟得上）
    private func applyPage(_ i: Int) {
        guard pairCount > 0 else { return }
        let idx = min(max(0, i), pairCount - 1)
        pageIndex = idx
        beforeID = pairBefore(idx)?.id
        afterID = pairAfter(idx)?.id
    }

    private func step(_ delta: Int) {
        let target = safeIndex + delta
        guard target >= 0, target < pairCount else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            applyPage(target)
            dragX = 0
        }
    }

    // MARK: 模式

    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(CompareMode.allCases) { m in
                let active = m == mode
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        mode = m
                        dragX = 0
                    }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                        .foregroundColor(active ? .white : Theme.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(active ? AnyView(Theme.gradRose) : AnyView(Theme.card))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(active ? Color.clear : Theme.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text(mode == .slider ? "拖圆点对比 · 点图放大" : "滑动换图 · 点图放大")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
        }
    }

    // MARK: 预览

    private var preview: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 左 / 中 / 右三页，拖动时相邻一组会跟着进来
                pageView(-1, w: w, h: h).offset(x: -w + dragX)
                pageView(0, w: w, h: h).offset(x: dragX)
                pageView(1, w: w, h: h).offset(x: w + dragX)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .gesture(panGesture(w: w))
            .overlay(alignment: .bottom) { pageBadge }
        }
        .aspectRatio(0.82, contentMode: .fit)
    }

    /// 单页：offset = -1 上一组 / 0 当前 / 1 下一组
    @ViewBuilder
    private func pageView(_ offset: Int, w: CGFloat, h: CGFloat) -> some View {
        let idx = safeIndex + offset
        let inRange = idx >= 0 && idx < pairCount
        let b = inRange ? (offset == 0 ? beforePhoto : pairBefore(idx)) : nil
        let a = inRange ? (offset == 0 ? afterPhoto : pairAfter(idx)) : nil

        if inRange, let b, let a {
            if mode == .side {
                HStack(spacing: 2) {
                    halfView(url(b), label: store.settings.beforeLabel,
                             phase: .before, width: w / 2 - 1, height: h)
                    halfView(url(a), label: store.settings.afterLabel,
                             phase: .after, width: w / 2 - 1, height: h)
                }
                .frame(width: w, height: h)
            } else {
                sliderPage(url(b), url(a), w: w, h: h)
            }
        } else {
            Color.black.frame(width: w, height: h)
        }
    }

    /// 滑块页：使用前盖在使用后上面，用 mask 按 slider 位置裁开
    private func sliderPage(_ before: URL?, _ after: URL?, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            imageFill(after)
                .frame(width: w, height: h)
                .clipped()

            imageFill(before)
                .frame(width: w, height: h)
                .clipped()
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(0, w * slider))
                }

            // 分割线 + 手柄
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.roseDeep)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 5)
            }
            .position(x: w * slider, y: h / 2)

            VStack {
                HStack {
                    tag(store.settings.beforeLabel, .before)
                    Spacer()
                    tag(store.settings.afterLabel, .after)
                }
                .padding(10)
                Spacer()
            }
        }
        .frame(width: w, height: h)
    }

    /// 手势：拖圆点 = 调对比；其余横向拖动 = 翻页
    private func panGesture(w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !isDragging {
                    isDragging = true
                    // 只有从手柄附近按下才算「调对比」，避免和翻页抢手势
                    dragOnHandle = mode == .slider && abs(v.startLocation.x - w * slider) < 44
                }
                if dragOnHandle {
                    slider = min(1, max(0, v.location.x / w))
                } else {
                    var x = v.translation.width
                    // 到头了给点阻尼，手感上知道没得翻了
                    if (safeIndex == 0 && x > 0) || (safeIndex == pairCount - 1 && x < 0) {
                        x *= 0.28
                    }
                    dragX = x
                }
            }
            .onEnded { v in
                let wasHandle = dragOnHandle
                isDragging = false
                dragOnHandle = false
                if wasHandle { return }

                /* 基本没位移 = 用户是在「点」图，不是翻页：打开大图。
                   DragGesture 的 minimumDistance 是 0，会吃掉普通点击，
                   所以只能在这里判断，不能再叠一个 onTapGesture 抢手势。 */
                if abs(v.translation.width) < 8 && abs(v.translation.height) < 8 {
                    withAnimation(.easeOut(duration: 0.12)) { dragX = 0 }
                    fullScreen = true
                    return
                }

                let dx = v.translation.width
                let projected = v.predictedEndTranslation.width
                var target = safeIndex
                if projected < -50 || dx < -w * 0.22 {
                    target = safeIndex + 1
                } else if projected > 50 || dx > w * 0.22 {
                    target = safeIndex - 1
                }
                target = min(max(0, target), max(0, pairCount - 1))

                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if target != safeIndex { applyPage(target) }
                    dragX = 0
                }
            }
    }

    /// 底部页码条：‹ 3 / 12 ›
    @ViewBuilder
    private var pageBadge: some View {
        if pairCount > 1 {
            HStack(spacing: 10) {
                Button {
                    step(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(safeIndex > 0 ? 1 : 0.3))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(safeIndex == 0)

                Text("\(safeIndex + 1) / \(pairCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()

                Button {
                    step(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(safeIndex < pairCount - 1 ? 1 : 0.3))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(safeIndex == pairCount - 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            .padding(.bottom, 10)
        }
    }

    private func halfView(_ u: URL?, label: String, phase: PhotoPhase,
                          width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            LocalImage(url: u, contentMode: .fit)
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(phase == .before ? Color.black.opacity(0.55) : Theme.rose.opacity(0.9))
                .clipShape(Capsule())
                .padding(8)
        }
    }

    private func imageFill(_ u: URL?) -> some View {
        ZStack {
            Color.black
            LocalImage(url: u, contentMode: .fit)
        }
    }

    private func tag(_ text: String, _ phase: PhotoPhase) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(phase == .before ? Color.black.opacity(0.55) : Theme.rose.opacity(0.9))
            .clipShape(Capsule())
    }

    // MARK: 选择器

    private func picker(title: String, photos: [PhotoItem],
                        selection: Binding<UUID?>, phase: PhotoPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("选择\(title)照片")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.inkSoft)
                Spacer()
                Text("\(photos.count) 张")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { p in
                        let active = (selection.wrappedValue ?? photos.first?.id) == p.id
                        Button {
                            selection.wrappedValue = p.id
                        } label: {
                            LocalImage(url: store.photoURL(clientID: clientID, fileName: p.fileName))
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(active ? Theme.roseDeep : Theme.line,
                                                lineWidth: active ? 2 : 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 导出

    private var exportRow: some View {
        VStack(spacing: 8) {
            Button {
                exportComposite()
            } label: {
                Label("生成对比图并存入系统相册", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("对比图会带上客户姓名、店名和「\(store.settings.beforeLabel) / \(store.settings.afterLabel)」标注，可直接发给客户。")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exportComposite() {
        guard let b = beforePhoto, let a = afterPhoto,
              let bi = UIImage(contentsOfFile: store.photoURL(clientID: clientID, fileName: b.fileName).path),
              let ai = UIImage(contentsOfFile: store.photoURL(clientID: clientID, fileName: a.fileName).path)
        else {
            toast = "照片读取失败"
            clearToast()
            return
        }

        let cell = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cell.width * 2, height: cell.height + 90),
                                               format: format)
        let output = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: cell.width * 2, height: cell.height + 90))

            drawAspectFit(bi, in: CGRect(x: 0, y: 90, width: cell.width, height: cell.height))
            drawAspectFit(ai, in: CGRect(x: cell.width, y: 90, width: cell.width, height: cell.height))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: UIColor(Theme.roseDeep)
            ]
            let attrs2: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            let name = (client.name.isEmpty ? "客户" : client.name) as NSString
            name.draw(at: CGPoint(x: 30, y: 26), withAttributes: attrs)
            let shop = store.settings.shopName as NSString
            let size = shop.size(withAttributes: attrs2)
            shop.draw(at: CGPoint(x: cell.width * 2 - size.width - 30, y: 30), withAttributes: attrs2)

            (store.settings.beforeLabel as NSString).draw(
                at: CGPoint(x: 30, y: cell.height + 110 - 60), withAttributes: attrs2)
            (store.settings.afterLabel as NSString).draw(
                at: CGPoint(x: cell.width + 30, y: cell.height + 110 - 60), withAttributes: attrs2)
        }

        UIImageWriteToSavedPhotosAlbum(output, nil, nil, nil)
        toast = "已保存到系统相册"
        clearToast()
    }

    private func drawAspectFit(_ image: UIImage, in rect: CGRect) {
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        image.draw(in: CGRect(origin: origin, size: size))
    }

    private func clearToast() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { toast = nil }
    }
}

// MARK: - 全屏对比（点图放大）

/// 点一下预览图就进这里：大图看细节，双指放大、双击还原，可切并排 / 滑块。
struct CompareFullscreen: View {
    let before: URL?
    let after: URL?
    let beforeLabel: String
    let afterLabel: String

    @Environment(\.dismiss) private var dismiss
    @State private var mode: CompareMode
    @State private var slider: CGFloat = 0.5
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(before: URL?, after: URL?, beforeLabel: String, afterLabel: String, mode: CompareMode) {
        self.before = before
        self.after = after
        self.beforeLabel = beforeLabel
        self.afterLabel = afterLabel
        _mode = State(initialValue: mode)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                stage(w: geo.size.width, h: geo.size.height)
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(magnification)
                    .simultaneousGesture(pan)
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer(minLength: 0)
                bottomHint
            }
        }
        .statusBarHidden(true)
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(CompareMode.allCases) { m in
                    let active = m == mode
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            mode = m
                            resetZoom()
                        }
                    } label: {
                        Text(m.rawValue)
                            .font(.system(size: 12, weight: active ? .semibold : .regular))
                            .foregroundColor(active ? Theme.roseDeep : .white.opacity(0.8))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(active ? Color.white : Color.white.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Button {
                toggleZoom()
            } label: {
                Image(systemName: zoom > 1 ? "minus.magnifyingglass" : "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomHint: some View {
        Text(mode == .slider ? "拖动中间圆点对比 · 双指放大 · 双击还原"
                             : "双指放大 · 双击还原 · 放大后可拖动")
            .font(.system(size: 11.5))
            .foregroundColor(.white.opacity(0.55))
            .padding(.bottom, 18)
    }

    // MARK: 画面

    @ViewBuilder
    private func stage(w: CGFloat, h: CGFloat) -> some View {
        if mode == .side {
            HStack(spacing: 2) {
                cell(before, label: beforeLabel, isAfter: false, w: w / 2 - 1, h: h)
                cell(after, label: afterLabel, isAfter: true, w: w / 2 - 1, h: h)
            }
            .frame(width: w, height: h)
        } else {
            ZStack {
                fullImage(after, w: w, h: h)

                fullImage(before, w: w, h: h)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, w * slider))
                    }

                ZStack {
                    Rectangle().fill(Color.white).frame(width: 2)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.roseDeep)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 6)
                }
                .position(x: w * slider, y: h / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            slider = min(1, max(0, v.location.x / w))
                        }
                )

                VStack {
                    HStack {
                        tag(beforeLabel, isAfter: false)
                        Spacer()
                        tag(afterLabel, isAfter: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 56)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            .frame(width: w, height: h)
        }
    }

    private func cell(_ url: URL?, label: String, isAfter: Bool, w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            fullImage(url, w: w, h: h)
            tag(label, isAfter: isAfter)
                .padding(12)
                .padding(.top, 44)
        }
        .frame(width: w, height: h)
        .clipped()
    }

    private func fullImage(_ url: URL?, w: CGFloat, h: CGFloat) -> some View {
        Group {
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
            } else {
                ZStack {
                    Color.white.opacity(0.05)
                    Text("图片不在本地")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(width: w, height: h)
            }
        }
    }

    private func tag(_ text: String, isAfter: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isAfter ? Theme.roseDeep.opacity(0.9) : Color.black.opacity(0.55))
            .clipShape(Capsule())
    }

    // MARK: 手势

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                zoom = min(4, max(1, lastZoom * v))
            }
            .onEnded { _ in
                lastZoom = zoom
                if zoom <= 1.01 { resetZoom() }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { v in
                guard zoom > 1, mode == .side else { return }
                offset = CGSize(width: lastOffset.width + v.translation.width,
                                height: lastOffset.height + v.translation.height)
            }
            .onEnded { _ in
                guard zoom > 1 else { return }
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if zoom > 1 {
                zoom = 1
                lastZoom = 1
                offset = .zero
                lastOffset = .zero
            } else {
                zoom = 2.5
                lastZoom = 2.5
            }
        }
    }

    private func resetZoom() {
        zoom = 1
        lastZoom = 1
        offset = .zero
        lastOffset = .zero
    }
}
