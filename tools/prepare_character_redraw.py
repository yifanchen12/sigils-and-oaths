"""Slice the redrawn cast, preserving connected silhouettes across atlas gutters.

Requires Pillow, NumPy and SciPy. This assembles generated artwork; it does not
draw or synthesize any character. Original sheets and prompts remain in sources.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from prepare_unit_pieces import figure

ROOT = Path(__file__).resolve().parents[1]
PRODUCTION = ROOT / 'assets/art/characters/v3/production.json'


def separate(path, count):
    image = Image.open(path).convert('RGBA')
    alpha = np.asarray(image.getchannel('A')).copy()
    mask = alpha > 100
    labels, total = ndimage.label(ndimage.binary_dilation(mask, iterations=2))
    sizes = np.bincount(labels.ravel())
    mains = sorted(range(1, total+1), key=lambda i: sizes[i], reverse=True)[:count]
    if len(mains) != count or min(sizes[i] for i in mains) < 10000:
        raise ValueError(f'{path.name}: missing complete silhouettes')
    centers = {i: ndimage.center_of_mass(mask, labels, i) for i in range(1, total+1)}
    mains.sort(key=lambda i: centers[i][1])
    if any(not (n/count-.15 <= centers[i][1]/image.width <= (n+1)/count+.15)
           for n, i in enumerate(mains)):
        raise ValueError(f'{path.name}: overlapping figures require a source correction')
    distances = [ndimage.distance_transform_edt(labels != i) for i in mains]
    owner = np.zeros(total+1, np.uint8)
    for i in range(1, total+1):
        if i in mains:
            owner[i] = mains.index(i)+1
        else:
            y,x = map(lambda value: int(round(value)), centers[i])
            owner[i] = int(np.argmin([distance[y,x] for distance in distances]))+1
    # Extend component ownership only into the original antialiased alpha.
    _, closest = ndimage.distance_transform_edt(labels == 0, return_indices=True)
    assigned = owner[labels[closest[0], closest[1]]]
    results = []
    for n in range(count):
        own_alpha = alpha.copy()
        own_alpha[(assigned != n+1) | (alpha < 12)] = 0
        ys,xs = np.nonzero(own_alpha > 55)
        bounds = (max(0,int(xs.min())-6), max(0,int(ys.min())-6),
                  min(image.width,int(xs.max())+7), min(image.height,int(ys.max())+7))
        cut = image.copy()
        cut.putalpha(Image.fromarray(own_alpha))
        cut = cut.crop(bounds)
        # PNG RGB under zero alpha can contain neighboring atlas figures. Clear
        # it so image editors and straight-alpha resampling cannot expose ghosts.
        pixels = np.asarray(cut).copy()
        pixels[pixels[:, :, 3] == 0, :3] = 0
        cut = Image.fromarray(pixels, 'RGBA')
        if (np.asarray(cut.getchannel('A')) == 0).mean() < .15:
            raise ValueError(f'{path.name}: unusable transparency in slot {n}')
        results.append(cut)
    return results


def prepare(allow_partial=False):
    record = json.loads(PRODUCTION.read_text('utf-8'))
    full_dir = ROOT / 'assets/art/characters/v3/full'
    full_dir.mkdir(parents=True, exist_ok=True)
    all_ids, previews, output = [], [], []
    for group in record['groups']:
        ids = group['ids']
        adult_path, chibi_path = ROOT/group['adult_source'], ROOT/group['chibi_source']
        if not adult_path.exists() or not chibi_path.exists():
            if allow_partial: continue
            raise FileNotFoundError('Missing completed adult/chibi pair for '+group['sheet'])
        adults, minis = separate(adult_path, len(ids)), separate(chibi_path, len(ids))
        portraits = Image.new('RGBA', (512*len(ids), 512))
        pieces = Image.new('RGBA', (256*len(ids), 256))
        for index,(key,adult,mini) in enumerate(zip(ids, adults, minis)):
            # A reviewed single-character correction overrides only its own slot.
            if key in group.get('adult_overrides', {}):
                adult = separate(ROOT/group['adult_overrides'][key], 1)[0]
            if key in group.get('chibi_overrides', {}):
                mini = separate(ROOT/group['chibi_overrides'][key], 1)[0]
            all_ids.append(key)
            destination = full_dir/(key+'.png')
            adult.save(destination)
            # Upper-body crop; individual exceptions can use normalized focus.
            focus = group.get('portrait_focus', {}).get(key, [.5,.28])
            size = min(adult.width, adult.height)
            cx,cy = adult.width*focus[0], adult.height*focus[1]
            left = max(0,min(adult.width-size,round(cx-size/2)))
            top = max(0,min(adult.height-size,round(cy-size/2)))
            portrait = adult.crop((left,top,left+size,top+size)).resize((512,512),Image.Resampling.LANCZOS)
            portraits.alpha_composite(portrait,(512*index,0))
            piece = figure(mini)
            pieces.alpha_composite(piece,(256*index,0))
            previews.append((key, adult, piece))
            output.append({'id':key,'full':destination.relative_to(ROOT).as_posix(),
                           'sheet':group['sheet'],'slot':index,
                           'full_sha256':hashlib.sha256(destination.read_bytes()).hexdigest()})
        portraits.save(ROOT/'assets/art/expansion'/(group['sheet']+'.png'))
        pieces.save(ROOT/'assets/art/pieces'/(group['sheet']+'.png'))
    if not allow_partial and (len(all_ids)!=84 or len(set(all_ids))!=84):
        raise ValueError('Every one of the 84 identities must have its own adult and miniature artwork')
    record['prepared'] = output
    PRODUCTION.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n','utf-8')
    if previews:
        contact = Image.new('RGB',(1400,270*((len(previews)+6)//7)),'#e9e3d7')
        draw = ImageDraw.Draw(contact)
        for i,(key,adult,mini) in enumerate(previews):
            x,y=i%7*200,i//7*270
            adult.thumbnail((145,232),Image.Resampling.LANCZOS)
            contact.paste(adult,(x+(146-adult.width)//2,y+4),adult)
            mini=mini.resize((76,76),Image.Resampling.LANCZOS)
            contact.paste(mini,(x+119,y+163),mini)
            draw.text((x+3,y+247),key,fill='#20303b')
        contact.save(ROOT/record.get('preview', 'docs/release/cast-v063.webp'),quality=88)
    print(f'{len(all_ids)} adult portraits and matching chibi figures prepared')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--allow-partial',action='store_true')
    args=parser.parse_args()
    prepare(args.allow_partial)
