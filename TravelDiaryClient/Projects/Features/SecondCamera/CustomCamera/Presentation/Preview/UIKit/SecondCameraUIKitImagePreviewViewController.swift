import UIKit

/// UIKit 大图预览控制器：UIScrollView 双指缩放 / 拖动 / 居中，对齐 Signal AttachmentPrep。
final class SecondCameraUIKitImagePreviewViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let imageContainerView = SecondCameraRoundedImageContainerView()

    private var image: UIImage
    private var imageID: AnyHashable
    private var contentInsets: UIEdgeInsets
    private var cornerRadius: CGFloat
    private var maximumZoomScaleMultiplier: CGFloat
    private var lastImageIdentifier: AnyHashable?

    private var scrollViewLeadingConstraint: NSLayoutConstraint?
    private var scrollViewTopConstraint: NSLayoutConstraint?
    private var scrollViewTrailingConstraint: NSLayoutConstraint?
    private var scrollViewBottomConstraint: NSLayoutConstraint?

    private var isViewConfigured = false
    private var pendingZoomReset = true

    init(
        imageID: AnyHashable,
        image: UIImage,
        contentInsets: UIEdgeInsets,
        cornerRadius: CGFloat,
        maximumZoomScaleMultiplier: CGFloat
    ) {
        self.imageID = imageID
        self.image = image
        self.contentInsets = contentInsets
        self.cornerRadius = cornerRadius
        self.maximumZoomScaleMultiplier = maximumZoomScaleMultiplier
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureScrollView()
        configureImageContainer()
        isViewConfigured = true
        lastImageIdentifier = imageID
        applyImageAndChrome(resetZoom: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateImageContainerSizeIfNeeded()
        updateZoomScale(resetIfNeeded: pendingZoomReset)
        centerContentIfNeeded()
        pendingZoomReset = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            guard let self else { return }
            self.updateImageContainerSizeIfNeeded()
            self.updateZoomScale(resetIfNeeded: false)
            self.centerContentIfNeeded()
        }
    }

    func update(
        imageID: AnyHashable,
        image: UIImage,
        contentInsets: UIEdgeInsets,
        cornerRadius: CGFloat,
        maximumZoomScaleMultiplier: CGFloat
    ) {
        let didChangeImage = imageID != lastImageIdentifier

        self.imageID = imageID
        self.image = image
        self.contentInsets = contentInsets
        self.cornerRadius = cornerRadius
        self.maximumZoomScaleMultiplier = maximumZoomScaleMultiplier

        guard isViewConfigured else { return }

        if didChangeImage {
            lastImageIdentifier = imageID
            pendingZoomReset = true
        }

        applyImageAndChrome(resetZoom: didChangeImage)
        view.setNeedsLayout()
    }

    // MARK: - Setup

    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)

        let leading = scrollView.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: contentInsets.left
        )
        let top = scrollView.topAnchor.constraint(
            equalTo: view.topAnchor,
            constant: contentInsets.top
        )
        let trailing = scrollView.trailingAnchor.constraint(
            equalTo: view.trailingAnchor,
            constant: -contentInsets.right
        )
        let bottom = scrollView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -contentInsets.bottom
        )

        scrollViewLeadingConstraint = leading
        scrollViewTopConstraint = top
        scrollViewTrailingConstraint = trailing
        scrollViewBottomConstraint = bottom

        NSLayoutConstraint.activate([leading, top, trailing, bottom])
    }

    private func configureImageContainer() {
        imageContainerView.setImage(image)
        imageContainerView.setCornerRadius(cornerRadius)
        scrollView.addSubview(imageContainerView)
    }

    // MARK: - Updates

    private func applyImageAndChrome(resetZoom: Bool) {
        imageContainerView.setImage(image)
        imageContainerView.setCornerRadius(cornerRadius)
        updateConstraintsForInsets()
        updateImageContainerSizeIfNeeded(force: resetZoom)
        updateZoomScale(resetIfNeeded: resetZoom)
        centerContentIfNeeded()
    }

    private func updateConstraintsForInsets() {
        scrollViewLeadingConstraint?.constant = contentInsets.left
        scrollViewTopConstraint?.constant = contentInsets.top
        scrollViewTrailingConstraint?.constant = -contentInsets.right
        scrollViewBottomConstraint?.constant = -contentInsets.bottom
    }

    /// 内容尺寸使用图片原始 point size，再由 minZoomScale 适配可视区域（与 Signal 一致）。
    private func updateImageContainerSizeIfNeeded(force: Bool = false) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let sizeChanged = imageContainerView.bounds.size != imageSize
        guard force || sizeChanged else { return }

        let previousZoom = scrollView.zoomScale
        if abs(previousZoom - 1) > .ulpOfOne {
            scrollView.zoomScale = 1
        }

        imageContainerView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize
    }

    private func updateZoomScale(resetIfNeeded: Bool) {
        let visibleSize = scrollView.bounds.size
        let contentSize = imageContainerView.bounds.size

        guard visibleSize.width > 0,
              visibleSize.height > 0,
              contentSize.width > 0,
              contentSize.height > 0
        else { return }

        let widthScale = visibleSize.width / contentSize.width
        let heightScale = visibleSize.height / contentSize.height
        let minScale = min(widthScale, heightScale)
        guard minScale.isFinite, minScale > 0 else { return }

        let previousMin = scrollView.minimumZoomScale
        let previousZoom = scrollView.zoomScale

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = minScale * maximumZoomScaleMultiplier

        if resetIfNeeded {
            scrollView.zoomScale = minScale
        } else if previousMin > 0, previousZoom > 0 {
            // 布局变化时保留相对放大倍数，避免用户正在查看细节时被弹回。
            let relative = previousZoom / previousMin
            let restored = min(max(minScale * relative, minScale), scrollView.maximumZoomScale)
            scrollView.zoomScale = restored
        } else if scrollView.zoomScale < minScale {
            scrollView.zoomScale = minScale
        } else if scrollView.zoomScale > scrollView.maximumZoomScale {
            scrollView.zoomScale = scrollView.maximumZoomScale
        }
    }

    private func centerContentIfNeeded() {
        let scrollViewSize = scrollView.bounds.size
        var contentCenter = CGPoint(
            x: scrollView.contentSize.width / 2,
            y: scrollView.contentSize.height / 2
        )

        if scrollView.contentSize.width < scrollViewSize.width {
            contentCenter.x = 0.5 * scrollViewSize.width
        }
        if scrollView.contentSize.height < scrollViewSize.height {
            contentCenter.y = 0.5 * scrollViewSize.height
        }

        imageContainerView.center = contentCenter
    }
}

// MARK: - UIScrollViewDelegate

extension SecondCameraUIKitImagePreviewViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageContainerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContentIfNeeded()
    }
}
