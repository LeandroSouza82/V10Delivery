import sys
from pathlib import Path
try:
    from PIL import Image
except Exception as e:
    print('PIL_MISSING')
    print(str(e))
    sys.exit(2)

if len(sys.argv) < 2:
    print('USAGE: python tools/check_icon_margin.py path/to/image.png')
    sys.exit(1)

p = Path(sys.argv[1])
if not p.exists():
    print('MISSING_FILE')
    sys.exit(3)

im = Image.open(p).convert('RGBA')
w, h = im.size
alpha = im.split()[-1]
bbox = alpha.getbbox()
if bbox is None:
    print('ALL_TRANSPARENT_OR_EMPTY')
    sys.exit(4)
left, upper, right, lower = bbox
pad_left = left
pad_top = upper
pad_right = w - right
pad_bottom = h - lower
pad_horizontal = pad_left + pad_right
pad_vertical = pad_top + pad_bottom
pad_horizontal_pct = round(pad_horizontal / w * 100, 1)
pad_vertical_pct = round(pad_vertical / h * 100, 1)

print(f'BBOX={bbox}; SIZE={w}x{h}')
print(f'PADDING left={pad_left} top={pad_top} right={pad_right} bottom={pad_bottom}')
print(f'PADDING_PERCENT horizontal={pad_horizontal_pct}% vertical={pad_vertical_pct}%')

# Heuristic: if more than 20% padding in any direction, suggest cropping
if pad_horizontal_pct > 20 or pad_vertical_pct > 20:
    print('SUGGEST_CROP: true')
    sys.exit(5)
else:
    print('SUGGEST_CROP: false')
    sys.exit(0)
