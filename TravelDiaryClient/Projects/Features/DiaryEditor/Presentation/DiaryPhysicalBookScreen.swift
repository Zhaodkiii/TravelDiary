import SwiftUI
import UIKit
import PhotosUI

/// 阅读投影不修改目录：内封皮与第一页组成首跨页，之后按目录顺序连续配对。
struct DiaryPhysicalBookScreen: View {
    @State private var book: DiaryBook
    let store: DiaryDocumentStore
    private let onShowList: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLandscape = false
    @State private var immersionDismissed = false
    @State private var showingPreviewExit = false
    private var isImmersive: Bool { isLandscape && !immersionDismissed }
    private var usesPlainPaper: Bool { isImmersive && AppleDeviceInfo.isDuo }
    private var readerSpreadCount: Int { isImmersive ? contentSpreadCount : spreadCount }
    @AppStorage("diary.reader.animation") private var readingAnimation = true
    @AppStorage("diary.reader.haptics") private var readingHaptics = true
    @AppStorage("diary.reader.sound") private var readingSound = false
    @State private var opened = false
    @State private var spread = 0
    @State private var turningCover = false
    private struct Campaign: Decodable {
        let save_anchor: String?
        let ai_pages_only: Bool?
        let assessed_faces: [AssessedFace]?
        let id: Int?
        let title: String?
        let product: String?
        let included_pages: Int?
        let cap_fen: Int?
        let ends_at: String?
        var enrollment: Enrollment?
        let blocked_reason: String?
        let standard_discount_fen: Int?
        let standard_is_covered: Bool?
        let unrestricted: Bool?
        let experience: Experience?
        let previous_campaigns: [PreviousCampaign]?
    }
    private struct AssessedFace: Decodable {
        let page: String
        let face: String
        let reason: String
    }
    private struct PreviousCampaign: Decodable {
        let title: String
        let heading: String
        let detail: String
    }
    private struct Experience: Decodable {
        let status: String
        let heading: String
        let detail: String
        let action: String
        let action_title: String
        let progress: Double
        let pending: Bool
        let completed: Bool
        let result_key: String
        let coupon_id: String?
        let product_id: String?
        let coupon_available: Bool?
        let order_id: String?
        let coupon_expires_at: String?
        let can_update: Bool
        let can_withdraw: Bool
        let historical: Bool
        let can_resubmit: Bool?
        let review_page_ids: [String]?
        let rewards: [Reward]
        let history: [History]
    }
    private struct Reward: Decodable {
        let threshold: Int
        let title: String
        let discount_fen: Int?
    }
    private struct History: Decodable {
        let event: String
        let at: String
        let reason: String?
        let reported_pages: Int?
        let approved_pages: Int?
    }
    private struct Enrollment: Decodable {
        let reported_pages: Int
        let approved_pages: Int
        let coupon_percent: Int?
        let coupon_available: Bool
        let withdrawn_at: String?
        let attempt: Int?
    }
    private struct EnrollmentResult: Decodable {
        let message: String
        let enrollment: Enrollment?
    }
    @State private var campaign: Campaign?
    @State private var activityOpen = false
    @State private var activityMessage = ""
    @State private var enrolling = false
    @State private var confirmingWithdrawal = false
    @State private var showPrintOffer = false
    @State private var checkingOut = false
    @State private var showingCampaignWallet = false
    @State private var showingPrintOrders = false
    @State private var routedPrintOrder: String?
    @State private var selectedPrintOrder: String?
    @State private var preferredPrintCoupon: String?
    @State private var printProducts: [PrintProduct] = []
    @State private var loadingPrintContext = false
    @State private var printContextError: String?
    @State private var printReadKey = ""
    @State private var lastAutomaticPrintKey = ""
    @State private var printRequestID = UUID()
    @State private var campaignDestination: CampaignDestination?
    @State private var localAIFaces: Int?
    @State private var campaignPages: Int?
    private enum CampaignDestination { case checkout, wallet, orders, order }
    private var printOfferSeenKey: String { "print.offer.\(store.ownerID).lastSeen" }
    @State private var makingCover = false
    @State private var editor: DiaryEditorSession?
    @State private var editingRightHalf = false
    @State private var loadingEditor = false
    @State private var editingReaderPhotos = false
    @State private var errorMessage: String?
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var choosingPreset = false
    @State private var showingExport = false
    private let completedCanvas: Bool
    private var continuousSpread: Bool { true }
    private var readingLeaves: [DiaryReadingLeaf] { DiaryReadingLeaf.project(book) }
    private var innerPages: [DiaryPageEntry] { book.contentPages }
    private var contentSpreadCount: Int { readingLeaves.count / 2 }
    private var spreadCount: Int { contentSpreadCount + 1 }
    private var paperRatio: CGFloat { DiaryBook.coverSize.width / DiaryBook.coverSize.height }

    init(book: DiaryBook, store: DiaryDocumentStore, initialPageID: UUID? = nil, completedCanvas: Bool = false, onShowList: (() -> Void)? = nil) {
        _book = State(initialValue: book)
        self.completedCanvas = completedCanvas
        self.store = store
        self.onShowList = onShowList
        let position = initialPageID.flatMap { id in DiaryReadingLeaf.project(book).firstIndex { $0.page?.id == id } }.map { $0 / 2 } ?? 0
        _spread = State(initialValue: position)
        _opened = State(initialValue: initialPageID != nil || book.shell == nil)
    }

    var body: some View {
        if onShowList != nil {
            readerContent
        } else {
            NavigationStack { readerContent }
        }
    }

