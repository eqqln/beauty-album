"""生成 App 图标：玫瑰渐变底 + 白色相框 + 心形。"""
import math
import os
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)

top = (250, 208, 214)
bot = (190, 112, 130)
for y in range(S):
    t = y / (S - 1)
    r = int(top[0] + (bot[0] - top[0]) * t)
    g = int(top[1] + (bot[1] - top[1]) * t)
    b = int(top[2] + (bot[2] - top[2]) * t)
    d.line([(0, y), (S, y)], fill=(r, g, b))

# 相框：白色圆角矩形，中间挖空
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([236, 236, 788, 788], radius=112, fill=255)
md.rounded_rectangle([300, 300, 724, 724], radius=72, fill=0)
img.paste((255, 255, 255), (0, 0), mask)

# 心形
cx, cy, scale = 512, 520, 9.2
pts = []
for i in range(240):
    t = 2 * math.pi * i / 240
    x = 16 * math.sin(t) ** 3
    y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
    pts.append((cx + x * scale, cy - y * scale))
d.polygon(pts, fill=(214, 118, 138))

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "BeautyAlbum", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
img.save(os.path.normpath(out), "PNG")
print("icon written", img.size, os.path.normpath(out))
