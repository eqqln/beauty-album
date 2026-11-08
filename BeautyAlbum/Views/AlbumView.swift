import SwiftUI
import PhotosUI
import UIKit

enum PhaseFilter: String, CaseIterable, Identifiable {
    case all
    case before
    case after

    var id: String { rawValue }

    func title(_ s: AppSettings) -> String {
        switch self {
        case .all: return "全部"
        case .before: return s.beforeLabel
        case .after: return s.afterLabel
        }
    }
}

struct AlbumView: View {
    let clientID: UUID
    @Binding var client: Client
    @EnvironmentObject var store: Store

    @State private var filter: PhaseFilter = .all
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var importing = false
    @State private var viewingID: UUID?
    @State private var toast: String?

    private var photos: [PhotoItem] {
        switch filter {
        case .all: return client.photos.sorted { $0.createdAt > $1.createdAt }
        case .before: return client.beforePhotos.sorted { $0.createdAt > $1.createdAt }
        case .after: return client.afterPhotos.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// 新导入照片默认归入的阶段
    private var targetPhase: PhotoPhase {
        switch filter {
        case .after: return .after
        case .before, .all: return .before
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.gridSpacing), count: 3)
    }

    var body: some View {
        VStack(spacing: 12) {
            filterBar
            hintBar

            if photos.isEmpty {
                EmptyHint(icon: "photo.badge.plus",
                          title: "还没有\(filter == .all ? "" : filter.title(store.settings))照片",
                          subtitle: "从相册选择或直接拍照，照片会自动压缩存储")
            } else {
                LazyVGrid(columns: columns, spacing: Metrics.gridSpacing) {
                    ForEach(photos) { p in
                        cell(p)
                    }
                }
            }
        }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            importPicked(items)
        }
        .onChange(of: capturedImage) { img in
            guard let img else { return }
            if let name = store.importImage(img, clientID: clientID) {
                client.photos.append(PhotoItem(fileName: name, phase: targetPhase))
                store.save()
                showToast("已添加 1 张\(store.settings.label(for: targetPhase))照片")
            }
            capturedImage = nil
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewingID != nil },
            set: { if !$0 { viewingID = nil } }
        )) {
            if let id = viewingID {
                PhotoViewer(clientID: clientID, client: $client, startPhotoID: id)
            }
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
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: 筛选条

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(PhaseFilter.allCases) { f in
                let active = f == filter
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { filter = f }
                } label: {
                    HStack(spacing: 4) {
                        Text(f.title(store.settings))
                            .font(.system(size: 12, weight: active ? .semibold : .regular))
                        Text("\(count(f))")
                            .font(.system(size: 10))
                            .opacity(0.7)
                    }
                    .foregroundColor(active ? .white : Theme.inkSoft)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(active ? AnyView(Theme.gradRose) : AnyView(Theme.card))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(active ? Color.clear : Theme.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func count(_ f: PhaseFilter) -> Int {
        switch f {
        case .all: return client.photos.count
        case .before: return client.beforePhotos.count
        case .after: return client.afterPhotos.count
        }
    }

    // MARK: 添加区

    private var hintBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItems,
                         maxSelectionCount: 40,
                         matching: .images,
                         photoLibrary: .shared()) {
                HStack(spacing: 5) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 12, weight: .medium))
                    Text("从相册添加").font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.gradRose)
                .clipShape(Capsule())
            }

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    showToast("当前设备没有可用相机")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "camera").font(.system(size: 12, weight: .medium))
                    Text("拍照").font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(Theme.roseDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.roseLight)
                .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            if importing {
                ProgressView().scaleEffect(0.8)
            } else {
                Text("归入 \(store.settings.label(for: targetPhase))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }
        }
    }

    // MARK: 网格单元

    private func cell(_ p: PhotoItem) -> some View {
        let url = store.photoURL(clientID: clientID, fileName: p.fileName)
        return Button {
            viewingID = p.id
        } label: {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    LocalImage(url: url)
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()

                    PhaseBadge(text: store.settings.label(for: p.phase), phase: p.phase)
                        .padding(5)

                    if !p.tag.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Text(p.tag)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.45))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                        }
                        .padding(5)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.movePhoto(clientID: clientID,
                                photoID: p.id,
                                to: p.phase == .before ? .after : .before)
                showToast("已移到\(p.phase == .before ? store.settings.afterLabel : store.settings.beforeLabel)")
            } label: {
                Label(p.phase == .before
                      ? "改为\(store.settings.afterLabel)"
                      : "改为\(store.settings.beforeLabel)",
                      systemImage: "arrow.left.arrow.right")
            }
            Button(role: .destructive) {
                withAnimation { store.deletePhoto(clientID: clientID, photo: p) }
                showToast("已删除")
            } label: {
                Label("删除照片", systemImage: "trash")
            }
        }
    }

    // MARK: 导入

    private func importPicked(_ items: [PhotosPickerItem]) {
        importing = true
        let phase = targetPhase
        Task {
            var added = 0
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data),
                      let name = store.importImage(img, clientID: clientID) else { continue }
                await MainActor.run {
                    client.photos.append(PhotoItem(fileName: name, phase: phase))
                }
                added += 1
            }
            await MainActor.run {
                store.save()
                importing = false
                pickerItems = []
                if added > 0 {
                    showToast("已添加 \(added) 张\(store.settings.label(for: phase))照片")
                } else {
                    showToast("没有导入成功，请重试")
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if toast == text { toast = nil } }
        }
    }
}

