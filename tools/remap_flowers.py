#!/usr/bin/env python3
"""Pixel-preserving Mocha flower adaptation. Requires Pillow.

Usage: python tools/remap_flowers.py '/path/to/8flowers by Brysiaa.png'
The purchased source stays external; existing game sprites are never overwritten.
Five growing frames are reversed into seed -> mature order, scaled 2x with
nearest-neighbor sampling, with alpha and silhouettes preserved exactly.
"""
from pathlib import Path
import argparse
import colorsys
import json
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
COLORS = dict(re.findall(r'pub const (\w+): u32 = 0x([0-9a-f]{6})ff;', (ROOT / 'src/theme.zig').read_text()))
MOCHA = {name: tuple(bytes.fromhex(value)) for name, value in COLORS.items()}
# Rows 0, 1 and 6 underlie the game's existing Rose, Tulip and Dandelion
# redraws. Keep those save IDs and artwork; append the other five species.
NEW = [(2, 'pink_tulip'), (3, 'poppy'), (4, 'hyacinth'), (5, 'red_tulip'), (7, 'iris')]


def family(rgb):
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    if s < .13: return 'neutral'
    if .16 < h < .48: return 'leaf'
    if .48 <= h < .7: return 'blue'
    if .7 <= h < .85: return 'purple'
    if .85 <= h < .95: return 'pink'
    if .045 < h <= .16: return 'gold'
    return 'red'

RAMPS = {
    'leaf': ['surface1', 'green', 'green'],
    'blue': ['surface2', 'blue', 'lavender', 'text'],
    'purple': ['surface2', 'mauve', 'lavender', 'pink'],
    'pink': ['red', 'maroon', 'pink', 'rosewater'],
    'gold': ['overlay0', 'peach', 'yellow', 'rosewater'],
    'red': ['surface2', 'red', 'maroon', 'flamingo'],
    'neutral': ['crust', 'surface1', 'subtext0', 'text', 'rosewater'],
}


def remap(source):
    mapping = {}
    result = source.copy()
    for row in range(8):
        # Rank only living colors within each flower; dark withered petals
        # must not push the living flower's entire ramp into white highlights.
        live = source.crop((0, row*16, 80, (row+1)*16))
        visible = {p[:3] for p in live.get_flattened_data() if p[3]}
        rowmap = {}
        for name, ramp in RAMPS.items():
            colors = sorted((rgb for rgb in visible if family(rgb) == name), key=lambda c: .2126*c[0]+.7152*c[1]+.0722*c[2])
            for i, rgb in enumerate(colors):
                rowmap[rgb] = MOCHA[ramp[round(i*(len(ramp)-1)/max(1,len(colors)-1))]]
        for y in range(row*16, (row+1)*16):
            for x in range(96):
                pixel = source.getpixel((x,y))
                if not pixel[3]: continue
                rgb = pixel[:3]
                mapped = rowmap.get(rgb)
                if mapped is None:
                    mapped = min(MOCHA.values(), key=lambda c: sum((c[i]-rgb[i])**2 for i in range(3)))
                mapping[(row, rgb)] = mapped
                result.putpixel((x,y), (*mapped, pixel[3]))
    assert result.getchannel('A').tobytes() == source.getchannel('A').tobytes()
    assert all(p[:3] in MOCHA.values() for p in result.get_flattened_data() if p[3])
    return result, mapping


def strips(sheet):
    for row, name in NEW:
        strip = Image.new('RGBA', (160, 32))
        for frame, col in enumerate([4,3,2,1,0]):
            src = sheet.crop((col*16,row*16,(col+1)*16,(row+1)*16))
            strip.paste(src.resize((32,32),Image.Resampling.NEAREST), (frame*32,0))
        yield name, strip


def comparison(source, variants, destination):
    scale=4; cw=420; header=66; rowH=82
    canvas=Image.new('RGB',(cw*len(variants),header+rowH*8+80),MOCHA['base'])
    draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype(str(ROOT/'sprites/baloo2.ttf'),22)
    small=ImageFont.truetype(str(ROOT/'sprites/baloo2.ttf'),17)
    for col,(label,im) in enumerate(variants):
        draw.text((col*cw+16,12),label,fill=MOCHA['text'],font=font)
        for row in range(8):
            y=header+row*rowH
            draw.text((col*cw+8,y+20),str(row+1),fill=MOCHA['subtext0'],font=small)
            rowimg=im.crop((0,row*16,96,(row+1)*16)).resize((384,64),Image.Resampling.NEAREST)
            canvas.paste(rowimg,(col*cw+30,y),rowimg)
    draw.text((18,header+rowH*8+10),'Original silhouettes and growth frames preserved. All previews use nearest-neighbor enlargement.',fill=MOCHA['subtext1'],font=small)
    canvas.save(destination)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('source',type=Path);args=parser.parse_args()
    source=Image.open(args.source).convert('RGBA')
    if source.size != (96,128): raise ValueError('Expected the original 96x128 sheet')
    out=ROOT/'output/flower-comparison';out.mkdir(parents=True,exist_ok=True)
    result,mapping=remap(source);result.save(out/'mocha-semantic.png')
    (out/'palette-map.json').write_text(json.dumps({str(row)+':#'+bytes(k).hex():'#'+bytes(v).hex() for (row,k),v in mapping.items()},indent=2)+'\n')
    for name,strip in strips(result): strip.save(ROOT/'sprites'/f'{name}.png')
    variants=[('Original pack',source),('Mocha: semantic ramps',result)]
    for label,name in [('Catppify: Mocha / 0','catppify-mocha-0.png'),('Catppify: Mocha / 4','catppify-mocha-4.png'),('Factory: current Mocha','factory-mocha.png'),('Factory: stock palette','factory-stock.png')]:
        if (out/name).exists(): variants.append((label,Image.open(out/name).convert('RGBA')))
    comparison(source,variants,out/'comparison.png')
    print('Wrote five new sprite strips; original artwork unchanged; alpha and Mocha palette verified.')

if __name__=='__main__': main()