    private var campaignBanner: some View {
        HStack {
            Button {
                activityOpen = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(campaign?.experience?.heading ?? campaign?.title ?? "实体书定制").font(.subheadline.weight(.semibold))
                        Text(campaign?.experience?.detail ?? "查看装订进度与优惠")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { showPrintOffer = false } label: { Image(systemName: "xmark") }
                .accessibilityLabel("关闭印制提示")
        }
        .padding(.horizontal, 24)
    }

    private var readerContent: some View {
        readerLayout
            .sheet(isPresented: $activityOpen, onDismiss: {
                let destination = campaignDestination
                campaignDestination = nil
                switch destination {
                case .checkout: checkingOut = true
                case .wallet: showingCampaignWallet = true
                case .orders: showingPrintOrders = true
                case .order: routedPrintOrder = selectedPrintOrder
                case nil: break
                }
            }) {
                printCenter
                    .presentationDetents([.fraction(0.86), .large])
                    .presentationDragIndicator(.visible)
                    .task { await refreshPrintCenter() }
            }
            .sheet(isPresented: $checkingOut, onDismiss: { Task { await loadPrintOffer(manual: true) } }) {
                PrintCheckoutScreen(book: book, store: store, preferredCouponID: preferredPrintCoupon, preferredProductID: campaign?.experience?.product_id)
            }
            .sheet(isPresented: $showingCampaignWallet) {
                NavigationStack {
                    PrintCouponWallet(owner: store.ownerID)
                        .toolbar { Button("关闭") { showingCampaignWallet = false } }
                }
            }
            .sheet(isPresented: $showingPrintOrders) {
                NavigationStack {
                    PrintOrdersScreen(owner: store.ownerID)
                        .toolbar { Button("关闭") { showingPrintOrders = false } }
                }
            }
            .sheet(isPresented: Binding(get: { routedPrintOrder != nil }, set: { if !$0 { routedPrintOrder = nil } }),
                   onDismiss: { Task { await loadPrintOffer(manual: true) } }) {
                if let id = routedPrintOrder {
                    NavigationStack {
                        PrintOrderDetailScreen(id: id, owner: store.ownerID)
                            .toolbar { Button("关闭") { routedPrintOrder = nil } }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadPrintOffer(manual: true) } }
            }
    }

    private var readerLayout: some View {
            VStack(spacing: isImmersive ? 0 : 16) {
                bookViewport
                if !isImmersive {
                    if showPrintOffer { campaignBanner }
                    HStack {
                        Button { if spread > 0 { spread -= 1 } else { closeBook() } } label: {
                            Image(systemName: "chevron.left")
                        }.disabled(!opened || (spread == 0 && book.shell == nil)).accessibilityLabel(spread == 0 ? "合上手帐" : "上一跨页")
                        Spacer()
                        Text(opened ? (spread == 0 || spread >= contentSpreadCount ? spreadTitle(spread) : "\(spreadTitle(spread)) / \(book.bodyPageCount)") : "外壳")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Button { if opened { spread += 1 } else { openBook() } } label: {
                            Image(systemName: "chevron.right")
                        }.disabled(spreadCount == 0 || (opened && spread >= spreadCount - 1))
                            .accessibilityLabel(opened ? "下一跨页" : "展开手帐")
                    }.padding(.horizontal, 28).disabled(turningCover)
                    HStack(spacing: 0) {
                        thumbnailRail
                        Menu { addActions } label: {
                            Image(systemName: "plus.circle.fill").font(.title2).padding(.trailing, 16)
                        }.accessibilityLabel("添加页面")
                    }.disabled(turningCover)
                }
            }
            .ignoresSafeArea(.container, edges: usesPlainPaper ? .all : [])
            .onGeometryChange(for: Bool.self) { geometry in
                // Include system insets so hiding the navigation bar cannot flip the classification.
                geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing >
                    geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            } action: { landscape in
                isLandscape = landscape
                if !landscape { immersionDismissed = false }
            }
            .onChange(of: isImmersive) { _, immersive in
                showingPreviewExit = false
                if immersive {
                    spread = min(spread, max(contentSpreadCount - 1, 0))
                    openBook()
                }
            }
            .overlay(alignment: .topLeading) {
                if isImmersive && showingPreviewExit {
                    Button("退出预览", systemImage: "arrow.down.right.and.arrow.up.left") {
                        immersionDismissed = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.8))
                    .padding(12)
                }
            }
            .task(id: showingPreviewExit) {
                guard showingPreviewExit else { return }
                do {
                    try await Task.sleep(for: .seconds(3))
                    showingPreviewExit = false
                } catch { }
            }
            .accessibilityAction(named: "退出沉浸预览") { immersionDismissed = true }
            .accessibilityAction(named: "下一跨页") {
                if opened && spread < readerSpreadCount - 1 { spread += 1 }
            }
            .accessibilityAction(named: "上一跨页") {
                if spread > 0 { spread -= 1 }
            }
            .toolbar(isImmersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(isImmersive)
            .persistentSystemOverlays(isImmersive ? .hidden : .automatic)
            .disabled(loadingEditor || editingReaderPhotos)
            .overlay { if editingReaderPhotos { ProgressView("正在处理照片…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .overlay { if loadingEditor { ProgressView("正在打开页面…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                        await createPage(data: data)
                    } catch { errorMessage = error.localizedDescription }
                    photo = nil
                }
            }
            .sheet(isPresented: $showingExport) { DiaryBookExportSheet(book: book, store: store) }
            .sheet(isPresented: $choosingPreset) {
                DiaryPresetPagePicker(ownerID: store.ownerID, targetBook: book) { updated in
                    book = updated
                    if let last = innerPages.last { reveal(last.id) }
                }
            }
            .fullScreenCover(isPresented: $makingCover, onDismiss: { Task { await refreshAfterEditing() } }) {
                DiaryCoverEditorScreen(store: store)
            }
            .fullScreenCover(item: $editor, onDismiss: {
                Task { await refreshAfterEditing() }
            }) { session in
                DiaryEditorScreen(session: session, entranceOnRightPage: editingRightHalf, onCommitSuccess: {
                    Task {
                        await refreshAfterEditing()
                        campaignPages = try? await store.printActivityPageCount(book)
                        await loadPrintOffer(announce: true)
                    }
                })
            }
            .alert("无法打开页面", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .task {
                await refreshAfterEditing()
                await loadPrintOffer(manual: true)
                if campaign?.enrollment != nil || completedCanvas {
                    campaignPages = try? await store.printActivityPageCount(book)
                    await loadPrintOffer(manual: true, announce: completedCanvas)
                }
            }
            .task(id: "\(book.catalogRevision)-\(spread)-\(opened)") { await preloadNeighboringSpreads() }
            .background {
                (isImmersive ? Color.black : Color(uiColor: .systemGroupedBackground))
                    .ignoresSafeArea()
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onShowList == nil {
                    ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { activityOpen = true } label: { printEntryIcon }
                        .accessibilityLabel("实体书定制")
                        .accessibilityValue(campaign?.experience?.heading ?? "查看规格与价格")
                    #if DEBUG
                    Menu {
                        Toggle("逐层呈现", isOn: $readingAnimation)
                        Toggle("阅读触感", isOn: $readingHaptics)
                        Toggle("纸张音效", isOn: $readingSound)
                    } label: { Image(systemName: "waveform") }
                    .accessibilityLabel("阅读动画与反馈")
                    #endif
                    Button { showingExport = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("导出手帐").disabled(book.pages.isEmpty || turningCover)
                    if let onShowList {
                        Button(action: onShowList) { Image(systemName: "list.bullet") }
                            .accessibilityLabel("页面列表")
                            .disabled(turningCover)
                    } else if book.shell != nil {
                        Button(opened ? "合上" : "展开") { if opened { closeBook() } else { openBook() } }
                            .disabled(spreadCount == 0 || turningCover)
                    }
                }
            }
    }

    private var bookViewport: some View {
        GeometryReader { geometry in
            if isImmersive {
                let size = usesPlainPaper
                    ? DiaryBookStageLayout.paperSize(viewport: geometry.size, paperRatio: paperRatio)
                    : DiaryBookStageLayout.openSize(viewport: geometry.size, paperRatio: paperRatio)
                // Keep the original direct UIKit gesture path in immersive reading.
                bookStage(viewport: geometry.size)
                    .allowsHitTesting(!turningCover)
                    .overlay {
                        HStack(spacing: 0) {
                            previewExitMargin
                            Spacer(minLength: 0).frame(width: size.width).allowsHitTesting(false)
                            previewExitMargin
                        }
                    }
            } else {
                let stageViewport = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 80))
                DiaryBookZoomViewport(contentSize: stageViewport,
                                      resetToken: opened ? spread + 1 : 0) {
                    bookStage(viewport: stageViewport)
                        .simultaneousGesture(TapGesture().onEnded { if !opened { openBook() } })
                }
                .frame(width: stageViewport.width, height: stageViewport.height)
                .allowsHitTesting(!turningCover)
                .overlay(alignment: .top) {
                    if opened && !turningCover {
                        let size = DiaryBookStageLayout.openSize(viewport: stageViewport, paperRatio: paperRatio)
                        HStack(alignment: .top, spacing: 16) {
                            if continuousSpread {
                                let ids = Set(readingLeaves.dropFirst(spread * 2).prefix(2).compactMap { $0.page?.id })
                                ForEach(innerPages.filter { ids.contains($0.id) }) { page in
                                    readerPhotos(at: innerPages.firstIndex(where: { $0.id == page.id }) ?? 0, title: "当前页面照片")
                                }
                            } else {
                                readerPhotos(at: spread * 2 - 1, title: "左页照片")
                                readerPhotos(at: spread * 2, title: "右页照片")
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(width: size.width)
                        .offset(y: (stageViewport.height + size.height) / 2 + 8)
                    }
                }
            }
        }.clipped()
    }

    @ViewBuilder private func readerPhotos(at index: Int, title: String) -> some View {
        if innerPages.indices.contains(index) {
            let page = innerPages[index]
            DiaryReaderPhotoStrip(page: page, store: store, title: title, readerBusy: $editingReaderPhotos,
                                  onSaved: { await refreshAfterEditing() })
                .id(page.id)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 68).allowsHitTesting(false)
        }
    }

    @ViewBuilder private func bookStage(viewport: CGSize) -> some View {
        if usesPlainPaper {
            let size = DiaryBookStageLayout.paperSize(viewport: viewport, paperRatio: paperRatio)
            curlBook
                .frame(width: size.width, height: size.height)
                .frame(width: viewport.width, height: viewport.height)
        } else {
            DiaryBookOpeningStage(progress: opened ? 1 : 0, viewport: viewport,
                                  paperRatio: paperRatio, cover: book.shell,
                                  firstPage: book.effectiveCover, store: store) {
                curlBook
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: opened)
        }
    }

    private var curlBook: some View {
        DiaryCurlBook(pages: innerPages, leaves: readingLeaves, continuousSpread: continuousSpread, store: store, spreadCount: readerSpreadCount, spread: $spread,
            allowsEditing: !isImmersive, reduceMotion: reduceMotion, plainPaper: usesPlainPaper,
            onSelectPage: openEditor, onAddPage: handleAdd)
            .id(book.catalogRevision)
    }

    private var previewExitMargin: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { showingPreviewExit.toggle() }
    }

    @ViewBuilder private var addActions: some View {
        Button("空白页", systemImage: "doc") { Task { await createPage(data: nil) } }
        Button("从照片新建", systemImage: "photo") { pickingPhoto = true }
        Button("从预设选择", systemImage: "books.vertical") { choosingPreset = true }
    }
    private func handleAdd(_ action: DiaryReaderAddAction) {
        switch action {
        case .cover: makingCover = true
        case .blank: Task { await createPage(data: nil) }
        case .photo: pickingPhoto = true
        case .preset: choosingPreset = true
        }
    }
    private func reveal(_ id: UUID) {
        if let index = innerPages.firstIndex(where: { $0.id == id }) { spread = continuousSpread ? (readingLeaves.firstIndex(where: { $0.page?.id == id }) ?? 0) / 2 : (index + 1) / 2 }
        opened = true
    }
    private func createPage(data: Data?) async {
        guard !loadingEditor else { return }
        loadingEditor = true
        defer { loadingEditor = false }
        do {
            var document = DiaryDocument()
            document.bookID = book.id
            document.objects[document.rootContentID]?.referenceSize = book.defaultPageSize
            var images: [UUID: UIImage] = [:]
            if let data {
                let (asset, image) = try await store.importImage(data, documentID: document.id)
                document.assets[asset.id] = asset; images[asset.id] = image
                document.objects[document.rootContentID]?.layers.insert(
                    DiaryLayer.photoBackground(asset: asset, pageSize: book.defaultPageSize), at: 0)
            }
            try await store.save(document)
            book = try await store.loadBook()
            reveal(document.id)
            editingRightHalf = false
            editor = DiaryEditorSession(document: document, images: images, store: store)
        } catch { errorMessage = error.localizedDescription }
    }

    private func openEditor(_ page: DiaryPageEntry, rightHalf: Bool) {
        guard opened, !turningCover, !loadingEditor, editor == nil else { return }
        editingRightHalf = rightHalf
        loadingEditor = true
        Task { @MainActor in
            defer { loadingEditor = false }
            do {
                let loaded = try await store.load(page.id)
                editor = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func preloadNeighboringSpreads() async {
        guard opened else { return }
        // 当前跨页先完成，避免预取抢在可见页面之前排入素材读取队列。
        let currentPages = readingLeaves.dropFirst(spread * 2).prefix(2).compactMap { $0.page }
        let neighboringPages = readingLeaves.dropFirst(max(0, spread * 2 - 2)).prefix(6).compactMap { $0.page }
        let pages = book.contentPages
        let current = pages.indices.filter { index in currentPages.contains { $0.id == pages[index].id } }
        let neighbors = pages.indices.filter { index in neighboringPages.contains { $0.id == pages[index].id } && !current.contains(index) }
        do {
            for index in current where pages.indices.contains(index) {
                try Task.checkCancellation()
                if readingAnimation {
                    _ = try? await DiaryReadingSources.load(page: pages[index], store: store)
                }
                _ = try? await DiaryPreviewService.image(page: pages[index], store: store, large: true)
            }
            // 快速连翻时不立即预取；已开始的共享请求仍可被后续页面复用。
            try await Task.sleep(for: .milliseconds(200))
            for index in neighbors where pages.indices.contains(index) {
                try Task.checkCancellation()
                if readingAnimation {
                    _ = try? await DiaryReadingSources.load(page: pages[index], store: store)
                }
                _ = try? await DiaryPreviewService.image(page: pages[index], store: store, large: true)
            }
        } catch is CancellationError { }
        catch { /* 预取失败由实际打开页面时的重试入口处理。 */ }
    }

    private var printEntryIcon: some View {
        let experience = campaign?.experience
        let hasActivity = campaign?.id != nil && campaign?.enrollment?.withdrawn_at == nil
        let progress = min(1, max(0, experience?.progress ?? 0))
        let unread = !(experience?.result_key.isEmpty ?? true) && experience?.result_key != printReadKey
        return ZStack {
            if hasActivity {
                Circle().stroke(.primary.opacity(0.2), lineWidth: 1.5)
                Circle().trim(from: 0, to: progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(.primary.opacity(0.5)).frame(width: 3, height: 3).offset(y: 13)
            }
            Image(systemName: "book.closed").font(.system(size: 15, weight: .medium))
            if experience?.completed == true && hasActivity {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.7, green: 0.54, blue: 0.27)).offset(x: 10, y: 10)
            } else if experience?.pending == true && hasActivity {
                Circle().stroke(.primary, lineWidth: 1.5).frame(width: 4, height: 4)
                    .offset(x: CGFloat(sin(progress * 2 * .pi)) * 13,
                            y: -CGFloat(cos(progress * 2 * .pi)) * 13)
            }
            if unread { Circle().fill(.primary).frame(width: 5, height: 5).offset(x: 12, y: -12) }
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }

    private var printCenter: some View {
        let ink = Color(red: 0.17, green: 0.25, blue: 0.19)
        let paper = Color(red: 0.98, green: 0.96, blue: 0.91)
        let experience = campaign?.experience
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image("PrintCampaignHero")
                    .resizable().scaledToFill()
                    .frame(height: 170).frame(maxWidth: .infinity).clipped()
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottomTrailing) {
                        Text("样书效果图").font(.caption2)
                            .padding(6).foregroundStyle(.white)
                            .background(.black.opacity(0.6), in: Capsule()).padding(10)
                    }
                VStack(alignment: .leading, spacing: 16) {
                    Text("实体书定制").font(.system(.title2, design: .serif, weight: .bold))
                    Text(book.title).font(.subheadline)
                    if loadingPrintContext { ProgressView("正在确认进度与优惠") }
                    if let error = printContextError {
                        Text(error).font(.footnote)
                        if let localAIFaces {
                            Text("本册有 \(localAIFaces) 个 AI 内页面待联网核对，制作记录已保存在本机。").font(.footnote)
                        }
                        Button("重新加载") { Task { await refreshPrintCenter() } }
                    }
                    if let offer = campaign, let experience, offer.id != nil {
                        printActivityContent(offer, experience: experience)
                    } else if experience?.status == "no_activity" {
                        Text("把旅途留在纸上").font(.headline)
                        Text("选择规格，先预览成品，再确认地址与费用。").font(.subheadline)
                    }
                    if let previous = campaign?.previous_campaigns, !previous.isEmpty {
                        DisclosureGroup("历史活动") {
                            ForEach(Array(previous.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    Text(item.heading).font(.footnote)
                                    Text(item.detail).font(.caption)
                                }.padding(.vertical, 6)
                            }
                        }.font(.subheadline)
                    }
                    printProductList
                    HStack {
                        Button("我的优惠券") { navigatePrint(.wallet) }
                        Spacer()
                        Button("印制订单") { navigatePrint(.orders) }
                    }.font(.subheadline)
                }.padding(.horizontal, 22)
            }.padding(.bottom, 18)
        }
        .foregroundStyle(ink).tint(ink).background(paper)
        .overlay(alignment: .topTrailing) {
            Button { activityOpen = false } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44).background(paper, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("关闭实体书定制").padding(12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    performPrintAction(experience?.action ?? "checkout")
                } label: {
                    Group {
                        if enrolling { ProgressView().tint(.white) }
                        else { Text(experience?.action_title ?? "预览并定制").fontWeight(.semibold) }
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 46)
                    .background(ink, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                    .disabled(enrolling || loadingPrintContext || printContextError != nil)
                if experience?.can_resubmit == true {
                    Button("完善后重新提交") { Task { await enrollForPrint() } }.font(.footnote).disabled(enrolling)
                } else if experience?.can_update == true {
                    Button("更新本册进度") { Task { await enrollForPrint() } }.font(.footnote).disabled(enrolling)
                }
                if experience?.can_withdraw == true {
                    Button("退出活动") { confirmingWithdrawal = true }.font(.footnote).disabled(enrolling)
                }
                if !activityMessage.isEmpty { Text(activityMessage).font(.footnote) }
            }.padding(.horizontal, 22).padding(.vertical, 10).background(paper)
        }
        .confirmationDialog("退出活动？", isPresented: $confirmingWithdrawal, titleVisibility: .visible) {
            Button("确认退出", role: .destructive) { Task { await withdrawFromPrintCampaign() } }
            Button("继续参加", role: .cancel) {}
        } message: {
            Text(campaign?.enrollment?.coupon_percent == nil
                 ? "退出后，本次进度将结束，待核验申请会撤回。作品仍可继续编辑。"
                 : "退出后，本期进度和升级将结束。已发优惠券及关联订单可在券包和订单中查看。")
        }
    }

    private var printProductList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("规格与费用").font(.headline)
            ForEach(printProducts) { product in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(product.title) · \(product.width_mm) × \(product.height_mm) mm").font(.subheadline.weight(.medium))
                    Text(product.free_printing == true ? "印制费 ¥0" : "每册基础价 \(PrintText.money(product.base_fen))，每内页面 \(PrintText.money(product.page_fen))")
                        .font(.footnote)
                    Text("运费 \(PrintText.money(product.shipping_fen)) · \(product.min_pages)–\(product.max_pages) 个内页面")
                        .font(.footnote)
                }
            }
            if printProducts.isEmpty && !loadingPrintContext && printContextError == nil {
                Text("暂无可用印制规格").font(.footnote)
            }
            if campaign?.id != nil {
                Button("直接预览并定制") {
                    preferredPrintCoupon = nil
                    navigatePrint(.checkout)
                }.font(.subheadline)
            }
        }
    }

    private func printActivityContent(_ offer: Campaign, experience: Experience) -> some View {
        let approved = offer.enrollment?.approved_pages ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            Text(offer.title ?? "本册装订礼").font(.subheadline.weight(.semibold))
            if experience.historical { Text("历史活动").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                ForEach(experience.rewards, id: \.threshold) { reward in
                    printMilestone("\(reward.threshold) 页", reward.title, approved >= reward.threshold || experience.completed)
                }
            }
            Text(experience.heading).font(.headline)
            if offer.enrollment?.withdrawn_at == nil && offer.enrollment != nil {
                ProgressView(value: experience.progress).tint(Color(red: 0.17, green: 0.25, blue: 0.19))
            }
            Text(experience.detail).font(.footnote)
            if campaign?.ai_pages_only == true {
                let faces = campaign?.assessed_faces ?? []
                Text("仅累计活动期间在本册保存的 AI 制作内页。请在截止前联网提交。").font(.footnote)
                DisclosureGroup("本期 AI 有效内页 · \(faces.filter { $0.reason.isEmpty }.count) 页") {
                    ForEach(Array(faces.enumerated()), id: \.offset) { _, item in
                        let index = book.bodyPages.firstIndex { $0.id.uuidString.lowercased() == item.page.lowercased() }
                        Text("内页 \((index ?? 0) + 1) · \(item.face == "right" ? "右页" : "左页") · \(item.reason.isEmpty ? "已计入" : item.reason)")
                    }
                    Text("手工页、复制页和缺少制作记录的旧页不自动累计。")
                }.font(.footnote)
            }
            if let raw = experience.coupon_expires_at, let expiry = PrintText.date(raw) {
                Text("券有效期至 \(expiry.formatted(date: .abbreviated, time: .shortened))").font(.footnote)
            }
            if experience.coupon_id != nil {
                HStack {
                    Button("查看优惠券") { navigatePrint(.wallet) }
                    if experience.coupon_available == true && offer.enrollment?.coupon_percent == 50 {
                        Button("使用第一档优惠") {
                            preferredPrintCoupon = experience.coupon_id
                            navigatePrint(.checkout)
                        }
                    }
                }.font(.subheadline)
                if offer.enrollment?.coupon_percent == 50 {
                    Text("使用第一档券后，本期奖励结束。").font(.caption)
                }
            }
            DisclosureGroup("活动规则与提交记录") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("适用 \(offer.product ?? "指定规格") · 优惠覆盖 \(offer.included_pages ?? 0) 个印制页 · 每券最高抵扣 \(PrintText.money(offer.cap_fen ?? 0))，运费另计。")
                    if let raw = offer.ends_at, let end = PrintText.date(raw) {
                        Text("报名与申报截止：\(end.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text("本册排版共 \(book.bodyPageCount) 页，有效内页以核验结果为准。")
                    ForEach(Array(experience.history.enumerated()), id: \.offset) { _, event in
                        Text(printHistoryText(event))
                    }
                }.font(.footnote).padding(.vertical, 8)
            }.font(.subheadline)
        }
    }

    private func printHistoryText(_ event: History) -> String {
        let date = PrintText.date(event.at)?.formatted(date: .abbreviated, time: .shortened) ?? ""
        switch event.event {
        case "progress": return "\(date) · 申报 \(event.reported_pages ?? 0) 页"
        case "approved": return "\(date) · 已核验 \(event.approved_pages ?? 0) 页"
        case "returned", "rejected": return "\(date) · \(event.reason ?? "请完善作品后重新提交")"
        case "withdrawn": return "\(date) · 退出活动"
        default: return "\(date) · 报名"
        }
    }

    private func navigatePrint(_ destination: CampaignDestination) {
        campaignDestination = destination
        activityOpen = false
    }

    private func performPrintAction(_ action: String) {
        switch action {
        case "join", "rejoin", "submit": Task { await enrollForPrint() }
        case "rework":
            if let raw = campaign?.experience?.review_page_ids?.first, let id = UUID(uuidString: raw),
               book.contentPages.contains(where: { $0.id == id }) {
                reveal(id)
            }
            activityOpen = false
        case "wallet": navigatePrint(.wallet)
        case "order":
            selectedPrintOrder = campaign?.experience?.order_id
            navigatePrint(.order)
        case "checkout":
            preferredPrintCoupon = campaign?.experience?.coupon_available == true ? campaign?.experience?.coupon_id : nil
            navigatePrint(.checkout)
        default: activityOpen = false
        }
    }

    private var printReadStorageKey: String { "print.read.\(store.ownerID).\(book.id.uuidString)" }

    private func refreshPrintCenter() async {
        loadingPrintContext = true
        printContextError = nil
        do { localAIFaces = try await store.printActivityEvidence(book).count
            if campaign?.ai_pages_only != true { campaignPages = try await store.printActivityPageCount(book) } }
        catch { printContextError = error.localizedDescription }
        let countError = printContextError
        await loadPrintOffer(manual: true)
        if let countError { printContextError = countError }
        do { printProducts = try await PrintOrderService.shared.products(owner: store.ownerID) }
        catch { printContextError = error.localizedDescription }
        loadingPrintContext = false
    }

    private func printMilestone(_ pages: String, _ reward: String, _ reached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(pages, systemImage: reached ? "checkmark.circle.fill" : "seal")
                .font(.system(.headline, design: .serif, weight: .semibold))
            Text(reward).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
    }

    private func loadPrintOffer(manual: Bool = false, preserveOnFailure: Bool = false, announce: Bool = false) async {
        let requestID = UUID()
        printRequestID = requestID
        do {
            let path = "campaign/?book=\(book.id.uuidString)&pages=\(campaignPages ?? 0)"
            let service = PrintOrderService.shared
            var offer: Campaign = try await service.request(path, owner: store.ownerID)
            guard printRequestID == requestID else { return }
            if let anchor = offer.save_anchor {
                UserDefaults.standard.set(anchor, forKey: "print.ai.anchor.\(store.ownerID).\(book.id.uuidString)")
            }
            if offer.ai_pages_only == true {
                let faces = try await store.printActivityEvidence(book)
                localAIFaces = faces.count
                offer = try await service.request(path, owner: store.ownerID, body: try service.json(["faces": faces]))
            }
            guard printRequestID == requestID else { return }
            campaign = offer
            printReadKey = UserDefaults.standard.string(forKey: printReadStorageKey) ?? ""
            printContextError = nil
            let key = offer.experience?.result_key ?? ""
            let changed = !key.isEmpty && key != printReadKey && key != lastAutomaticPrintKey
            let allowed = UserDefaults.standard.double(forKey: printOfferSeenKey) < Date().timeIntervalSince1970 - 86400
            if offer.id != nil && !activityOpen && ((announce && allowed) || (changed && lastAutomaticPrintKey != "")) {
                showPrintOffer = true
                lastAutomaticPrintKey = key
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: printOfferSeenKey)
            }
            if offer.id == nil { showPrintOffer = false }
            if activityOpen {
                printReadKey = key
                UserDefaults.standard.set(key, forKey: printReadStorageKey)
            }
            if lastAutomaticPrintKey.isEmpty { lastAutomaticPrintKey = key }
        } catch {
            if printRequestID == requestID {
                printContextError = error.localizedDescription
                if !preserveOnFailure && campaign == nil { showPrintOffer = false }
            }
        }
    }

    private func enrollForPrint() async {
        guard let id = campaign?.id, !enrolling else { return }
        enrolling = true
        defer { enrolling = false }
        do {
            let service = PrintOrderService.shared
            let count = campaign?.ai_pages_only == true ? 0 : try await store.printActivityPageCount(book)
            var fields: [String: Any] = ["book_id": book.id.uuidString, "pages": count,
                                            "rejoin": campaign?.enrollment?.withdrawn_at != nil,
                                            "attempt": campaign?.enrollment?.attempt ?? 1]
            if campaign?.ai_pages_only == true { fields["faces"] = try await store.printActivityEvidence(book) }
            let payload = try service.json(fields)
            let result: EnrollmentResult = try await service.request("campaign/\(id)/join/", owner: store.ownerID, body: payload)
            campaignPages = count
            if let enrollment = result.enrollment { campaign?.enrollment = enrollment }
            activityMessage = ""
            await loadPrintOffer(manual: true, preserveOnFailure: true)
        } catch { activityMessage = error.localizedDescription }
    }

    private func withdrawFromPrintCampaign() async {
        guard let id = campaign?.id, let attempt = campaign?.enrollment?.attempt, !enrolling else { return }
        enrolling = true
        defer { enrolling = false }
        do {
            let service = PrintOrderService.shared
            let payload = try service.json(["book_id": book.id.uuidString, "attempt": attempt])
            let result: EnrollmentResult = try await service.request("campaign/\(id)/withdraw/", owner: store.ownerID, body: payload)
            if campaign?.id == id { campaign?.enrollment = result.enrollment }
            activityMessage = result.message
            await loadPrintOffer(manual: true, preserveOnFailure: true)
        } catch { activityMessage = error.localizedDescription }
    }

    private func refreshAfterEditing() async {
        do {
            book = try await store.loadBook()
            spread = min(spread, max(readerSpreadCount - 1, 0))
        } catch { errorMessage = error.localizedDescription }
    }

    private var thumbnailRail: some View {
        DiaryBookThumbnailRail(hasCover: book.shell != nil, spreadCount: spreadCount,
            spread: spread, opened: opened, title: spreadTitle,
            onClose: closeBook, onSelect: { spread = $0; openBook() }) {
                if let cover = book.shell { DiaryPagePreview(page: cover, store: store) }
            } leaf: { index in thumbnail(index) }
    }

    @ViewBuilder private func thumbnail(_ index: Int) -> some View {
        if index == -1 {
            DiaryBookLining().frame(width: 50, height: 76)
        } else if continuousSpread, readingLeaves.indices.contains(index + 1) {
            let leaf = readingLeaves[index + 1]
            if let page = leaf.page {
                if let left = leaf.left { DiarySpreadHalfPreview(page: page, store: store, left: left).frame(width: 50, height: 76) }
                else { DiaryPagePreview(page: page, store: store).frame(width: 50, height: 76) }
            } else { Color(red: 0.96, green: 0.92, blue: 0.82).frame(width: 50, height: 76) }
        } else if index == -1 {
            DiaryBookLining().frame(width: 50, height: 76)
        } else if innerPages.indices.contains(index) {
            DiaryPagePreview(page: innerPages[index], store: store).frame(width: 50, height: 76)
        } else {
            Color(red: 0.96, green: 0.92, blue: 0.82).frame(width: 50, height: 76)
        }
    }
    private func spreadTitle(_ index: Int) -> String {
        if index == 0 { return book.effectiveCover == nil ? "添加封面" : "封面" }
        if index >= contentSpreadCount { return "添加页面" }
        let shown = readingLeaves.dropFirst(index * 2).prefix(2).compactMap { $0.page }
        let ids = Set(shown.map(\.id))
        let body = book.bodyPages
        let first = body.prefix { !ids.contains($0.id) }.reduce(1) { $0 + ($1.canvasLayout == .spread ? 2 : 1) }
        let count = body.filter { ids.contains($0.id) }.reduce(0) { $0 + ($1.canvasLayout == .spread ? 2 : 1) }
        return count <= 1 ? "第 \(first) 页" : "第 \(first)–\(first + count - 1) 页"
    }
    private func openBook() {
        guard spreadCount > 0, !turningCover else { return }
        setOpened(true)
    }
    private func closeBook() {
        guard !turningCover, book.shell != nil else { return }
        // 合书前回到内封皮，保证封面背面始终对应书本起始位置。
        spread = 0
        setOpened(false)
    }
    private func setOpened(_ value: Bool) {
        guard opened != value else { return }
        turningCover = !reduceMotion && !usesPlainPaper
        opened = value
        guard turningCover else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            turningCover = false
        }
    }
}

