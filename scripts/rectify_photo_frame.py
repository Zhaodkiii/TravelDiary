#!/usr/bin/env python3
"""Straighten a photo frame with a four-point perspective transform.

Click the four outer corners of the frame body in clockwise order, starting at
the top-left. The entire frame image is transformed, preserving its transparent
background and decorative details. The original asset is never overwritten.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox

import numpy as np
from PIL import Image, ImageTk


def parse_ratio(value: str | None, width: float, height: float) -> float:
    """Return output width / height, derived from the selected opening by default."""
    if value is None:
        return width / height
    try:
        a, b = value.split(":", 1)
        ratio = float(a) / float(b)
    except (ValueError, ZeroDivisionError) as exc:
        raise argparse.ArgumentTypeError("比例请写成 W:H，例如 4:3 或 1:1") from exc
    if ratio <= 0:
        raise argparse.ArgumentTypeError("比例必须大于 0")
    return ratio


def homography(source: np.ndarray, destination: np.ndarray) -> np.ndarray:
    rows, values = [], []
    for (x, y), (u, v) in zip(source, destination):
        rows.extend(([x, y, 1, 0, 0, 0, -u * x, -u * y],
                     [0, 0, 0, x, y, 1, -v * x, -v * y]))
        values.extend((u, v))
    return np.append(np.linalg.solve(rows, values), 1).reshape(3, 3)


class Rectifier:
    def __init__(self, path: Path, output: Path, ratio_arg: str | None):
        self.path = path
        self.output = output
        self.image = Image.open(path).convert("RGBA")
        self.width, self.height = self.image.size
        self.points: list[tuple[float, float]] = []
        self.scale = min(1.0, 1100 / self.width, 760 / self.height)
        self.preview_size = (round(self.width * self.scale), round(self.height * self.scale))
        self.ratio_arg = ratio_arg

        self.root = tk.Tk()
        self.root.title(f"规整相框内框：{path.name}")
        self.photo = ImageTk.PhotoImage(self.image.resize(self.preview_size, Image.Resampling.LANCZOS))
        self.canvas = tk.Canvas(self.root, width=self.preview_size[0], height=self.preview_size[1],
                                cursor="crosshair", highlightthickness=0)
        self.canvas.pack(padx=10, pady=10)
        self.canvas.create_image(0, 0, image=self.photo, anchor="nw")
        self.canvas.bind("<Button-1>", self.add_point)

        self.status = tk.StringVar(value="依次点击相框外框四角：左上、右上、右下、左下")
        tk.Label(self.root, textvariable=self.status).pack(pady=(0, 8))
        controls = tk.Frame(self.root)
        controls.pack(pady=(0, 10))
        tk.Button(controls, text="撤销一点", command=self.undo).pack(side="left", padx=4)
        tk.Button(controls, text="清除", command=self.clear).pack(side="left", padx=4)
        tk.Button(controls, text="生成 PNG", command=self.save).pack(side="left", padx=4)
        self.root.bind("<Escape>", lambda _event: self.root.destroy())

    def add_point(self, event: tk.Event) -> None:
        if len(self.points) == 4:
            self.clear()
        x = min(max(event.x / self.scale, 0), self.width - 1)
        y = min(max(event.y / self.scale, 0), self.height - 1)
        self.points.append((x, y))
        i = len(self.points)
        radius = max(4, round(6 * self.scale))
        cx, cy = x * self.scale, y * self.scale
        self.canvas.create_oval(cx-radius, cy-radius, cx+radius, cy+radius,
                                fill="#ff3b30", outline="white", width=2, tags="markers")
        self.canvas.create_text(cx, cy, text=str(i), fill="white", font=("Arial", 11, "bold"), tags="markers")
        self.status.set(f"已选 {i}/4 个角点" if i < 4 else "四点已选好；可生成，或点击画面重新选择")

    def undo(self) -> None:
        if self.points:
            self.points.pop()
            self.canvas.delete("markers")
            old = self.points[:]
            self.points = []
            for x, y in old:
                class Event: pass
                event = Event()
                event.x, event.y = round(x * self.scale), round(y * self.scale)
                self.add_point(event)
            self.status.set(f"已选 {len(self.points)}/4 个角点")

    def clear(self) -> None:
        self.points.clear()
        self.canvas.delete("markers")
        self.status.set("依次点击相框外框四角：左上、右上、右下、左下")

    def save(self) -> None:
        if len(self.points) != 4:
            messagebox.showinfo("还差角点", "请先依次点击相框外框的四个角。", parent=self.root)
            return
        quad = np.asarray(self.points, dtype=float)
        top = np.linalg.norm(quad[1] - quad[0])
        bottom = np.linalg.norm(quad[2] - quad[3])
        left = np.linalg.norm(quad[3] - quad[0])
        right = np.linalg.norm(quad[2] - quad[1])
        out_h = max(1, round((left + right) / 2))
        ratio = parse_ratio(self.ratio_arg, (top + bottom) / 2, (left + right) / 2)
        out_w = max(1, round(out_h * ratio))
        target = np.array([[0, 0], [out_w, 0], [out_w, out_h], [0, out_h]], dtype=float)

        forward = homography(quad, target)
        corners = np.array([[0, 0], [self.width, 0], [self.width, self.height], [0, self.height]], dtype=float)
        mapped = np.c_[corners, np.ones(4)] @ forward.T
        mapped = mapped[:, :2] / mapped[:, 2:]
        low = np.floor(mapped.min(axis=0))
        high = np.ceil(mapped.max(axis=0))
        out_size = tuple(np.maximum(1, (high - low).astype(int)))
        translation = np.array([[1, 0, -low[0]], [0, 1, -low[1]], [0, 0, 1]], dtype=float)
        inverse = np.linalg.inv(translation @ forward)
        inverse /= inverse[2, 2]
        coeffs = (inverse[0, 0], inverse[0, 1], inverse[0, 2],
                  inverse[1, 0], inverse[1, 1], inverse[1, 2],
                  inverse[2, 0], inverse[2, 1])
        result = self.image.transform(out_size, Image.Transform.PERSPECTIVE, coeffs,
                                      resample=Image.Resampling.BICUBIC)
        self.output.parent.mkdir(parents=True, exist_ok=True)
        result.save(self.output, optimize=True)
        messagebox.showinfo("完成", f"已保存：\n{self.output}", parent=self.root)
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    parser = argparse.ArgumentParser(description="手动选取相框外框四角，透视拉正为长方形或正方形。")
    parser.add_argument("image", nargs="?", type=Path, help="输入 PNG；不填时会弹出文件选择框")
    parser.add_argument("-o", "--output", type=Path, help="输出 PNG，默认在原图旁生成 *_rectified.png")
    parser.add_argument("--ratio", help="目标内框宽高比，如 4:3、3:4 或 1:1；默认按当前内框平均边长")
    args = parser.parse_args()
    if args.ratio:
        parse_ratio(args.ratio, 1, 1)
    source = args.image or filedialog.askopenfilename(
        title="选择相框 PNG", filetypes=(("PNG 图片", "*.png"), ("所有文件", "*")))
    if not source:
        return
    source = Path(source)
    if not source.is_file():
        parser.error(f"找不到输入文件：{source}")
    destination = args.output or source.with_name(f"{source.stem}_rectified.png")
    Rectifier(source, destination, args.ratio).run()


if __name__ == "__main__":
    main()
