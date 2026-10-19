import SwiftUI
import PDFKit

struct PrintCheckoutScreen: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    var revisionOrder: PrintOrder? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var revisions: [PrintOrder] = []
    @State private var reviseSelection: PrintOrder?
    @State private var products: [PrintProduct] = []
    @State private var productID = ""
    @State private var front: UUID?
    @State private var back: UUID?
    @State private var prepared: PrintPrepared?
    @State private var address = PrintAddress()
    @State private var quantity = 1
    @State private var quote: PrintQuote?
    @State private var confirmed = false
    @State private var sawCover = false
    @State private var sawInterior = false
    @State private var preview: PrintPreviewItem?
    @State private var busy = false
    @State private var error: String?
    @State private var progressText = ""
    @State private var jobID: UUID?
    @State private var submissionKey = UUID()
    private let service = PrintOrderService.shared
    private var product: PrintProduct? { products.first { $0.id == productID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(book.title).font(.title2.bold())
                    Text("把亲手制作的回忆，印成可以珍藏的一本。").foregroundStyle(.secondary)
                    NavigationLink("我的印制订单") { PrintOrdersScreen(owner: store.ownerID) }
                }
                if revisionOrder == nil && !revisions.isEmpty {
                    Section("有订单需要修改重提") {
                        ForEach(revisions) { item in
                            Button { reviseSelection = item } label: {
                                VStack(alignment: .leading) { Text(item.title + " · " + item.spec.title); Text(item.exception_reason).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                        Text("选择原订单可替换生产稿，无需重复下单或付款。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let revisionOrder {
                    Section("修改原订单") {
                        Text(revisionOrder.number).font(.caption).textSelection(.enabled)
                        Text(revisionOrder.exception_reason).foregroundStyle(.orange)
                        Text("请先在编辑器完成修改，再生成并确认新稿。须保持原规格、份数及 \(revisionOrder.page_count) 面内页；新稿直接替换当前生产稿。").font(.footnote)
                    }
                }
                if products.isEmpty && !busy {
                    Section { ContentUnavailableView("印制服务准备中", systemImage: "book.closed", description: Text("目前没有已开放的规格，请稍后再来。")) }
                }
                if !products.isEmpty {
                    Section("选择实物规格") {
                        Picker("印制规格", selection: $productID) { ForEach(products) { Text($0.title).tag($0.id) } }.disabled(revisionOrder != nil)
                        if let product {
                            Text("\(product.width_mm) × \(product.height_mm) mm · \(product.paper) · \(product.binding)").font(.subheadline)
                            if !product.description.isEmpty { Text(product.description).font(.footnote).foregroundStyle(.secondary) }
                            Text("内页\(product.duplex ? "双面" : "单面")印刷 · \(product.min_pages)–\(product.max_pages) 面").font(.footnote)
                            if !product.lead_time.isEmpty { Text(product.lead_time).font(.footnote) }
                            Stepper("印制 \(quantity) 份", value: $quantity, in: 1...max(product.max_quantity,1)).disabled(revisionOrder != nil)
                        }
                    }
                    Section {
                        Picker("正封面", selection: $front) {
                            Text("请选择").tag(Optional<UUID>.none)
                            ForEach(Array(book.contentPages.enumerated()), id: \.element.id) { i, page in Text(pageTitle(page, i)).tag(Optional(page.id)) }
                        }
                        Picker("封底", selection: $back) {
                            Text("请选择").tag(Optional<UUID>.none)
                            ForEach(Array(book.contentPages.enumerated()), id: \.element.id) { i, page in Text(pageTitle(page, i)).tag(Optional(page.id)) }
                        }
                        Text("其余页面按原顺序作为内页。阅读器外壳不会印入成品；双面印刷需要时会在末尾补一面空白。").font(.footnote).foregroundStyle(.secondary)
                        Button(prepared == nil ? "生成并检查生产稿" : "重新生成生产稿") { Task { await prepare() } }
                            .disabled(front == nil || back == nil || front == back || busy)
                    } header: { Text("封面与内页") }
                    if let prepared {
                        Section("确认最终生产稿") {
                            Button("预览封面与封底 · 2 面") { sawCover = true; preview = PrintPreviewItem(url: prepared.directory.appendingPathComponent("cover.pdf"), title: "封面与封底") }
                            Button("预览内页 · \(prepared.pageCount) 面") { sawInterior = true; preview = PrintPreviewItem(url: prepared.directory.appendingPathComponent("interior.pdf"), title: "内页 · \(prepared.pageCount) 面") }
                            ForEach(Array(prepared.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote).foregroundStyle(.orange) }
                            Text("请放大检查照片、文字、页序和边缘。当前规格按页面原尺寸印制，无额外出血扩展；重要内容请避开裁切和装订位置。").font(.footnote).foregroundStyle(.secondary)
                            Toggle("我已检查内容、页序和裁切范围，按此版本印制", isOn: $confirmed).disabled(!sawCover || !sawInterior)
                        }
                        Section("收货地址") {
                            TextField("收件人", text: $address.name).textContentType(.name)
                            TextField("手机号", text: $address.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            Picker("配送地区", selection: $address.region) {
                                Text("请选择").tag("")
                                ForEach(product?.regions ?? [], id: \.self) { Text($0).tag($0) }
                            }
                            TextField("街道、门牌号等详细地址", text: $address.detail, axis: .vertical).textContentType(.fullStreetAddress)
                        }
                        .disabled(revisionOrder != nil)
                        Section("费用与提交") {
                            if let product { Text(product.terms).font(.footnote).foregroundStyle(.secondary) }
                            Button(revisionOrder == nil ? "计算价格" : "核对原订单费用") { Task { await calculate() } }.disabled(!address.complete || busy)
                            if let quote {
                                LabeledContent("印制费", value: PrintText.money(quote.production_fen))
                                LabeledContent("运费", value: PrintText.money(quote.shipping_fen))
                                LabeledContent("合计", value: quote.total_fen == 0 ? "免费" : PrintText.money(quote.total_fen)).font(.headline)
                                Text("\(quote.page_count) 面内页 · 每份 \(quote.sheets) 张内页纸；封面另计。").font(.footnote).foregroundStyle(.secondary)
                                Button(revisionOrder == nil ? "确认订单并上传" : "替换生产稿并重新提交") { submit(prepared) }
                                    .disabled(!confirmed || !address.complete || busy || jobID != nil)
                                Text(revisionOrder != nil ? "保留原订单及付款信息，新稿上传后重新审核，无需再次支付。" : quote.total_fen == 0 ? "本次订单免费，上传完成后直接提交人工审核，无需支付。" : "生产文件上传后，可在订单中使用微信支付。").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if busy { Section { ProgressView(progressText.isEmpty ? "正在加载…" : progressText) } }
                if let error { Section { Text(error).foregroundStyle(.red); Button("重新加载规格") { Task { await load() } } } }
            }
            .disabled(busy)
            .navigationTitle(revisionOrder == nil ? "装订成册" : "修改重提")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
            .navigationDestination(isPresented: Binding(get: { jobID != nil }, set: { if !$0 { jobID = nil; submissionKey = UUID(); prepared = nil } })) {
                if let jobID { PrintUploadScreen(id: jobID, owner: store.ownerID) }
            }
            .sheet(item: $preview) { item in PrintPDFPreview(item: item) }
            .sheet(item: $reviseSelection) { item in PrintCheckoutScreen(book: book, store: store, revisionOrder: item) }
            .task { await load() }
            .onChange(of: productID) { _, _ in if revisionOrder == nil { invalidate(); quantity = 1; address.region = "" } }
            .onChange(of: front) { _, _ in invalidate() }
            .onChange(of: back) { _, _ in invalidate() }
            .onChange(of: quantity) { _, _ in quote = nil }
            .onChange(of: address.region) { _, _ in quote = nil }
            .onDisappear { if jobID == nil { invalidate() } }
        }
        .interactiveDismissDisabled(busy)
    }
    private func pageTitle(_ page: DiaryPageEntry, _ i: Int) -> String { "第 \(i+1) 页" + (page.title.isEmpty ? "" : " · \(page.title)") }
    private func invalidate() {
        if let prepared { try? FileManager.default.removeItem(at: prepared.directory) }
        prepared = nil; confirmed = false; sawCover = false; sawInterior = false; quote = nil
    }
    private func load() async {
        busy = true; error = nil; defer { busy = false }
        do {
            if let revisionOrder {
                products = [revisionOrder.spec]; productID = revisionOrder.spec.id; quantity = revisionOrder.quantity; address = revisionOrder.address
            } else {
                products = try await service.products(owner: store.ownerID)
                if !products.contains(where: { $0.id == productID }) { productID = products.first?.id ?? "" }
                revisions = try await service.revisionOrders(bookID: book.id, owner: store.ownerID)
            }
        }
        catch { self.error = error.localizedDescription }
    }
    private func prepare() async {
        guard let product, let front, let back else { return }
        invalidate(); busy = true; error = nil; defer { busy = false; progressText = "" }
        var dir: URL?
        do {
            try service.requireOwner(store.ownerID, bound: true)
            let directory = try service.draftDirectory(owner: store.ownerID); dir = directory
            prepared = try await DiaryBookPrintExporter.prepare(book: book, store: store, product: product, front: front, back: back, directory: directory) { done, total in progressText = "正在准备生产稿 \(done)/\(total)" }
        } catch { if let dir { try? FileManager.default.removeItem(at: dir) }; self.error = error.localizedDescription }
    }
    private func calculate() async {
        guard let product, let prepared else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            if let revisionOrder {
                guard prepared.pageCount == revisionOrder.page_count else { throw PrintFailure("重提需保持 \(revisionOrder.page_count) 面内页；当前为 \(prepared.pageCount) 面。如需更改页数，请取消后重新下单。") }
                quote = PrintQuote(total_fen: revisionOrder.total_fen, production_fen: revisionOrder.total_fen - product.shipping_fen, shipping_fen: product.shipping_fen, page_count: prepared.pageCount, sheets: product.duplex ? (prepared.pageCount+1)/2 : prepared.pageCount, product_revision: product.revision)
                return
            }
            let result = try await service.quote(product: product, pages: prepared.pageCount, quantity: quantity, address: address, owner: store.ownerID)
            guard result.product_revision == product.revision else { throw PrintFailure("规格已更新，请重新打开印制页面") }
            quote = result
        } catch { self.error = error.localizedDescription; quote = nil }
    }
    private func submit(_ prepared: PrintPrepared) {
        guard let product, let quote, confirmed else { return }
        do {
            let submission = PrintSubmission(key: submissionKey, product_id: product.id, product_revision: product.revision,
                title: book.title, quantity: quantity, page_count: prepared.pageCount, address: address,
                snapshot: prepared.snapshot, files: prepared.files, confirmed: true, quote_total_fen: quote.total_fen, revise_order_id: revisionOrder?.id, order_revision: revisionOrder?.revision)
            jobID = try service.enqueue(submission, directory: prepared.directory, owner: store.ownerID)
        } catch { self.error = error.localizedDescription }
    }
}

struct PrintPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String }
private struct PrintPDFPreview: View {
    let item: PrintPreviewItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { PrintPDFView(url: item.url).navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
    }
}
private struct PrintPDFView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.document = PDFDocument(url: url); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateUIView(_ uiView: PDFView, context: Context) { }
}

struct PrintUploadScreen: View {
    let id: UUID
    let owner: String
    @ObservedObject private var service = PrintOrderService.shared
    @State private var latestOrder: PrintOrder?
    @State private var refreshError: String?
    private var job: PrintLocalJob? { service.jobs.first { $0.id == id && $0.owner == owner } }
    var body: some View {
        List {
            if let job {
                Section { Text(job.submission.title).font(.headline); Text(job.state)
                    if let latestOrder, job.state == "已上传" { Text(latestOrder.statusText).foregroundStyle(.secondary) }
                    if let latestOrder, !latestOrder.production_error.isEmpty { Text(latestOrder.production_error).foregroundStyle(.red) }
                    if let refreshError { Text(refreshError).foregroundStyle(.red) }
                    if let progress = service.progress[id] { ProgressView(value: progress); Text("\(Int(progress*100))%").font(.caption) }
                    if let error = job.error { Text(error).foregroundStyle(.red) }
                    if service.isRunning(id) { Button("暂停上传") { service.pause(id) } }
                    else if job.state != "已上传" || latestOrder?.file_state == "failed" { Button(latestOrder?.file_state == "failed" ? "重新上传生产稿" : "继续上传") { latestOrder = nil; service.resume(id) } }
                    Text("可以离开此页面，订单与上传记录已保存。系统中断后，可从“我的印制订单”继续。").font(.footnote).foregroundStyle(.secondary)
                }
                if let orderID = job.orderID { Section { NavigationLink(job.submission.quote_total_fen == 0 ? "查看免费印制订单" : "查看订单 / 微信支付") { PrintOrderDetailScreen(id: orderID, owner: owner) } } }
            } else { Text("此账号下没有该上传任务") }
        }.navigationTitle("提交印制")
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
        List {
            let local = service.jobs.filter { $0.owner == owner && $0.state != "已上传" }
            if !local.isEmpty { Section("待上传 / 可恢复") { ForEach(local) { job in NavigationLink { PrintUploadScreen(id: job.id, owner: owner) } label: { VStack(alignment: .leading) { Text(job.submission.title); Text(job.state).font(.caption).foregroundStyle(.secondary) } } } } }
            Section("印制订单") {
                ForEach(orders) { order in NavigationLink { PrintOrderDetailScreen(id: order.id, owner: owner) } label: {
                    VStack(alignment: .leading, spacing: 6) { HStack { Text(order.title).font(.headline); Spacer(); Text(order.statusText).font(.caption) }
                        Text("\(order.spec.title) · \(order.quantity) 份 · \(PrintText.money(order.total_fen))").font(.subheadline).foregroundStyle(.secondary)
                    }
                } }
                if orders.isEmpty && !busy { Text("还没有印制订单。完成手帐后，在导出页选择“装订成册”。").foregroundStyle(.secondary) }
                if next != nil { Button("加载更多") { Task { await load(more: true) } }.disabled(busy) }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("我的印制订单").task { await load() }.refreshable { await load() }
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
    private let service = PrintOrderService.shared
    var body: some View {
        List {
            if let order {
                Section { Text(order.statusText).font(.title2.bold()); Text(order.title).font(.headline)
                    Text("订单号：\(order.number)").font(.caption).textSelection(.enabled)
                    LabeledContent("金额", value: PrintText.money(order.total_fen))
                    Text(PrintText.label(order.payment_state)).foregroundStyle(.secondary)
                    if !order.production_error.isEmpty { Text(order.production_error).foregroundStyle(.red) }
                }
                if order.state == "needs_revision" {
                    Section("修改后重新提交") {
                        Text(order.exception_reason).foregroundStyle(.orange)
                        Text("在原作品中完成修改，再重新生成生产稿。保留原订单与付款信息，无需重复下单。").font(.footnote)
                        Button("打开原订单重提页面") { Task { await openRevision(order) } }.disabled(busy)
                    }
                } else if !order.exception_reason.isEmpty {
                    Section("制作情况") { Text(order.exception_reason) }
                }
                if !order.after_sale_state.isEmpty {
                    Section("售后进度 · " + PrintText.label(order.after_sale_state)) {
                        Text(order.after_sale_message)
                        if !order.after_sale_resolution.isEmpty { Text("处理结果：" + order.after_sale_resolution) }
                    }
                }
                if order.refund_state == "exception" { Section { Text("退款暂未完成，工作人员正在核对。可通过售后联系处理。").foregroundStyle(.orange) } }
                Section("印制与寄送") {
                    Text("\(order.spec.title) · \(order.quantity) 份 · \(order.page_count) 面内页")
                    Text("\(order.address.name) · \(order.address.phone)")
                    Text(order.address.region + " " + order.address.detail)
                    ForEach(order.shipments) { s in Text("\(s.kind == "reship" ? "补寄 · " : "")\(s.carrier) · \(s.tracking_number)").textSelection(.enabled) }
                }
                Section {
                    if order.allowed_actions.contains("upload"), let local = service.jobs.first(where: { $0.orderID == id && $0.owner == owner && $0.productionID == order.production_id }) {
                        NavigationLink("继续上传生产文件") { PrintUploadScreen(id: local.id, owner: owner) }
                    }
                    if order.allowed_actions.contains("pay") { Button("微信支付 · \(PrintText.money(order.total_fen))") { Task { await pay() } } }
                    Button("刷新订单与付款结果") { Task { await load(payment: order.payment_state == "unpaid" || order.payment_state == "refund_pending") } }
                    if order.allowed_actions.contains("cancel") { Button("取消订单", role: .destructive) { confirmingCancel = true } }
                    if order.allowed_actions.contains("receive") { Button("确认收货") { confirmingReceive = true } }
                }.disabled(busy)
                if order.allowed_actions.contains("after_sale") {
                    Section("售后申请") { TextField("请描述遇到的问题", text: $message, axis: .vertical); Button("提交售后申请") { Task { await act("after_sale") } }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) }
                }
                Section("订单进度") { ForEach(order.events.reversed()) { event in VStack(alignment: .leading, spacing: 5) { Text(event.message); Text(event.created_at.replacingOccurrences(of: "T", with: " ").prefix(19)).font(.caption).foregroundStyle(.secondary) } } }
            }
            if busy { ProgressView("正在处理…") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("印制订单")
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
        .confirmationDialog("确认已收到并检查此订单的全部成品？", isPresented: $confirmingReceive, titleVisibility: .visible) {
            Button("确认收货") { Task { await act("receive") } }
        }
        .confirmationDialog("取消此印制订单？已付款订单将申请原路退款。", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("确认取消", role: .destructive) { Task { await act("cancel") } }
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