/// 静止时显示装订结构；卷页期间由 UIKit 协调淡出，避免覆盖在弯曲纸面上。
struct DiaryBindingRings: View {
    var body: some View {
        GeometryReader { geometry in
            // 关闭时保留透明视口，让视频导出的独立装订层仍有有效尺寸。
            Color.clear
            if DiaryBookAppearance.showsBindingRings {
                // 九扣按三组三枚排列；固定在书脊，翻页时不跟随纸张旋转。
                ForEach(0..<9) { index in
                    let fraction = DiaryBookSpine.ringPositions[index]
                    Image("DiaryBookRing").resizable().scaledToFit()
                        .frame(width: min(geometry.size.width * 0.075, 56))
                        .position(x: geometry.size.width / 2, y: geometry.size.height * fraction)
                }
            }
        }
    }

}

/// UIKit 中置书脊始终显示两个控制器，内封皮占首位，末尾缺页时补齐留白。
/// 原生 pageCurl 提供交互卷页、取消回弹和纸张背面，无需模拟整张跨页滑动。
private enum DiaryReaderAddAction { case cover, blank, photo, preset }

private struct DiaryCurlBook: View {
    let pages: [DiaryPageEntry]
    let leaves: [DiaryReadingLeaf]
    let continuousSpread: Bool
    let store: DiaryDocumentStore
    let spreadCount: Int
    @Binding var spread: Int
    let allowsEditing: Bool
    let reduceMotion: Bool
    let plainPaper: Bool
    let onSelectPage: (DiaryPageEntry, Bool) -> Void
    let onAddPage: (DiaryReaderAddAction) -> Void

