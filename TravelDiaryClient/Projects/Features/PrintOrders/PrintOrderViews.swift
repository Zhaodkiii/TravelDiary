import SwiftUI
import PDFKit

struct PrintCheckoutScreen: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    var revisionOrder: PrintOrder? = nil
    @Environment(\.dismiss) private var dismiss
    private enum Route: Hashable { case preview, checkout, submission(UUID) }
    @State private var path: [Route] = []
    @State private var revisions: [PrintOrder] = []
    @State private var reviseSelection: PrintOrder?
    @State private var products: [PrintProduct] = []
    @State private var productID = ""
    @State private var prepared: PrintPrepared?
    @State private var address = PrintAddress()
    @State private var quantity = 1
    @State private var quote: PrintQuote?
    @State private var confirmed = false
    @State private var progressivePreview: PrintProgressivePreviewItem?
    @State private var preview: PrintPreviewItem?
    @State private var busy = false
    @State private var error: String?
    @State private var previewPages: [UUID: URL] = [:]
    @State private var preparationDirectory: URL?
    @State private var preparationDone = 0
    @State private var preparationTotal = 0
    @State private var jobID: UUID?
    @State private var submissionKey = UUID()
    private let service = PrintOrderService.shared
    private let ink = Color(red: 0.23, green: 0.36, blue: 0.31)
    private var product: PrintProduct? { products.first { $0.id == productID } }
    private var quoteKey: String { "\(productID)|\(quantity)|\(address.region)|\(prepared?.directory.lastPathComponent ?? "")" }
    private var mappingError: String? {
        guard let product else { return nil }
        do { _ = try DiaryBookPrintExporter.mapping(book: book, product: product); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack(path: $path) {
            specification
                .navigationTitle(revisionOrder == nil ? "装订成册" : "修改重提")
                .safeAreaInset(edge: .bottom) {
                    action("下一步 · 预览成品", disabled: product == nil || mappingError != nil) {
                        error = nil; path.append(.preview)
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .preview:
                        previewPage.navigationTitle("预览成品")
                            .navigationBarBackButtonHidden(busy)
                            .safeAreaInset(edge: .bottom) {
                                previewFooter
                            }
                            .task { if prepared == nil { await prepare() } }
                    case .checkout:
                        checkout.navigationTitle("确认订单")
                            .navigationBarBackButtonHidden(busy)
                            .safeAreaInset(edge: .bottom) {
                                action(submitTitle, disabled: !confirmed || !address.complete || quote == nil || busy || jobID != nil) {
                                    if let prepared { submit(prepared) }
                                }
                            }
                            .task(id: quoteKey) { await calculate() }
                    case .submission(let id):
                        PrintUploadScreen(id: id, owner: store.ownerID, onClose: { dismiss() })
                            .navigationBarBackButtonHidden(true)
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(jobID == nil ? "关闭" : "完成") { dismiss() }.disabled(busy) } }
        }
        .tint(ink)
        .interactiveDismissDisabled(busy)
        .sheet(item: $preview) { PrintPDFPreview(item: $0) }
        .sheet(item: $progressivePreview) { PrintProgressivePreview(item: $0) }
        .sheet(item: $reviseSelection) { PrintCheckoutScreen(book: book, store: store, revisionOrder: $0) }
        .task { await load() }
        .onChange(of: productID) { _, _ in
            invalidate()
            if revisionOrder == nil { quantity = 1; if !(product?.regions.contains(address.region) ?? false) { address.region = "" } }
        }
        .onChange(of: path) { _, _ in error = nil }
        .onChange(of: quantity) { _, _ in quote = nil; confirmed = false }
        .onChange(of: address.region) { _, _ in quote = nil; confirmed = false }
        .onDisappear { if jobID == nil { invalidate() } }
    }

    private var specification: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                steps(1)
                Text(book.title).font(.title2.bold())
                Text("把亲手制作的回忆，印成可以珍藏的一本。").foregroundStyle(.secondary)
                if let revisionOrder {
                    GroupBox("修改原订单 · \(revisionOrder.number)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(revisionOrder.exception_reason).foregroundStyle(.orange)
                            Text("保留原规格、份数、地址及 \(revisionOrder.page_count) 面内页，无需重复付款。请先在作品中完成修改。").font(.footnote)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(products) { item in
                    Button {
                        guard revisionOrder == nil else { return }; productID = item.id
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: productID == item.id ? "largecircle.fill.circle" : "circle").foregroundStyle(ink)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(item.title).font(.headline); Spacer(); Text(item.free_printing == true ? "印制免费" : "按页计费").font(.caption).foregroundStyle(ink) }
                                Text("\(item.width_mm) × \(item.height_mm) mm · \(item.paper) · \(item.binding)").font(.subheadline)
                                Text("内页\(item.duplex ? "双面" : "单面")印刷 · \(item.min_pages)–\(item.max_pages) 面").font(.footnote).foregroundStyle(.secondary)
                                Text(item.shipping_fen == 0 ? "免运费" : "每单运费 \(PrintText.money(item.shipping_fen))").font(.footnote)
                                if !item.description.isEmpty { Text(item.description).font(.footnote).foregroundStyle(.secondary) }
                                if !item.lead_time.isEmpty { Text(item.lead_time).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(productID == item.id ? ink : Color.secondary.opacity(0.2), lineWidth: productID == item.id ? 2 : 1))
                    }.buttonStyle(.plain)
                }
                if let product {
                    Stepper("印制 \(quantity) 份", value: $quantity, in: 1...max(product.max_quantity, 1)).disabled(revisionOrder != nil)
                    if let map = try? DiaryBookPrintExporter.mapping(book: book, product: product) {
                        Text("\(map.cover.isEmpty ? "无外壳" : "外壳 1 面") · 内页 \(map.count) 面 · 每份 \(product.duplex ? map.count / 2 : map.count) 张内页纸").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Text("全部内容页按作品排序连续印制。有外壳时，外壳放在最前面；皮革边框与装订环仅用于预览。").font(.footnote).foregroundStyle(.secondary)
                if let mappingError { Text(mappingError).font(.subheadline).foregroundStyle(.red) }
                if products.isEmpty && !busy && error == nil { ContentUnavailableView("印制服务准备中", systemImage: "book.closed", description: Text("目前没有已开放的规格，请稍后再来。")) }
                if busy { ProgressView("正在加载规格…") }
                errorMessage
                if error != nil { Button("重新加载") { Task { await load() } } }
                if revisionOrder == nil && !revisions.isEmpty {
                    GroupBox("有订单需要修改重提") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(revisions) { item in Button { reviseSelection = item } label: { Text("\(item.title) · \(item.spec.title)\n\(item.exception_reason)").multilineTextAlignment(.leading) } }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                NavigationLink("我的印制订单") { PrintOrdersScreen(owner: store.ownerID) }
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
    }

    private var previewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                steps(2)
                Text("按作品顺序，装订成一本").font(.title2.bold())
                Text("有外壳时先显示外壳，其余页面按作品顺序展示。已生成的跨页可随时点击放大检查。").font(.subheadline).foregroundStyle(.secondary)
                if !previewPages.isEmpty {
                    PrintProductionPreview(book: book, pageSize: CGSize(width: product?.width_mm ?? 148, height: product?.height_mm ?? 210), thumbnails: previewPages) { role, title, left, right in
                        guard let directory = prepared?.directory ?? preparationDirectory else { return }
                        let pages = book.contentPages
                        func pageURL(_ index: Int?) -> URL? {
                            guard let index, pages.indices.contains(index) else { return nil }
                            return directory.appendingPathComponent("page-\(pages[index].id).pdf")
                        }
                        let shellURL = book.shell.map { directory.appendingPathComponent("page-\($0.id).pdf") }
                        progressivePreview = PrintProgressivePreviewItem(title: title,
                            left: role == "cover" ? shellURL : pageURL(left), right: role == "cover" ? nil : pageURL(right),
                            isSpread: role != "cover", lining: left == nil,
                            pageSize: CGSize(width: product?.width_mm ?? 148, height: product?.height_mm ?? 210))
                    }
                }
                if let prepared {
                    Button("查看完整印制内页 · \(prepared.pageCount) 面") {
                        preview = PrintPreviewItem(url: prepared.directory.appendingPathComponent("interior.pdf"), title: "全部印制内页")
                    }.font(.subheadline)
                    ForEach(Array(prepared.warnings.enumerated()), id: \.offset) { _, warning in Label(warning, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange) }
                    Text("请检查文字、照片、页序及装订边。皮革外沿与装订环仅展示装订效果；无额外出血，重要内容请避开裁切和装订位置。").font(.footnote).foregroundStyle(.secondary)
                }
                errorMessage
                if error != nil && !busy { Button("重新生成预览") { Task { await prepare() } } }
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
    }

    private var previewFooter: some View {
        Button {
            guard prepared != nil, !busy else { return }
            error = nil; path.append(.checkout)
        } label: {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.white).controlSize(.small) }
                Text(busy ? (preparationDone == preparationTotal && preparationTotal > 0 ? "正在完成文件检查…" : "正在准备成品 \(preparationDone)/\(preparationTotal)") : "确认成品 · 下一步")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity).padding(16)
            .foregroundStyle(.white)
            .background {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        ink.opacity(busy ? 0.45 : 1)
                        if busy {
                            ink.frame(width: geometry.size.width * CGFloat(preparationDone) / CGFloat(max(preparationTotal, 1)))
                        }
                    }
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(prepared == nil || busy)
        .accessibilityLabel(busy ? "成品准备进度，\(preparationDone)，共 \(preparationTotal) 页" : "确认成品，下一步")
        .padding().background(.regularMaterial)
    }

    private var checkout: some View {
        Form {
            Section { steps(3) }
            Section("收货地址") {
                TextField("收件人", text: $address.name).textContentType(.name).onChange(of: address.name) { _, _ in confirmed = false }
                TextField("手机号", text: $address.phone).keyboardType(.phonePad).textContentType(.telephoneNumber).onChange(of: address.phone) { _, _ in confirmed = false }
                Picker("配送地区", selection: $address.region) {
                    Text("请选择").tag("")
                    ForEach(product?.regions ?? [], id: \.self) { Text($0).tag($0) }
                }
                TextField("街道、门牌号等详细地址", text: $address.detail, axis: .vertical).textContentType(.fullStreetAddress).onChange(of: address.detail) { _, _ in confirmed = false }
            }.disabled(revisionOrder != nil)
            if let product, let prepared {
                Section("印制内容") {
                    LabeledContent("作品", value: book.title)
                    LabeledContent("规格", value: "\(product.title) · \(product.width_mm) × \(product.height_mm) mm")
                    LabeledContent("纸张 / 装订", value: "\(product.paper) / \(product.binding)")
                    LabeledContent("数量", value: "\(quantity) 份")
                    LabeledContent("外壳", value: book.shell == nil ? "未设置" : "1 面，位于内容页之前")
                    LabeledContent("内页", value: "\(prepared.pageCount) 面 · 每份 \(product.duplex ? prepared.pageCount / 2 : prepared.pageCount) 张纸")
                    if !product.lead_time.isEmpty { Text(product.lead_time).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("费用") {
                    if let quote {
                        LabeledContent("印制费", value: PrintText.money(quote.production_fen))
                        LabeledContent("运费", value: PrintText.money(quote.shipping_fen))
                        LabeledContent("实付", value: quote.total_fen == 0 ? "免费 · ¥0.00" : PrintText.money(quote.total_fen)).font(.headline)
                    } else if busy { ProgressView("正在确认费用…") }
                    else { Text("请选择配送地区，以确认费用。").foregroundStyle(.secondary) }
                    errorMessage
                    if error != nil { Button("重试确认费用") { Task { await calculate() } }.disabled(busy) }
                }
                Section("购买与售后") {
                    Text(product.terms).font(.footnote).foregroundStyle(.secondary)
                    Toggle("我已检查成品预览，并同意购买及售后说明", isOn: $confirmed)
                    Text(revisionOrder != nil ? "新稿替换当前生产稿，保留原订单及付款信息。" : "上传完成后，免费订单直接进入人工审核；收费订单需完成微信支付。").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var submitTitle: String {
        if revisionOrder != nil { return "替换生产稿并重新提交" }
        guard let quote else { return "确认配送地区后提交" }
        return quote.total_fen == 0 ? "提交免费印制订单" : "提交订单 · \(PrintText.money(quote.total_fen))"
    }
    private func steps(_ current: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(["选择规格", "预览成品", "确认订单"].enumerated()), id: \.offset) { index, title in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Text("\(index + 1) \(title)").font(.caption.weight(current == index + 1 ? .semibold : .regular)).foregroundStyle(current == index + 1 ? ink : .secondary)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("第 \(current) 步，共 3 步")
    }
    @ViewBuilder private var errorMessage: some View { if let error { Text(error).foregroundStyle(.red).font(.subheadline) } }
    private func action(_ title: String, disabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.headline).frame(maxWidth: .infinity).padding(12) }
            .buttonStyle(.borderedProminent).disabled(disabled || busy).padding().background(.regularMaterial)
    }
    private func invalidate() {
        if let directory = prepared?.directory ?? preparationDirectory { try? FileManager.default.removeItem(at: directory) }
        prepared = nil; preparationDirectory = nil; previewPages = [:]
        preparationDone = 0; preparationTotal = 0
        confirmed = false; quote = nil
    }
    private func load() async {
        busy = true; error = nil; defer { busy = false }
        do {
            if let revisionOrder {
                products = [revisionOrder.spec]; productID = revisionOrder.spec.id; quantity = revisionOrder.quantity; address = revisionOrder.address
            } else {
                products = try await service.products(owner: store.ownerID)
                if !products.contains(where: { $0.id == productID }) {
                    productID = products.min { left, right in
                        let size = book.contentPages.first?.size ?? book.defaultPageSize
                        return DiaryBookPrintExporter.proportionDifference(size, product: left) < DiaryBookPrintExporter.proportionDifference(size, product: right)
                    }?.id ?? ""
                }
                revisions = try await service.revisionOrders(bookID: book.id, owner: store.ownerID)
                if address.name.isEmpty, let last = try? await service.orders(owner: store.ownerID, offset: 0).results.first {
                    address = last.address
                    if !(product?.regions.contains(address.region) ?? false) { address.region = "" }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func prepare() async {
        guard let product, !busy else { return }
        invalidate(); busy = true; error = nil
        preparationTotal = book.contentPages.count + (book.shell == nil ? 0 : 1)
        defer { busy = false }
        var dir: URL?
        do {
            try service.requireOwner(store.ownerID, bound: true)
            let directory = try service.draftDirectory(owner: store.ownerID); dir = directory; preparationDirectory = directory
            let result = try await DiaryBookPrintExporter.prepare(book: book, store: store, product: product, directory: directory,
                onPageReady: { pageID, thumbnail in previewPages[pageID] = thumbnail }) { done, total in
                    preparationDone = done; preparationTotal = total
                }
            try Task.checkCancellation()
            if let revisionOrder, result.pageCount != revisionOrder.page_count { throw PrintFailure("重提需保持 \(revisionOrder.page_count) 面内页，当前为 \(result.pageCount) 面，请返回作品调整。") }
            prepared = result
        } catch {
            if let dir { try? FileManager.default.removeItem(at: dir) }
            previewPages = [:]; preparationDirectory = nil; preparationDone = 0
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
    private func calculate() async {
        guard let product, let prepared, !address.region.isEmpty else { quote = nil; return }
        let key = quoteKey
        busy = true; error = nil; defer { busy = false }
        do {
            let result: PrintQuote
            if let revisionOrder {
                result = PrintQuote(total_fen: revisionOrder.total_fen, production_fen: revisionOrder.total_fen - product.shipping_fen, shipping_fen: product.shipping_fen, page_count: prepared.pageCount, sheets: product.duplex ? prepared.pageCount/2 : prepared.pageCount, product_revision: product.revision)
            } else { result = try await service.quote(product: product, pages: prepared.pageCount, quantity: quantity, address: address, owner: store.ownerID) }
            try Task.checkCancellation()
            guard key == quoteKey else { return }
            guard result.product_revision == product.revision else { throw PrintFailure("规格已更新，请关闭并重新打开印制页面") }
            quote = result
        } catch { if key == quoteKey && !(error is CancellationError) { self.error = error.localizedDescription; quote = nil } }
    }
    private func submit(_ prepared: PrintPrepared) {
        guard let product, let quote, confirmed, address.complete, jobID == nil else { return }
        do {
            let submission = PrintSubmission(key: submissionKey, product_id: product.id, product_revision: product.revision,
                title: book.title, quantity: quantity, page_count: prepared.pageCount, address: address.trimmed,
                snapshot: prepared.snapshot, files: prepared.files, confirmed: true, quote_total_fen: quote.total_fen, revise_order_id: revisionOrder?.id, order_revision: revisionOrder?.revision)
            let id = try service.enqueue(submission, directory: prepared.directory, owner: store.ownerID)
            jobID = id; path.append(.submission(id))
        } catch { self.error = error.localizedDescription }
    }
}

private struct PrintProductionPreview: View {
    let book: DiaryBook
    let pageSize: CGSize
    let thumbnails: [UUID: URL]
    let open: (String, String, Int?, Int?) -> Void
    private var aspect: CGFloat {
        2 / (0.955 * (1 - DiaryBookSpine.halfGapFraction) * pageSize.height / max(pageSize.width, 1) + 0.09)
    }
    private var spreads: [[DiaryPageEntry?]] { DiaryBookImageExporter.spreadPages(book) }
    private var readySpreads: [Int] {
        DiaryBookPrintExporter.readySpreads(book: book, readyPageIDs: Set(thumbnails.keys))
    }
    private func index(_ page: DiaryPageEntry?) -> Int? {
        guard let page else { return nil }
        return book.contentPages.firstIndex { $0.id == page.id }
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            if let shell = book.shell, let url = thumbnails[shell.id] {
                Button { open("cover", "外壳", 0, nil) } label: {
                    VStack(spacing: 8) {
                        PrintPreparedThumbnail(url: url).frame(maxWidth: .infinity).aspectRatio(aspect, contentMode: .fit)
                        Text("外壳").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(readySpreads, id: \.self) { spread in
                let pair = spreads[spread]
                let left = index(pair[0])
                let right = index(pair[1])
                Button { open("interior", "内容页", left, right) } label: {
                    VStack(spacing: 8) {
                        PrintPreparedSpread(left: pair[0].flatMap { thumbnails[$0.id] }, right: pair[1].flatMap { thumbnails[$0.id] }, lining: spread == 0)
                            .aspectRatio(aspect, contentMode: .fit)
                        Text("第 " + [left, right].compactMap { $0.map { String($0 + 1) } }.joined(separator: "–") + " 页")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.buttonStyle(.plain)
    }
}

private enum PrintPreviewImageLoader {
    nonisolated static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
        return Task.isCancelled ? nil : image
    }
}

private struct PrintPreparedSpread: View {
    let left: URL?
    let right: URL?
    let lining: Bool
    @State private var leftImage: UIImage?
    @State private var rightImage: UIImage?
    var body: some View {
        DiaryExportSpread(left: leftImage, right: rightImage, lining: lining)
            .task(id: left) { leftImage = await PrintPreviewImageLoader.load(left) }
            .task(id: right) { rightImage = await PrintPreviewImageLoader.load(right) }
    }
}

private struct PrintPreparedThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Color.clear }
        }.task(id: url) { image = await PrintPreviewImageLoader.load(url) }
    }
}

private struct PrintBoundPDFSpread: View {
    let left: PDFPage?
    let right: PDFPage?
    let lining: Bool
    var thumbnailSize = CGSize(width: 300, height: 440)
    @State private var leftImage: UIImage?
    @State private var rightImage: UIImage?
    var body: some View {
        DiaryExportSpread(left: leftImage, right: rightImage, lining: lining)
            .task(id: left) { leftImage = left?.thumbnail(of: thumbnailSize, for: .mediaBox) }
            .task(id: right) { rightImage = right?.thumbnail(of: thumbnailSize, for: .mediaBox) }
    }
}

private struct PrintProgressivePreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let left: URL?
    let right: URL?
    let isSpread: Bool
    let lining: Bool
    let pageSize: CGSize
}

private struct PrintProgressivePreview: View {
    let item: PrintProgressivePreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var left: UIImage?
    @State private var right: UIImage?
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let aspect = 2 / (0.955 * (1 - DiaryBookSpine.halfGapFraction) * item.pageSize.height / max(item.pageSize.width, 1) + 0.09)
                DiaryBookZoomViewport(contentSize: geometry.size, resetToken: 0) {
                    Group {
                        if item.isSpread { DiaryExportSpread(left: left, right: right, lining: item.lining).aspectRatio(aspect, contentMode: .fit) }
                        else if let left { Image(uiImage: left).resizable().scaledToFit() }
                        else { ProgressView() }
                    }.padding(12).frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task {
                let urls = (item.left, item.right)
                let result = await Task.detached(priority: .userInitiated) {
                    func image(_ url: URL?) -> UIImage? {
                        guard let url else { return nil }
                        return autoreleasepool { PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 1400, height: 2000), for: .mediaBox) }
                    }
                    return (image(urls.0), image(urls.1))
                }.value
                guard !Task.isCancelled else { return }
                left = result.0; right = result.1
            }
        }
    }
}

struct PrintPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String; var pageIndex: Int = 0; var isSpread = false; var leftPageIndex: Int? = nil; var rightPageIndex: Int? = nil }
private struct PrintPDFPreview: View {
    let item: PrintPreviewItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { Group {
            if item.isSpread { PrintEnlargedSpread(item: item) }
            else { PrintPDFView(url: item.url, pageIndex: item.pageIndex) }
        }.navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
    }
}
private struct PrintEnlargedSpread: View {
    let item: PrintPreviewItem
    @State private var document: PDFDocument?
    var body: some View {
        GeometryReader { geometry in
            let size = document?.page(at: 0)?.bounds(for: .mediaBox).size ?? CGSize(width: 148, height: 210)
            let aspect = 2 / (0.955 * (1 - DiaryBookSpine.halfGapFraction) * size.height / max(size.width, 1) + 0.09)
            DiaryBookZoomViewport(contentSize: geometry.size, resetToken: 0) {
                PrintBoundPDFSpread(left: item.leftPageIndex.flatMap { document?.page(at: $0) },
                                    right: item.rightPageIndex.flatMap { document?.page(at: $0) }, lining: item.leftPageIndex == nil, thumbnailSize: CGSize(width: 1400, height: 2000))
                    .aspectRatio(aspect, contentMode: .fit).padding(12)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }.task { document = PDFDocument(url: item.url) }
    }
}

private struct PrintPDFView: UIViewRepresentable {
    let url: URL
    var pageIndex: Int = 0
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.document = PDFDocument(url: url); view.autoScales = true; view.displayMode = .singlePageContinuous; if let page = view.document?.page(at: pageIndex) { view.go(to: page) }; return view }
    func updateUIView(_ uiView: PDFView, context: Context) { }
}

struct PrintUploadScreen: View {
    let id: UUID
    let owner: String
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = PrintOrderService.shared
    @State private var latestOrder: PrintOrder?
    @State private var refreshError: String?
    private var job: PrintLocalJob? { service.jobs.first { $0.id == id && $0.owner == owner } }
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
    var body: some View {
        List {
            if let job {
                Section {
                    Label(job.state == "已上传" ? "订单已提交" : "正在提交印制", systemImage: job.state == "已上传" ? "checkmark.circle.fill" : "arrow.up.doc").font(.headline)
                    HStack {
                        Label("文件已准备", systemImage: "checkmark.circle.fill")
                        Image(systemName: "chevron.right")
                        Text(job.state == "已上传" ? "上传完成" : "上传文件")
                        Image(systemName: "chevron.right")
                        Text("提交完成").foregroundStyle(job.state == "已上传" ? .primary : .secondary)
                    }.font(.caption)
                    Text(job.submission.title).font(.headline); Text(job.state)
                    if let latestOrder, job.state == "已上传" { Text(latestOrder.statusText).foregroundStyle(.secondary) }
                    if let latestOrder, !latestOrder.production_error.isEmpty { Text(latestOrder.production_error).foregroundStyle(.red) }
                    if let refreshError { Text(refreshError).foregroundStyle(.red) }
                    if let progress = service.progress[id] { ProgressView(value: progress); Text("\(Int(progress*100))%").font(.caption) }
                    if let error = job.error { Text(error).foregroundStyle(.red) }
                    if service.isRunning(id) { Button("暂停上传") { service.pause(id) } }
                    else if job.state != "已上传" || latestOrder?.file_state == "failed" { Button(latestOrder?.file_state == "failed" ? "重新上传生产稿" : "继续上传") { latestOrder = nil; service.resume(id) } }
//                    Text("可以离开此页面，订单与上传记录已保存。系统中断后，可从“我的印制订单”继续。").font(.footnote).foregroundStyle(.secondary)
                }
                if let orderID = job.orderID { Section { NavigationLink(job.submission.quote_total_fen == 0 ? "查看免费印制订单" : "查看订单 / 微信支付") { PrintOrderDetailScreen(id: orderID, owner: owner) } } }
            } else { Text("此账号下没有该上传任务") }
        }.navigationTitle("提交印制")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(job?.state == "已上传" ? "完成" : "关闭", action: close)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: close) {
                Text(job?.state == "已上传" ? "完成并关闭" : "关闭页面")
                    .font(.headline).frame(maxWidth: .infinity).padding(12)
            }
            .buttonStyle(.borderedProminent)
            .padding().background(.regularMaterial)
        }
        .task {
            while !Task.isCancelled {
                if let orderID = job?.orderID, !service.isRunning(id) {
                    do { latestOrder = try await service.order(orderID, owner: owner); refreshError = nil }
                    catch { refreshError = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }
}

struct PrintOrdersScreen: View {
    let owner: String
    @ObservedObject private var service = PrintOrderService.shared
    @State private var orders: [PrintOrder] = []
    @State private var next: Int?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let local = service.jobs.filter { $0.owner == owner && $0.state != "已上传" }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("把旅途，装订成册").font(.title2.bold()).foregroundStyle(DiaryLibraryStyle.ink)
                    Text("查看印制进度，也可以继续完成尚未上传的生产文件。")
                        .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                }
                if !local.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("待上传 / 可恢复", detail: "\(local.count) 项")
                        ForEach(local) { job in
                            NavigationLink { PrintUploadScreen(id: job.id, owner: owner) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "arrow.up.doc").font(.title3).foregroundStyle(DiaryLibraryStyle.accent)
                                        .frame(width: 42, height: 42).background(DiaryLibraryStyle.background, in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(job.submission.title).font(.headline).foregroundStyle(DiaryLibraryStyle.ink)
                                        Text(job.state).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.secondary.opacity(0.65))
                                }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("印制订单", detail: orders.isEmpty ? nil : "\(orders.count) 笔")
                    if orders.isEmpty && !busy && error == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "book.closed").font(.title2).foregroundStyle(DiaryLibraryStyle.accent)
                            Text("还没有印制订单").font(.headline).foregroundStyle(DiaryLibraryStyle.ink)
                            Text("完成旅行手帐后，在导出页选择“装订成册”，把回忆做成一本可以珍藏的书。")
                                .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    ForEach(orders) { order in orderCard(order) }
                    if next != nil {
                        Button { Task { await load(more: true) } } label: {
                            HStack { Spacer(); if busy { ProgressView().controlSize(.small) }; Text(busy ? "正在加载…" : "加载更多订单"); Spacer() }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.accent).padding(14)
                                .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).disabled(busy)
                    }
                }
                if busy && orders.isEmpty { ProgressView("正在读取订单…").frame(maxWidth: .infinity).padding() }
                if let error {
                    DiaryLibraryNotice(message: "订单暂时无法加载：\(error)", actionTitle: "重新加载") { Task { await load() } }
                }
            }
            .frame(maxWidth: 680, alignment: .leading).padding(20).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background.ignoresSafeArea())
        .foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .navigationTitle("我的印制订单")
        .task { await load() }
        .refreshable { await load() }
    }

    private func sectionHeading(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(DiaryLibraryStyle.ink)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
        }.padding(.horizontal, 2)
    }

    private func orderCard(_ order: PrintOrder) -> some View {
        NavigationLink { PrintOrderDetailScreen(id: order.id, owner: owner) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(order.title).font(.headline).foregroundStyle(DiaryLibraryStyle.ink).lineLimit(2)
                        Text("\(order.spec.title) · \(order.quantity) 份")
                            .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                    Spacer(minLength: 4)
                    statusBadge(order.statusText, state: order.state)
                }
                Rectangle().fill(DiaryLibraryStyle.line.opacity(0.7)).frame(height: 1)
                HStack {
                    Text("订单金额").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    Spacer()
                    Text(PrintText.money(order.total_fen)).font(.subheadline.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.ink)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.secondary.opacity(0.6)).padding(.leading, 4)
                }
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func statusBadge(_ title: String, state: String) -> some View {
        let tone = orderTone(state)
        return Text(title).font(.caption.weight(.medium)).foregroundStyle(tone)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tone.opacity(0.1), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }

    private func orderTone(_ state: String) -> Color {
        switch state {
        case "completed": .green
        case "cancelled": DiaryLibraryStyle.secondary
        case "needs_revision", "exception", "failed": .orange
        case "shipped", "ready_to_ship": DiaryLibraryStyle.accent
        default: DiaryLibraryStyle.accent
        }
    }
    private func load(more: Bool = false) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { let page = try await service.orders(owner: owner, offset: more ? next ?? 0 : 0); orders = more ? orders + page.results : page.results; next = page.next_offset }
        catch { self.error = error.localizedDescription }
    }
}

