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

    private var beforePhotos: [PhotoItem] { client.beforePhotos.sorted { $0.createdAt > $1.createdAt } }
    private var afterPhotos: [PhotoItem] { client.afterPhotos.sorted { $0.createdAt > $1.createdAt } }

    private var beforePhoto: PhotoItem? {
        beforePhotos.first { $0.id == beforeID } ?? beforePhotos.first
    }
    private var afterPhoto: PhotoItem? {
        afterPhotos.first { $0.id == afterID } ?? afterPhotos.first
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
        beforeID = beforePhotos.first?.id
        afterID = afterPhotos.first?.id
    }

    // MARK: 模式

    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(CompareMode.allCases) { m in
                let active = m == mode
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { mode = m }
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
            if mode == .slider {
                Text("拖动分割线")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }
        }
    }

    // MARK: 预览

    private var preview: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                if mode == .side {
                    HStack(spacing: 2) {
                        halfView(url(beforePhoto), label: store.settings.beforeLabel,
                                 phase: .before, width: w / 2 - 1, height: h)
                        halfView(url(afterPhoto), label: store.settings.afterLabel,
                                 phase: .after, width: w / 2 - 1, height: h)
                    }
                } else {
                    ZStack {
                        imageFill(url(afterPhoto))
                            .frame(width: w, height: h)
                            .clipped()

                        imageFill(url(beforePhoto))
                            .frame(width: w, height: h)
                            .clipped()
                            .mask(
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: w * slider)
                                    Color.clear
                                }
                            )

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
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                slider = min(1, max(0, v.location.x / w))
                            }
                    )
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .aspectRatio(0.82, contentMode: .fit)
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
