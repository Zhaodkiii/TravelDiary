import UIKit

/// 预览大图圆角裁剪容器：圆角作用在内部 clipView，缩放时仍保持 Signal 风格圆角。
final class SecondCameraRoundedImageContainerView: UIView {
    private let clipView = UIView()
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
    }

    func setCornerRadius(_ cornerRadius: CGFloat, animated: Bool = false) {
        guard clipView.layer.cornerRadius != cornerRadius else { return }

        if animated {
            let animation = CABasicAnimation(keyPath: #keyPath(CALayer.cornerRadius))
            animation.fromValue = clipView.layer.cornerRadius
            animation.toValue = cornerRadius
            animation.duration = 0.15
            clipView.layer.add(animation, forKey: "cornerRadius")
        }

        clipView.layer.cornerRadius = cornerRadius
    }

    private func configureSubviews() {
        backgroundColor = .clear
        isOpaque = false

        clipView.clipsToBounds = true
        clipView.backgroundColor = .clear
        clipView.isOpaque = false
        clipView.layer.cornerRadius = SecondCameraImagePreviewLayout.signalPreviewCornerRadius

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.isOpaque = false

        addSubview(clipView)
        clipView.addSubview(imageView)

        clipView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipView.topAnchor.constraint(equalTo: topAnchor),
            clipView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: clipView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
        ])
    }
}