    var body: some View {
        DiaryPageCurlReader(spreadCount: spreadCount, spread: $spread, reduceMotion: reduceMotion, allowsPageActions: allowsEditing, showsBinding: true) { index, canSelect in
            DiaryPaperController(index: index, page: continuousSpread ? (leaves.indices.contains(index) ? leaves[index].page : nil) : (pages.indices.contains(index - 1) ? pages[index - 1] : nil), continuousSpread: continuousSpread, splitHalf: continuousSpread && leaves.indices.contains(index) ? leaves[index].left : nil,
                store: store, plainPaper: plainPaper, showsAddPlaceholder: allowsEditing, canSelect: canSelect, onAdd: { if canSelect() { onAddPage($0) } },
                onSelect: { if canSelect() { onSelectPage($0, continuousSpread && leaves.indices.contains(index) && leaves[index].left == false) } })
        }
    }
}

protocol DiaryIndexedPaper: AnyObject {
    var index: Int { get }
}

/// Lets the zoom viewport suspend navigation without changing UIKit gesture state.
final class DiaryCurlPageViewController: UIPageViewController {
    var onZoomSuspensionChange: ((Bool) -> Void)?

    func setZoomSuspended(_ suspended: Bool) {
        onZoomSuspensionChange?(suspended)
    }
}

