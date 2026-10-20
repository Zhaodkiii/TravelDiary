#!/usr/bin/env python3
"""Batch-straighten frame openings from transparent PNG photo-frame assets.

Each opening is detected as a large enclosed transparent region. Its four
extreme corners are mapped to a rectangle, carrying the frame and decoration
through the same perspective transform. Use --in-place only when you intend
to replace assets; original PNGs are copied to --backup-dir first.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
import shutil

import numpy as np
from PIL import Image


REGULAR_IDS = {
    "0689278c91", "1794e316eb", "40f4355996", "62154094ae", "8073b107ff",
    "81599c4dbb", "85e952845d", "9754e7d86e", "c3a046d48f", "d95bc23c2f",
}


def enclosed_opening(alpha: np.ndarray) -> np.ndarray | None:
    free = alpha < 100
    height, width = free.shape
    seen = np.zeros((height, width), dtype=bool)
    largest = None
    for y, x in zip(*np.where(free)):
        if seen[y, x]:
            continue
        queue = deque([(int(x), int(y))])
        seen[y, x] = True
        points = []
        touches_edge = False
        while queue:
            cx, cy = queue.popleft()
            points.append((cx, cy))
            touches_edge |= cx in (0, width - 1) or cy in (0, height - 1)
            for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                if 0 <= nx < width and 0 <= ny < height and free[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((nx, ny))
        if not touches_edge and len(points) > 250 and (largest is None or len(points) > len(largest)):
            largest = points
    return None if largest is None else np.asarray(largest, dtype=float)


def homography(source: np.ndarray, destination: np.ndarray) -> np.ndarray:
    rows, values = [], []
    for (x, y), (u, v) in zip(source, destination):
        rows.extend(([x, y, 1, 0, 0, 0, -u * x, -u * y],
                     [0, 0, 0, x, y, 1, -v * x, -v * y]))
        values.extend((u, v))
    return np.append(np.linalg.solve(rows, values), 1).reshape(3, 3)


def rectify(image: Image.Image) -> Image.Image | None:
    image = image.convert("RGBA")
    width, height = image.size
    alpha = np.asarray(image.getchannel("A").resize((256, 256), Image.Resampling.BILINEAR))
    opening = enclosed_opening(alpha)
    if opening is None:
        return None
    opening[:, 0] *= width / 256
    opening[:, 1] *= height / 256
    sums = opening[:, 0] / width + opening[:, 1] / height
    differences = opening[:, 0] / width - opening[:, 1] / height
    quad = np.array([opening[sums.argmin()], opening[differences.argmax()],
                     opening[sums.argmax()], opening[differences.argmin()]])
    out_width = (np.linalg.norm(quad[1] - quad[0]) + np.linalg.norm(quad[2] - quad[3])) / 2
    out_height = (np.linalg.norm(quad[3] - quad[0]) + np.linalg.norm(quad[2] - quad[1])) / 2
    if out_width < 5 or out_height < 5:
        return None
    target = np.array([[0, 0], [out_width, 0], [out_width, out_height], [0, out_height]])
    forward = homography(quad, target)
    bounds = np.array([[0, 0], [width, 0], [width, height], [0, height]], dtype=float)
    mapped = np.c_[bounds, np.ones(4)] @ forward.T
    mapped = mapped[:, :2] / mapped[:, 2:]
    low, high = np.floor(mapped.min(axis=0)), np.ceil(mapped.max(axis=0))
    size = tuple(np.maximum(1, (high - low).astype(int)))
    if max(size) > 4000:
        return None
    translation = np.array([[1, 0, -low[0]], [0, 1, -low[1]], [0, 0, 1]])
    inverse = np.linalg.inv(translation @ forward)
    inverse /= inverse[2, 2]
    coefficients = tuple(inverse.flatten()[:8])
    return image.transform(size, Image.Transform.PERSPECTIVE, coefficients,
                           resample=Image.Resampling.BICUBIC)


def main() -> None:
    default_assets = Path(__file__).resolve().parents[1] / "TravelDiaryClient/Projects/App/Resources/Assets.xcassets/PhotoFrames"
    parser = argparse.ArgumentParser(description="批量将透明相框内框透视拉正为长方形。")
    parser.add_argument("--assets", type=Path, default=default_assets, help="PhotoFrames.xcassets 目录")
    parser.add_argument("--output", type=Path, help="输出目录；默认写入 PhotoFrames_rectified")
    parser.add_argument("--in-place", action="store_true", help="替换原 PNG，并先在备份目录保存原图")
    parser.add_argument("--backup-dir", type=Path, help="原图备份目录；--in-place 时必填")
    parser.add_argument("--include-regular", action="store_true", help="也处理此前判断为规则的 10 个相框")
    args = parser.parse_args()
    if args.in_place and not args.backup_dir:
        parser.error("使用 --in-place 时必须同时提供 --backup-dir")
    if not args.in_place and args.output is None:
        args.output = args.assets.parent / "PhotoFrames_rectified"

    processed, skipped = 0, []
    for image_path in sorted(args.assets.glob("diary_frame_*.imageset/frame.png")):
        ident = image_path.parent.name.removeprefix("diary_frame_").removesuffix(".imageset")
        if not args.include_regular and ident in REGULAR_IDS:
            continue
        result = rectify(Image.open(image_path))
        if result is None:
            skipped.append(ident)
            continue
        if args.in_place:
            relative = image_path.relative_to(args.assets)
            backup = args.backup_dir / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(image_path, backup)
            destination = image_path
        else:
            destination = args.output / image_path.parent.name / image_path.name
            destination.parent.mkdir(parents=True, exist_ok=True)
        result.save(destination, optimize=True)
        processed += 1
    print(f"处理完成：{processed} 张；跳过：{len(skipped)} 张")
    if skipped:
        print("未识别到透明内框：" + ", ".join(skipped))


if __name__ == "__main__":
    main()
