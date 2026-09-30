#!/usr/bin/env python3
"""validate_scripts.py — 脚本包交付前的强制静态检查。

检查项（FAIL 阻断交付，WARN 需人工确认）：
  1. 文件集：total_fetch.sh + total_install.sh + 每 slug 的 <slug>_fetch.sh / <slug>_install.sh
  2. 语法：逐文件 sh -n
  3. 结构：#!/bin/sh 开头、set -eu、--dry-run / --rollback 支持、DEPLOY_FAIL 错误输出
  4. 角色防颠倒：total_fetch 含 run_fetch，total_install 含 run_install
  5. 占位符/标记段残留（total 文件）
  6. 组件 install 脚本禁止包管理器安装事务与联网安装
  7. 组件脚本 bashism 粗检（[[ ]]、<<<、数组、local）
  8. 组件 fetch 不触碰 total 管理的仓库目录/清单/归档（写操作）

用法:
    python3 validate_scripts.py <脚本目录> [--bundle bundle.json]
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

SLUG_FILE = re.compile(r"([a-z0-9]+(?:_[a-z0-9]+)*)_(fetch|install)\.sh$")
PLACEHOLDER = re.compile(r"@@[A-Z_]+@@")
MARKER = re.compile(r"#@@(?:BEGIN|END)_[A-Z_]+@@")

INSTALL_BAN = [
    (re.compile(r"\b(?:yum|dnf)\s+(?:-[^ ]*\s+)*install\b"), "FAIL",
     "组件 install 禁止 yum/dnf 安装（统一包事务由 total_install 执行）"),
    (re.compile(r"\brpm\s+-[iU]", ), "FAIL", "组件 install 禁止裸 rpm -i/-U 事务"),
    (re.compile(r"\b(?:apt|apt-get)\s+(?:-[^ ]*\s+)*install\b"), "FAIL",
     "组件 install 禁止 apt/apt-get 安装（统一包事务由 total_install 执行）"),
    (re.compile(r"\bdpkg\s+-i\b"), "FAIL", "组件 install 禁止 dpkg -i 安装"),
    (re.compile(r"\b(?:curl|wget)\b[^\n]*\b(?:https?|ftp)://"), "WARN",
     "组件 install 出现联网下载（离线安装脚本不应联网，请确认用途）"),
]

FETCH_BAN = [
    (re.compile(r">\s*\"?\$?ARTIFACT_DIR/(?:rpms|debs)/"), "FAIL",
     "组件 fetch 禁止写入 total 管理的包仓库目录 rpms/ debs/"),
    (re.compile(r"(?:rm|mv|cp|touch|mkdir)[^\n]*MANIFEST\.txt"), "FAIL",
     "组件 fetch 禁止修改 MANIFEST.txt"),
    (re.compile(r"(?:tar|gzip|rm)[^\n]*fetch-artifacts\.tar\.gz"), "FAIL",
     "组件 fetch 禁止创建/修改/删除 fetch-artifacts.tar.gz"),
]

BASHISM = [
    (re.compile(r"\[\[\s"), "FAIL", "bashism：[[ ]]（POSIX sh 应用 test/[）"),
    (re.compile(r"\s<<<\s"), "FAIL", "bashism：here-string <<<"),
    (re.compile(r"=\([^)]"), "FAIL", "bashism：数组赋值 =( )"),
    (re.compile(r"^\s*local\s+\w+=", re.M), "WARN", "local 非 POSIX 保证（dash 支持，busybox 受限）"),
]

results = []


def check(level: str, msg: str) -> None:
    results.append((level, msg))


def validate_file(path: Path, role: str) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    name = path.name

    if not lines or lines[0] != "#!/bin/sh":
        check("FAIL", f"{name}: 缺少 #!/bin/sh 首行")
    if not re.search(r"^set -eu\b", text, re.M):
        check("FAIL", f"{name}: 缺少 set -eu")
    if "--dry-run" not in text:
        check("FAIL", f"{name}: 不支持 --dry-run")
    if "--rollback" not in text:
        check("FAIL", f"{name}: 不支持 --rollback")
    if "DEPLOY_FAIL" not in text:
        check("FAIL", f"{name}: 错误未按 DEPLOY_FAIL: <CODE> 约定输出")

    r = subprocess.run(["sh", "-n", str(path)], capture_output=True, text=True)
    if r.returncode != 0:
        check("FAIL", f"{name}: sh -n 语法错误: {r.stderr.strip().splitlines()[-1] if r.stderr else ''}")

    if role == "total_fetch" and "run_fetch" not in text:
        check("FAIL", f"{name}: total_fetch 缺少 run_fetch（角色颠倒或模板损坏）")
    if role == "total_install" and "run_install" not in text:
        check("FAIL", f"{name}: total_install 缺少 run_install（角色颠倒或模板损坏）")
    if role.startswith("total"):
        if PLACEHOLDER.search(text):
            check("FAIL", f"{name}: 残留未替换占位符 {sorted(set(PLACEHOLDER.findall(text)))}")
        if MARKER.search(text):
            check("FAIL", f"{name}: 残留模板标记段 {sorted(set(MARKER.findall(text)))}")

    if role == "component_install":
        for pat, level, msg in INSTALL_BAN:
            m = pat.search(text)
            if m:
                check(level, f"{name}: {msg}（命中: {m.group(0).strip()[:60]}）")
    if role == "component_fetch":
        for pat, level, msg in FETCH_BAN:
            m = pat.search(text)
            if m:
                check(level, f"{name}: {msg}（命中: {m.group(0).strip()[:60]}）")
    if role.startswith("component"):
        for pat, level, msg in BASHISM:
            m = pat.search(text)
            if m:
                check(level, f"{name}: {msg}（命中: {m.group(0).strip()[:40]}）")


def main() -> None:
    ap = argparse.ArgumentParser(description="脚本包交付前静态检查")
    ap.add_argument("directory", type=Path, help="脚本包目录")
    ap.add_argument("--bundle", type=Path, help="bundle.json（提供 slug 集，可选）")
    args = ap.parse_args()

    d = args.directory
    if not d.is_dir():
        die(f"目录不存在: {d}")
    total_fetch, total_install = d / "total_fetch.sh", d / "total_install.sh"
    if not total_fetch.is_file():
        check("FAIL", "缺少 total_fetch.sh")
    if not total_install.is_file():
        check("FAIL", "缺少 total_install.sh")

    if args.bundle and args.bundle.is_file():
        import json
        bundle = json.loads(args.bundle.read_text(encoding="utf-8"))
        slugs = [c["slug"] for c in bundle.get("components", [])]
    else:
        slugs = sorted({m.group(1) for f in d.glob("*_*.sh")
                        if (m := SLUG_FILE.fullmatch(f.name)) and m.group(1) != "total"})
    if not slugs:
        check("FAIL", "目录中未发现任何组件脚本（<slug>_fetch.sh / <slug>_install.sh）")

    for slug in slugs:
        if slug == "total":
            continue
        for kind in ("fetch", "install"):
            p = d / f"{slug}_{kind}.sh"
            if not p.is_file():
                check("FAIL", f"缺少 {p.name}")

    # 多余的组件脚本（不在 slug 集）也报告
    known = {f"{s}_{k}.sh" for s in slugs for k in ("fetch", "install")} | {
        "total_fetch.sh", "total_install.sh"}
    for f in d.glob("*.sh"):
        if f.name not in known and SLUG_FILE.fullmatch(f.name):
            check("WARN", f"{f.name}: 不在组件清单中（遗留文件？）")

    if total_fetch.is_file():
        validate_file(total_fetch, "total_fetch")
    if total_install.is_file():
        validate_file(total_install, "total_install")
    for slug in slugs:
        for kind, role in (("fetch", "component_fetch"), ("install", "component_install")):
            p = d / f"{slug}_{kind}.sh"
            if p.is_file():
                validate_file(p, role)

    fails = [m for lv, m in results if lv == "FAIL"]
    warns = [m for lv, m in results if lv == "WARN"]
    for lv, msg in results:
        print(f"[{lv}] {msg}")
    print(f"\n检查完成: {len(results)} 项（FAIL {len(fails)}，WARN {len(warns)}）")
    if fails:
        print("❌ 存在阻断项，修复后重新检查；交付禁止跳过本检查。")
        sys.exit(1)
    print("✅ 静态检查全部通过（WARN 需人工确认后放行）。")


def die(msg: str) -> None:
    print(f"validate_scripts: {msg}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