struct PrintOrderDetailScreen: View {
    let id: String
    let owner: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var order: PrintOrder?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingCancel = false
    @State private var confirmingReceive = false
    @State private var revisionContext: PrintRevisionContext?
    @State private var message = ""
    @State private var actionKey = UUID()
    @State private var showingAfterSale = false
    private let service = PrintOrderService.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let order {
                    statusCard(order)
                    if order.state == "needs_revision" {
                        noticeCard(title: "修改后重新提交", message: "\(order.exception_reason)\n\n在原作品中完成修改，再重新生成生产稿。保留原订单与付款信息，无需重复下单。", symbol: "pencil.and.outline", tone: .orange) {
                            Button { Task { await openRevision(order) } } label: {
                                Label("打开原订单重提页面", systemImage: "arrow.up.right.square")
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(13)
                            }.buttonStyle(.borderedProminent).disabled(busy)
                        }
                    } else if !order.exception_reason.isEmpty {
                        noticeCard(title: "制作情况", message: order.exception_reason, symbol: "info.circle", tone: .orange)
                    }
                    if !order.production_error.isEmpty {
                        noticeCard(title: "生产文件提示", message: order.production_error, symbol: "exclamationmark.triangle", tone: .orange)
                    }
                    if !order.after_sale_state.isEmpty {
                        detailCard(title: "售后进度", symbol: "bubble.left.and.bubble.right") {
                            Text(PrintText.label(order.after_sale_state)).font(.subheadline.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.accent)
                            Text(order.after_sale_message).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                            if !order.after_sale_resolution.isEmpty { infoRow("处理结果", value: order.after_sale_resolution) }
                        }
                    }
                    if order.refund_state == "exception" {
                        noticeCard(title: "退款处理中", message: "退款暂未完成，工作人员正在核对。可通过售后联系处理。", symbol: "clock", tone: .orange)
                    }
                    detailCard(title: "印制规格", symbol: "book.closed") {
                        infoRow("成品规格", value: order.spec.title)
                        infoRow("印制数量", value: "\(order.quantity) 份")
                        infoRow("内页", value: "\(order.page_count) 面")
                        if let covers = order.cover_page_count, covers > 0 { infoRow("封面", value: "\(covers) 面") }
                        infoRow("付款状态", value: PrintText.label(order.payment_state))
                    }
                    detailCard(title: "收货与物流", symbol: "shippingbox") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(order.address.name) · \(order.address.phone)").font(.subheadline.weight(.medium)).foregroundStyle(DiaryLibraryStyle.ink)
                            Text(order.address.region + " " + order.address.detail).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).textSelection(.enabled)
                        }.padding(.vertical, 4)
                        if !order.shipments.isEmpty {
                            ForEach(order.shipments) { shipment in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "shippingbox.fill").foregroundStyle(DiaryLibraryStyle.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(shipment.kind == "reship" ? "补寄 · " : "物流单号 · ")\(shipment.carrier)").font(.subheadline.weight(.medium))
                                        Text(shipment.tracking_number).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary).textSelection(.enabled)
                                    }
                                }.padding(.top, 8)
                            }
                        } else {
                            Text("发货后，物流信息会显示在这里。") .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                        }
                    }
                    actionCard(order)
                    if order.allowed_actions.contains("after_sale") {
                        detailCard(title: "售后申请", symbol: "text.bubble") {
                            Text("描述遇到的问题，我们会根据订单进度协助处理。")
                                .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                            TextField("请描述遇到的问题", text: $message, axis: .vertical)
                                .lineLimit(3...6).padding(12).background(DiaryLibraryStyle.background, in: RoundedRectangle(cornerRadius: 12))
                            Button { Task { await act("after_sale") } } label: {
                                Text("提交售后申请").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(13)
                            }.buttonStyle(.bordered).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        }
                    }
                    timelineCard(order)
                } else if busy {
                    ProgressView("正在读取订单…").frame(maxWidth: .infinity).padding(32)
                        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                if let error {
                    DiaryLibraryNotice(message: "订单处理未完成：\(error)", actionTitle: "刷新订单") { Task { await load(payment: true) } }
                }
                if busy && order != nil { ProgressView("正在处理…").frame(maxWidth: .infinity).padding(.vertical, 4) }
            }
            .frame(maxWidth: 680, alignment: .leading).padding(20).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background.ignoresSafeArea())
        .foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .navigationTitle("订单详情")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load(payment: order?.payment_state == "unpaid" || order?.payment_state == "refund_pending") } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(DiaryLibraryStyle.accent)
                }.disabled(busy).accessibilityLabel("刷新订单")
            }
        }
        .task {
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if scenePhase == .active { await load() }
            }
        }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load(payment: true) } } }
        .onReceive(NotificationCenter.default.publisher(for: .printPaymentReturned)) { _ in Task { await load(payment: true) } }
        .sheet(item: $revisionContext, onDismiss: { Task { await load() } }) { context in
            PrintCheckoutScreen(book: context.book, store: context.store, revisionOrder: context.order)
        }
    }

    private func statusCard(_ order: PrintOrder) -> some View {
        let tone = orderTone(order.state)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: orderSymbol(order.state)).font(.subheadline.weight(.semibold))
                Text(order.statusText).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(PrintText.label(order.payment_state)).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
            }.foregroundStyle(tone)
            Text(order.title).font(.title3.bold()).foregroundStyle(DiaryLibraryStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("订单金额").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    Text(PrintText.money(order.total_fen)).font(.title2.bold()).foregroundStyle(DiaryLibraryStyle.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("订单编号").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    Text(order.number).font(.caption.monospaced()).foregroundStyle(DiaryLibraryStyle.secondary)
                        .lineLimit(1).textSelection(.enabled)
                }.frame(maxWidth: 190, alignment: .trailing)
            }
            Rectangle().fill(DiaryLibraryStyle.line.opacity(0.75)).frame(height: 1)
            Label("订单信息与进度会随印制状态更新", systemImage: "sparkle")
                .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).fill(tone).frame(width: 34, height: 4).padding(.leading, 18)
            }
    }

    private func detailCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(DiaryLibraryStyle.ink)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline).foregroundStyle(DiaryLibraryStyle.ink).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 5)
    }

    private func noticeCard<Content: View>(title: String, message: String, symbol: String, tone: Color, @ViewBuilder content: () -> Content = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(tone)
            Text(message).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).fixedSize(horizontal: false, vertical: true)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tone.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder private func actionCard(_ order: PrintOrder) -> some View {
        let local = service.jobs.first(where: { $0.orderID == id && $0.owner == owner && $0.productionID == order.production_id })
        if (order.allowed_actions.contains("upload") && local != nil) || order.allowed_actions.contains("pay") || order.allowed_actions.contains("cancel") || order.allowed_actions.contains("receive") {
            VStack(spacing: 10) {
                if order.allowed_actions.contains("pay") {
                    Button { Task { await pay() } } label: {
                        HStack { Image(systemName: "creditcard"); Text("微信支付 · \(PrintText.money(order.total_fen))") }
                            .font(.headline).frame(maxWidth: .infinity).padding(14)
                    }.buttonStyle(.borderedProminent)
                }
                if order.allowed_actions.contains("upload"), let local {
                    NavigationLink { PrintUploadScreen(id: local.id, owner: owner) } label: {
                        Label("继续上传生产文件", systemImage: "arrow.up.doc")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    if order.allowed_actions.contains("cancel") {
                        Button("取消订单", role: .destructive) { confirmingCancel = true }
                            .frame(maxWidth: .infinity).buttonStyle(.bordered)
                            .confirmationDialog("取消此印制订单？已付款订单将申请原路退款。", isPresented: $confirmingCancel, titleVisibility: .visible) {
                                Button("确认取消", role: .destructive) { Task { await act("cancel") } }
                            }
                    }
                    if order.allowed_actions.contains("receive") {
                        Button("确认收货") { confirmingReceive = true }
                            .frame(maxWidth: .infinity).buttonStyle(.bordered)
                            .confirmationDialog("确认已收到并检查此订单的全部成品？", isPresented: $confirmingReceive, titleVisibility: .visible) {
                                Button("确认收货") { Task { await act("receive") } }
                            }
                    }
                }
            }.padding(14).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18)).disabled(busy)
        }
    }

    private func timelineCard(_ order: PrintOrder) -> some View {
        detailCard(title: "订单进度", symbol: "clock.arrow.circlepath") {
            if order.events.isEmpty {
                Text("订单进度更新后会显示在这里。").font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(order.events.reversed().enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle().fill(index == 0 ? DiaryLibraryStyle.accent : DiaryLibraryStyle.line)
                                    .frame(width: 9, height: 9).padding(.top, 4)
                                if index < order.events.count - 1 {
                                    Rectangle().fill(DiaryLibraryStyle.line).frame(width: 1, height: 36)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.message).font(.subheadline).foregroundStyle(DiaryLibraryStyle.ink)
                                Text(event.created_at.replacingOccurrences(of: "T", with: " ").prefix(19))
                                    .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                            }.padding(.bottom, 12)
                        }
                    }
                }
            }
        }
    }

    private func orderTone(_ state: String) -> Color {
        switch state {
        case "completed": .green
        case "cancelled": DiaryLibraryStyle.secondary
        case "needs_revision", "exception", "failed": .orange
        case "shipped", "ready_to_ship": DiaryLibraryStyle.accent
        default: DiaryLibraryStyle.accent
        }
    }

    private func orderSymbol(_ state: String) -> String {
        switch state {
        case "completed": "checkmark.circle.fill"
        case "cancelled": "xmark.circle.fill"
        case "needs_revision", "exception", "failed": "exclamationmark.circle.fill"
        case "shipped", "ready_to_ship": "shippingbox.fill"
        default: "clock.fill"
        }
    }
    private func openRevision(_ order: PrintOrder) async {
        busy = true; error = nil; defer { busy = false }
        do {
            try service.requireOwner(owner)
            guard let bookID = UUID(uuidString: order.source_book_id) else { throw PrintFailure("无法识别原作品") }
            let store = DiaryDocumentStore(ownerID: owner, bookID: bookID)
            let book = try await store.loadBook()
            revisionContext = PrintRevisionContext(book: book, store: store, order: order)
        } catch { self.error = "无法打开本机原作品，请在保有该作品的设备上修改重提。" }
    }
    private func load(payment: Bool = false) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { order = payment ? try await service.refreshPayment(id, owner: owner) : try await service.order(id, owner: owner) }
        catch { self.error = error.localizedDescription }
    }
    private func pay() async {
        busy = true; error = nil; defer { busy = false }
        do { try await service.pay(id, owner: owner) } catch { self.error = error.localizedDescription }
    }
    private func act(_ action: String) async {
        guard let order, !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { self.order = try await service.action(action, order: order, owner: owner, message: message, key: actionKey); actionKey = UUID(); message = "" }
        catch {
            let reason = error.localizedDescription
            do {
                self.order = try await service.order(id, owner: owner)
                actionKey = UUID()
                self.error = reason + "。已刷新订单，请核对进度后再操作。"
            } catch { self.error = reason + "。暂未刷新成功，请手动刷新订单后核对。" }
        }
    }
}

private struct PrintRevisionContext: Identifiable { var id: String { order.id }; let book: DiaryBook; let store: DiaryDocumentStore; let order: PrintOrder }