/// Keep UIKit's own gesture decisions while preventing new curls during updates.
@MainActor private final class DiaryCurlGestureGate: NSObject, UIGestureRecognizerDelegate {
    nonisolated(unsafe) weak var original: (any UIGestureRecognizerDelegate)?
    var allowsNavigation: () -> Bool = { true }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        allowsNavigation() && (original?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true)
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}

/// Shared native curl engine for saved diaries and read-only preset previews.
struct DiaryPageCurlReader: UIViewControllerRepresentable {
    let spreadCount: Int
    @Binding var spread: Int
    let reduceMotion: Bool
    var allowsPageActions = true
    var showsBinding = true
    let makePaper: (Int, @escaping () -> Bool) -> UIViewController

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = DiaryCurlPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue]
        )
        controller.isDoubleSided = true
        controller.delegate = context.coordinator
        controller.onZoomSuspensionChange = { [weak coordinator = context.coordinator, weak controller] suspended in
            guard let coordinator, let controller else { return }
            coordinator.setZoomSuspended(suspended, in: controller)
        }
        controller.view.backgroundColor = .clear
        context.coordinator.installReducedMotionSwipes(in: controller)
        context.coordinator.installRings(in: controller)
        context.coordinator.show(spread, in: controller, animated: false)
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateBindingVisibility()
        context.coordinator.updateMotionPolicy(in: controller)
        context.coordinator.show(spread, in: controller, animated: !reduceMotion)
    }

    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: DiaryPageCurlReader
        private var readingTask: Task<Void, Never>?
        private var transitioning = false
        private var displayed = -1
        private var zoomSuspended = false
        private var pageSource: DiaryPageCurlReader
        private var papers: [Int: UIViewController] = [:]
        private var reducedMotionSwipes: [UISwipeGestureRecognizer] = []
        private weak var navigationController: UIPageViewController?
        private var navigationGates: [DiaryCurlGestureGate] = []

        private func hasActiveGesture(in controller: UIPageViewController) -> Bool {
            controller.gestureRecognizers.contains { $0.state == .began || $0.state == .changed }
        }

        func installNavigationGates(in controller: UIPageViewController) {
            guard navigationController !== controller else { return }
            navigationController = controller
            for gesture in controller.gestureRecognizers {
                let gate = DiaryCurlGestureGate()
                gate.original = gesture.delegate
                gate.allowsNavigation = { [weak self] in
                    guard let self else { return false }
                    return !self.transitioning && !self.zoomSuspended && !self.parent.reduceMotion
                }
                navigationGates.append(gate)
                gesture.delegate = gate
                if let pan = gesture as? UIPanGestureRecognizer {
                    pan.maximumNumberOfTouches = 1
                    pan.addTarget(self, action: #selector(nativePanChanged(_:)))
                }
                if gesture is UITapGestureRecognizer { gesture.isEnabled = false }
            }
        }

        @objc private func nativePanChanged(_ gesture: UIPanGestureRecognizer) {
            guard [.ended, .cancelled, .failed].contains(gesture.state),
                  let controller = navigationController else { return }
            // Boundary pans may end without any page-transition delegate callback.
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self, let controller, !self.transitioning else { return }
                self.show(self.parent.spread, in: controller, animated: !self.parent.reduceMotion)
            }
        }

        func installReducedMotionSwipes(in controller: UIPageViewController) {
            for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(turnWithoutAnimation(_:)))
                swipe.direction = direction
                swipe.isEnabled = false
                controller.view.addGestureRecognizer(swipe)
                reducedMotionSwipes.append(swipe)
            }
        }

        @objc private func turnWithoutAnimation(_ gesture: UISwipeGestureRecognizer) {
            guard parent.reduceMotion, !transitioning, !zoomSuspended else { return }
            let next = parent.spread + (gesture.direction == .left ? 1 : -1)
            guard (0..<parent.spreadCount).contains(next) else { return }
            parent.spread = next
        }

        func updateMotionPolicy(in controller: UIPageViewController) {
            // Keep the data source stable even while UIKit is preparing a pan.
            // Navigation gates reject new gestures without cancelling an active curl.
            if controller.dataSource !== self { controller.dataSource = self }
            installNavigationGates(in: controller)
            reducedMotionSwipes.forEach {
                $0.isEnabled = parent.reduceMotion && !zoomSuspended && !transitioning
            }
        }

        func setZoomSuspended(_ suspended: Bool, in controller: UIPageViewController) {
            if suspended { presentReading(in: controller, animated: false) }
            zoomSuspended = suspended
            updateMotionPolicy(in: controller)
        }
        private let rings = UIHostingController(rootView: DiaryBindingRings())

        func installRings(in controller: UIPageViewController) {
            controller.addChild(rings)
            rings.safeAreaRegions = []
            rings.view.backgroundColor = .clear
            rings.view.isUserInteractionEnabled = false
            rings.view.accessibilityElementsHidden = true
            rings.view.frame = controller.view.bounds
            rings.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            controller.view.addSubview(rings.view)
            rings.didMove(toParent: controller)
            updateBindingVisibility()
        }

        func updateBindingVisibility() {
            setRingsVisible(!transitioning, animated: false)
        }

        private func setRingsVisible(_ visible: Bool, animated: Bool) {
            // 直接修改独立装订层，不触发 SwiftUI 更新或重建卷页控制器。
            UIView.animate(withDuration: animated ? (visible ? 0.18 : 0.08) : 0,
                           delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.rings.view.alpha = visible && self.parent.showsBinding ? 1 : 0
            }
        }
        init(_ parent: DiaryPageCurlReader) {
            self.parent = parent
            self.pageSource = parent
        }

        func page(_ index: Int) -> UIViewController? {
            // A mid-spine controller must always start with two leaves, even for an empty book.
            guard (0..<(max(1, pageSource.spreadCount) * 2)).contains(index) else { return nil }
            if let paper = papers[index] { return paper }
            let paper = pageSource.makePaper(index) { [weak self] in self?.transitioning == false && self?.parent.allowsPageActions == true }
            papers[index] = paper
            (paper as? DiaryPaperController)?.prepareReading()
            return paper
        }
        func show(_ requested: Int, in controller: UIPageViewController, animated: Bool) {
            guard !transitioning, !hasActiveGesture(in: controller) else { return }
            let countChanged = pageSource.spreadCount != parent.spreadCount || pageSource.allowsPageActions != parent.allowsPageActions || pageSource.showsBinding != parent.showsBinding
            pageSource = parent
            if countChanged { papers.removeAll() }
            let target = min(max(requested, 0), max(1, pageSource.spreadCount) - 1)
            guard target != displayed || countChanged else {
                updateMotionPolicy(in: controller)
                return
            }
            guard let left = page(target * 2), let right = page(target * 2 + 1) else { return }
            let direction: UIPageViewController.NavigationDirection = target >= displayed ? .forward : .reverse
            prepareReading()
            transitioning = true
            // The gesture gate rejects new pans while this transition is running.
            updateMotionPolicy(in: controller)
            // Refreshing read-only paper views during rotation is not a page turn.
            let animateTurn = animated && target != displayed
            if animateTurn { setRingsVisible(false, animated: false) }
            controller.setViewControllers([left, right], direction: direction, animated: animateTurn) { [weak self, weak controller] finished in
                // UIKit is still unwinding its transition inside this callback.
                // Keep the lock until the next main-queue turn before starting another curl.
                DispatchQueue.main.async {
                    guard let self, let controller else { return }
                    if finished { self.displayed = target }
                    self.transitioning = false
                    self.show(self.parent.spread, in: controller, animated: !self.parent.reduceMotion)
                    self.restoreAfterTransition(in: controller)
                    self.presentReading(in: controller, animated: finished)
                }
            }
        }

        private func prepareReading() {
            readingTask?.cancel()
            for paper in papers.values { (paper as? DiaryPaperController)?.prepareReading() }
        }
        private func presentReading(in controller: UIPageViewController, animated: Bool) {
            guard !transitioning else { return }
            readingTask?.cancel()
            let visible = (controller.viewControllers ?? []).compactMap { $0 as? DiaryPaperController }
            guard animated && !parent.reduceMotion && UserDefaults.standard.bool(forKey: "diary.reader.animation") else {
                visible.forEach { $0.finishReading() }; return
            }
            visible.forEach { $0.prepareReading() }
            readingTask = Task { @MainActor [weak self, weak controller] in
                for paper in visible { await paper.prepareSource() }
                guard !Task.isCancelled, let self, let controller, !self.transitioning,
                      controller.viewControllers?.compactMap({ ($0 as? DiaryPaperController)?.index }) == visible.map(\.index) else { return }
                let start = CACurrentMediaTime() + 0.15
                visible.forEach { $0.playReading(at: start) }
            }
        }
        private func restoreAfterTransition(in controller: UIPageViewController) {
            guard !transitioning else { return }
            if let indices = controller.viewControllers?.compactMap({ ($0 as? any DiaryIndexedPaper)?.index }),
               let first = indices.min(), let last = indices.max() {
                papers = papers.filter { (first - 2...last + 2).contains($0.key) }
            }
            updateMotionPolicy(in: controller)
            controller.view.bringSubviewToFront(rings.view)
            setRingsVisible(true, animated: !parent.reduceMotion)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let paper = viewController as? any DiaryIndexedPaper else { return nil }
            return page(paper.index - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let paper = viewController as? any DiaryIndexedPaper else { return nil }
            return page(paper.index + 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            prepareReading()
            transitioning = true
            setRingsVisible(false, animated: !parent.reduceMotion)
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            DispatchQueue.main.async { [weak self, weak pageViewController] in
                guard let self, let pageViewController else { return }
                let requested = self.parent.spread
                let old = self.displayed
                if let first = pageViewController.viewControllers?.compactMap({ ($0 as? any DiaryIndexedPaper)?.index }).min() {
                    self.displayed = first / 2
                }
                self.transitioning = false
                if requested != old {
                    self.show(requested, in: pageViewController, animated: !self.parent.reduceMotion)
                } else {
                    // Rotation may remove the add spread while a native curl is finishing.
                    self.parent.spread = min(max(self.displayed, 0), max(self.parent.spreadCount - 1, 0))
                    self.show(self.parent.spread, in: pageViewController, animated: false)
                }
                self.restoreAfterTransition(in: pageViewController)
                self.presentReading(in: pageViewController, animated: completed)
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            .mid
        }
    }
}

/// 每次只加载 UIKit 请求的相邻页；复用现有带版本号的预览缓存，不解码整本原图。
@MainActor private final class DiaryPaperController: UIHostingController<DiaryBookPaper>, UIPopoverPresentationControllerDelegate, DiaryIndexedPaper {
    let index: Int
    private let canSelect: () -> Bool
    let playback = DiaryReadingPlayback()
    private let readingStore: DiaryDocumentStore
    private let selectedPage: DiaryPageEntry?
    private let onSelect: (DiaryPageEntry) -> Void
    private let onAdd: (DiaryReaderAddAction) -> Void
    init(index: Int, page: DiaryPageEntry?, continuousSpread: Bool, splitHalf: Bool?, store: DiaryDocumentStore, plainPaper: Bool, showsAddPlaceholder: Bool, canSelect: @escaping () -> Bool, onAdd: @escaping (DiaryReaderAddAction) -> Void, onSelect: @escaping (DiaryPageEntry) -> Void) {
        self.index = index
        self.canSelect = canSelect
        self.readingStore = store
        self.selectedPage = page
        self.onSelect = onSelect
        self.onAdd = onAdd
        super.init(rootView: DiaryBookPaper(page: page, store: store, left: index.isMultiple(of: 2), insideCover: index == 0, coverSlot: index == 1, splitHalf: splitHalf, showsAddPlaceholder: showsAddPlaceholder, plainPaper: plainPaper, playback: playback))
        view.backgroundColor = .clear
        safeAreaRegions = []
        if showsAddPlaceholder && (page != nil || index > 0) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(selectPage(_:)))
            view.addGestureRecognizer(tap)
            view.accessibilityHint = page == nil ? (index == 1 ? "轻点添加封面" : "轻点添加页面") : "轻点编辑这一页"
        }
    }
    private func updateReadingSurface() {
        func visit(_ view: UIView) {
            if let surface = view as? any DiaryReadingSurfaceControlling {
                surface.update(phase: playback.phase, began: playback.began)
                // UIKit may snapshot the leaf before SwiftUI delivers its next update.
                view.layer.displayIfNeeded()
            }
            view.subviews.forEach(visit)
        }
        if let view = viewIfLoaded { visit(view) }
    }
    func prepareSource() async {
        guard UserDefaults.standard.bool(forKey: "diary.reader.animation") else { return }
        if let selectedPage { _ = try? await DiaryReadingSources.load(page: selectedPage, store: readingStore) }
        // Let the hosting view install its source-backed surface before starting both leaves.
        await Task.yield()
    }
    func prepareReading() { playback.prepare(); updateReadingSurface() }
    func playReading(at time: CFTimeInterval) { playback.play(at: time); updateReadingSurface() }
    func finishReading() { playback.finish(); updateReadingSurface() }
    @objc private func selectPage(_ gesture: UITapGestureRecognizer) {
        guard canSelect() else { return }
        finishReading()
        if let selectedPage { onSelect(selectedPage) }
        else if index == 1 { onAdd(.cover) }
        else if index > 0 { showAddMenu(at: gesture.location(in: view)) }
    }
    private func showAddMenu(at point: CGPoint) {
        guard presentedViewController == nil, view.window != nil else { return }
        let menu = UIAlertController(title: "添加页面", message: nil, preferredStyle: .actionSheet)
        for (title, action) in [("空白页", DiaryReaderAddAction.blank), ("从照片新建", .photo), ("从预设选择", .preset)] {
            menu.addAction(UIAlertAction(title: title, style: .default) { [weak self, weak menu] _ in
                // Finish dismissing the native menu before presenting a photo picker or sheet.
                guard let self else { return }
                if let menu, menu.presentingViewController != nil {
                    menu.dismiss(animated: true) { self.onAdd(action) }
                } else { self.onAdd(action) }
            })
        }
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        menu.modalPresentationStyle = .popover
        if let popover = menu.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
            popover.permittedArrowDirections = .any
            popover.delegate = self
        }
        present(menu, animated: true)
    }
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("不支持 Storyboard") }
}

