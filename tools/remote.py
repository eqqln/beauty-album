#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
远程部署工具（不依赖 SFTP，走 exec + base64 管道）

用法：
  python tools/remote.py info
  python tools/remote.py run "<shell command>"
  python tools/remote.py push <local_dir_or_file> <remote_dir> [--exclude a,b] [--owner www:www]
  python tools/remote.py put  <local_file> <remote_file> [--owner www:www]

连接参数来自环境变量：REMOTE_HOST / REMOTE_PORT / REMOTE_USER / REMOTE_PASS
"""
import base64
import io
import os
import sys
import tarfile
import time

import paramiko

HOST = os.environ.get("REMOTE_HOST", "")
PORT = int(os.environ.get("REMOTE_PORT", "22"))
USER = os.environ.get("REMOTE_USER", "ubuntu")
PASS = os.environ.get("REMOTE_PASS", "")


def connect(retries=3):
    last = None
    for i in range(retries):
        try:
            c = paramiko.SSHClient()
            c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            c.connect(hostname=HOST, port=PORT, username=USER, password=PASS,
                      timeout=25, banner_timeout=25, auth_timeout=25,
                      look_for_keys=False, allow_agent=False)
            return c
        except Exception as e:
            last = e
            time.sleep(2 + i * 2)
    raise last


def run(client, cmd, quiet=False):
    stdin, stdout, stderr = client.exec_command(cmd, timeout=600)
    out = stdout.read().decode("utf-8", "ignore")
    err = stderr.read().decode("utf-8", "ignore")
    code = stdout.channel.recv_exit_status()
    if not quiet:
        if out:
            print(out, end="" if out.endswith("\n") else "\n")
        if err.strip():
            print("[stderr] " + err.strip(), file=sys.stderr)
        print(f"[exit {code}]")
    return code, out, err


def tar_bytes(path, excludes):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        if os.path.isfile(path):
            tar.add(path, arcname=os.path.basename(path))
        else:
            base = os.path.abspath(path)
            for root, dirs, files in os.walk(base):
                dirs[:] = [d for d in dirs if d not in excludes and not d.startswith(".git")]
                for f in files:
                    if f in excludes:
                        continue
                    full = os.path.join(root, f)
                    rel = os.path.relpath(full, base).replace("\\", "/")
                    tar.add(full, arcname=rel)
    return buf.getvalue()


def _send_stdin(client, cmd, payload: bytes):
    stdin, stdout, stderr = client.exec_command(cmd, timeout=900)
    for i in range(0, len(payload), 65536):
        stdin.write(payload[i:i + 65536])
        stdin.flush()
    stdin.channel.shutdown_write()
    out = stdout.read().decode("utf-8", "ignore")
    err = stderr.read().decode("utf-8", "ignore")
    code = stdout.channel.recv_exit_status()
    return code, out, err


def push(client, local, remote_dir, excludes, owner):
    """把目录/文件打包上传并解压到 remote_dir"""
    data = tar_bytes(local, excludes)
    b64 = base64.b64encode(data)
    owner_cmd = f"; sudo chown -R {owner} {remote_dir}" if owner else ""
    inner = ("import sys,base64,tarfile,io,os;"
             "tarfile.open(fileobj=io.BytesIO(base64.b64decode(sys.stdin.buffer.read())))"
             ".extractall(os.environ['DEST'])")
    cmd = (f"sudo mkdir -p {remote_dir} && "
           f"DEST={remote_dir} sudo -E python3 -c \"{inner}\"{owner_cmd} && echo PUSH_OK")
    code, out, err = _send_stdin(client, cmd, b64)
    if "PUSH_OK" in out:
        print(f"pushed {len(data)/1024:.1f} KB -> {remote_dir}")
        return
    raise SystemExit(f"push failed ({code}): {out} {err}")


def put_file(client, local, remote, owner=None):
    """上传单个文件到指定路径"""
    with open(local, "rb") as f:
        b64 = base64.b64encode(f.read())
    owner_cmd = f" && sudo chown {owner} {remote}" if owner else ""
    cmd = (f"sudo mkdir -p {os.path.dirname(remote)} && "
           f"sudo bash -c 'base64 -d > {remote}'{owner_cmd} && echo PUT_OK")
    code, out, err = _send_stdin(client, cmd, b64)
    if "PUT_OK" in out:
        print(f"put {local} -> {remote}")
        return
    raise SystemExit(f"put failed ({code}): {out} {err}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    action = sys.argv[1]
    args = [a for a in sys.argv[2:] if not a.startswith("--")]
    excludes = set()
    owner = None
    for i, a in enumerate(sys.argv):
        if a == "--exclude":
            excludes = set(x.strip() for x in sys.argv[i + 1].split(",") if x.strip())
        if a == "--owner":
            owner = sys.argv[i + 1]

    client = connect()
    try:
        if action == "info":
            run(client, "whoami; uname -a; df -h / | tail -1")
        elif action == "run":
            run(client, args[0])
        elif action == "push":
            push(client, args[0], args[1], excludes, owner)
        elif action == "put":
            put_file(client, args[0], args[1], owner)
        else:
            print(__doc__)
            return 1
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
