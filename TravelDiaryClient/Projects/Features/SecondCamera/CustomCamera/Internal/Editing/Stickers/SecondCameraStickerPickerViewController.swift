import UIKit
import PureLayout

final class SecondCameraStickerPickerViewController: UIViewController {

    weak var pickerDelegate: SecondCameraStickerPickerDelegate?

    private let store = SecondCameraDefaultStickerStore.shared
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        overrideUserInterfaceStyle = .dark

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 72, height: 72)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(SecondCameraEditorStickerCell.self, forCellWithReuseIdentifier: SecondCameraEditorStickerCell.reuseId)

        view.addSubview(collectionView)
        collectionView.autoPinEdgesToSuperviewEdges()
    }
}

extension SecondCameraStickerPickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    private var stickers: [SecondCameraStickerItem] {
        store.packs.first?.stickers ?? []
    }

    private var packId: String {
        store.packs.first?.id ?? "signal-default"
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        stickers.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SecondCameraEditorStickerCell.reuseId, for: indexPath) as! SecondCameraEditorStickerCell
        let item = stickers[indexPath.item]
        let info = store.stickerInfo(for: item, packId: packId)
        cell.configure(image: store.image(for: info))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = stickers[indexPath.item]
        let info = store.stickerInfo(for: item, packId: packId)
        pickerDelegate?.didSelectSecondCameraSticker(info)
    }
}

private final class SecondCameraEditorStickerCell: UICollectionViewCell {
    static let reuseId = "SecondCameraEditorStickerCell"
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(image: UIImage?) {
        imageView.image = image
    }
}
