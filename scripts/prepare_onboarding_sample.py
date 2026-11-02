#!/usr/bin/env python3
"""Bundle page one of an exported TravelDiary book for the offline making guide.

Usage: python3 scripts/prepare_onboarding_sample.py '/path/to/exported/book'
Requires Pillow. Keeps original object IDs, layout and alpha; limits source images
for a presentation-only scene. Does not modify the source book.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageOps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('book', type=Path)
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / 'TravelDiaryClient/Projects/App/Resources/DiaryOnboarding.bundle'
    book = json.loads((args.book / 'book.json').read_text())
    page = book['pages'][0]
    revision = args.book / 'pages' / page['id'] / 'revisions' / page['revisionID']
    manifest = json.loads((revision / 'manifest.json').read_text())
    objects = [json.loads((revision / 'objects' / Path(ref['path']).name).read_text()) for ref in manifest['objects']]
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    for asset in manifest['assets'].values():
        with Image.open(args.book / asset['path']) as source:
            image = ImageOps.exif_transpose(source)
            image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
            alpha = image.mode in ('RGBA', 'LA') or 'transparency' in image.info
            name = asset['id'] + ('.png' if alpha else '.jpg')
            image.save(output / name, **({'optimize': True} if alpha else {'quality': 86, 'optimize': True}))
            assets.append(dict(asset, path=name, pixelSize=list(image.size)))
    scene = dict(rootContentID=manifest['rootContentID'], objects=objects, assets=assets)
    (output / 'scene.json').write_text(json.dumps(scene, ensure_ascii=False, separators=(',', ':')))
    print(f'Bundled {len(objects)} objects, {len(assets)} images into {output}')


if __name__ == '__main__':
    main()
