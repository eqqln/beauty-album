# -*- coding: utf-8 -*-
"""验证 upload 接口：图片 / 视频两条通道"""
import json
import struct
import sys
import urllib.request

BASE = "https://meiyan.shengka.net/meiyan-api/?r=upload"
import os, tempfile
TOKEN = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tok.txt")).read().strip()
TMP = tempfile.gettempdir()


def make_mp4(path):
    """构造一个 finfo 能认出来的最小 mp4（ftyp box）"""
    ftyp = b"isom" + struct.pack(">I", 0x200) + b"isomiso2avc1mp41"
    box = struct.pack(">I", 8 + len(ftyp)) + b"ftyp" + ftyp
    # 再塞一个空的 mdat，凑点体积
    mdat = struct.pack(">I", 8 + 1024) + b"mdat" + b"\x00" * 1024
    with open(path, "wb") as f:
        f.write(box + mdat)


def make_png(path):
    import zlib
    w = h = 2
    raw = b""
    for _ in range(h):
        raw += b"\x00" + b"\xff\x00\x00" * w

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def upload(path, name, mime):
    data = open(path, "rb").read()
    bd = "----wbTest"
    body = b""
    body += ("--%s\r\n" % bd).encode()
    body += ('Content-Disposition: form-data; name="file"; filename="%s"\r\n' % name).encode()
    body += ("Content-Type: %s\r\n\r\n" % mime).encode()
    body += data
    body += ("\r\n--%s--\r\n" % bd).encode()
    req = urllib.request.Request(BASE, data=body, method="POST")
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", "multipart/form-data; boundary=%s" % bd)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def main():
    make_png(os.path.join(TMP, "_t.png"))
    make_mp4(os.path.join(TMP, "_t.mp4"))
    make_mp4(os.path.join(TMP, "_bad.mov"))

    print("== PNG 图片")
    print(upload(os.path.join(TMP, "_t.png"), "test.png", "image/png"))
    print("== MP4 视频")
    print(upload(os.path.join(TMP, "_t.mp4"), "test.mp4", "video/mp4"))
    print("== MOV 视频")
    print(upload(os.path.join(TMP, "_bad.mov"), "test.mov", "video/quicktime"))

    # 非视频伪装成 mp4：应被 finfo 拦下
    open(os.path.join(TMP, "_fake.mp4"), "wb").write(b"this is definitely not a video" * 100)
    print("== 伪装 mp4（应报错）")
    print(upload(os.path.join(TMP, "_fake.mp4"), "fake.mp4", "video/mp4"))

    # 不支持的扩展名
    print("== .txt（应报错）")
    print(upload(os.path.join(TMP, "_t.png"), "test.txt", "text/plain"))


if __name__ == "__main__":
    main()