private struct DiaryBookPaper: View {
    @AppStorage("diary.reader.animation") private var readingAnimation = true
    let page: DiaryPageEntry?
    let store: DiaryDocumentStore
    let left: Bool
    let insideCover: Bool
    let coverSlot: Bool
    let splitHalf: Bool?
    let showsAddPlaceholder: Bool
    let plainPaper: Bool
    @ObservedObject var playback: DiaryReadingPlayback
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if insideCover {
                DiaryBookLining()
                    .accessibilityLabel("内封皮")
            } else if let page {
                if readingAnimation {
                    DiaryAnimatedReadingPage(page: page, store: store, half: splitHalf, playback: playback)
                } else if let splitHalf {
                    DiarySpreadHalfPreview(page: page, store: store, left: splitHalf)
                } else {
                    DiaryPagePreview(page: page, store: store, large: true, undecorated: true)
                }
            } else if showsAddPlaceholder {
                Label(coverSlot ? "添加封面" : "添加页面", systemImage: "plus.circle").font(.caption).foregroundStyle(.brown.opacity(0.5))
            }
            HStack(spacing: 0) {
                if left { Spacer(minLength: 0) }
                LinearGradient(colors: [.black.opacity(plainPaper ? 0.10 : 0.16), .clear], startPoint: left ? .trailing : .leading, endPoint: left ? .leading : .trailing)
                    .frame(width: plainPaper ? 8 : 18)
                if !left { Spacer(minLength: 0) }
            }.allowsHitTesting(false)
        }
        .frame(width: geometry.size.width * (1 - DiaryBookSpine.halfGapFraction), height: geometry.size.height)
        // 只裁每张纸的外侧两角；卷页容器不加蒙版，保留 UIKit 卷曲与投影。
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: plainPaper && left ? DiaryBookStageLayout.paperCornerRadius : 0,
            bottomLeadingRadius: plainPaper && left ? DiaryBookStageLayout.paperCornerRadius : 0,
            bottomTrailingRadius: plainPaper && !left ? DiaryBookStageLayout.paperCornerRadius : 0,
            topTrailingRadius: plainPaper && !left ? DiaryBookStageLayout.paperCornerRadius : 0,
            style: .continuous))
        .shadow(color: .black.opacity(plainPaper ? 0 : 0.35), radius: 1.5, x: left ? 1.5 : -1.5)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: left ? .leading : .trailing)
        }
    }
}

/// 同一完整文档只读裁切；左右半页共用版本与预览缓存。
private struct DiarySpreadHalfPreview: View {
    let page: DiaryPageEntry
    let store: DiaryDocumentStore
    let left: Bool
    var body: some View {
        GeometryReader { geometry in
            DiaryPagePreview(page: page, store: store, large: true, undecorated: true)
                .frame(width: geometry.size.width * 2, height: geometry.size.height)
                .offset(x: left ? 0 : -geometry.size.width)
        }.clipped()
    }
}

/// 单页保持完整；只有完整跨页比例生成两个裁切投影。
private struct DiaryReadingLeaf {
    let page: DiaryPageEntry?
    let left: Bool?
    static func project(_ book: DiaryBook) -> [Self] {
        book.readingSpreads.flatMap { pair in
            if let page = pair[0], page.canvasLayout == .spread {
                return [Self(page: page, left: true), Self(page: page, left: false)]
            }
            return pair.map { Self(page: $0, left: nil) }
        }
    }
}