// MARK: - 相机

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 大图查看

struct PhotoViewer: View {
    let clientID: UUID
    @Binding var client: Client
    let startPhotoID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var currentID: UUID
    @State private var showDeleteConfirm = false
    @State private var editingTag = false
    @State private var tagDraft = ""

    init(clientID: UUID, client: Binding<Client>, startPhotoID: UUID) {
        self.clientID = clientID
        self._client = client
        self.startPhotoID = startPhotoID
        self._currentID = State(initialValue: startPhotoID)
    }

    private var photos: [PhotoItem] {
        client.photos.sorted { $0.createdAt > $1.createdAt }
    }

    private var current: PhotoItem? {
        client.photos.first { $0.id == currentID }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(photos) { p in
                    LocalImage(url: store.photoURL(clientID: clientID, fileName: p.fileName),
                               contentMode: .fit)
                        .tag(p.id)
                        .padding(.bottom, 120)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden(true)
        .alert("删除这张照片？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let p = current {
                    store.deletePhoto(clientID: clientID, photo: p)
                    if photos.count <= 1 { dismiss() }
                }
            }
        } message: {
            Text("照片文件会从相册中移除，无法撤销。")
        }
        .alert("照片标签", isPresented: $editingTag) {
            TextField("例如：面部、颈部", text: $tagDraft)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let id = current?.id, let i = client.photos.firstIndex(where: { $0.id == id }) {
                    client.photos[i].tag = tagDraft
                    store.save()
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            Spacer()
            if let p = current {
                PhaseBadge(text: store.settings.label(for: p.phase), phase: p.phase)
            }
            Spacer()
            Button {
                tagDraft = current?.tag ?? ""
                editingTag = true
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let p = current {
                HStack(spacing: 10) {
                    Button {
                        store.movePhoto(clientID: clientID, photoID: p.id,
                                        to: p.phase == .before ? .after : .before)
                    } label: {
                        Label(p.phase == .before
                              ? "改为\(store.settings.afterLabel)"
                              : "改为\(store.settings.beforeLabel)",
                              systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.55))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(Fmt.dateTime.string(from: p.createdAt))
                    if !p.tag.isEmpty { Text("·"); Text(p.tag) }
                    if !p.caption.isEmpty { Text("·"); Text(p.caption).lineLimit(1) }
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.bottom, 34)
    }
}
