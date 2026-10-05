#!/usr/bin/env python3
"""parse_result.py — 解析 collect.sh 产出的环境探测结果包，输出环境画像要点。

输入：envprobe-<指纹8>-<时间戳>-<版本>.tar.gz（result-package-v1 格式），
或已解开的结果根目录（含 MANIFEST.txt / status.env / data/）。

输出：画像要点（路由字段 os_id / os_version / arch / package_manager / glibc、
资源摘要、已装包概况），--json 输出机器可读 JSON 供后续生成阶段引用。

用法:
    python3 parse_result.py <结果包.tar.gz|结果目录> [--json]
"""
import argparse
import base64
import io
import json
import re
import sys
import tarfile
from pathlib import Path

MAX_ENTRIES = 5000
MAX_TOTAL_BYTES = 200 * 1024 * 1024
META_KEYS = {"rc", "status", "started_at", "ended_at", "truncated", "encoding", "no_timeout"}


def die(msg: str) -> None:
    print(f"parse_result: {msg}", file=sys.stderr)
    sys.exit(1)


def load_package(source: Path) -> dict:
    """返回 {相对路径: bytes}。含防护：条目数、总字节、路径逃逸。"""
    files = {}
    if source.is_dir():
        for p in sorted(source.rglob("*")):
            if p.is_file():
                files[str(p.relative_to(source))] = p.read_bytes()
        return files
    if not source.is_file():
        die(f"结果包不存在: {source}")
    try:
        with tarfile.open(source, "r:gz") as tf:
            members = tf.getmembers()
            if len(members) > MAX_ENTRIES:
                die(f"条目数超限（{len(members)} > {MAX_ENTRIES}），拒绝解析")
            total = sum(m.size for m in members if m.isfile())
            if total > MAX_TOTAL_BYTES:
                die(f"解压总字节超限（{total} > {MAX_TOTAL_BYTES}），拒绝解析")
            root = members[0].name.split("/")[0] if members else ""
            for m in members:
                rel = m.name
                if root and rel == root:
                    continue
                if root and rel.startswith(root + "/"):
                    rel = rel[len(root) + 1:]
                norm = Path(rel).as_posix()
                if norm.startswith("..") or "/../" in f"/{norm}/":
                    die(f"路径逃逸条目，拒绝: {m.name}")
                if m.isfile():
                    files[norm] = tf.extractfile(m).read()
    except tarfile.TarError as e:
        die(f"tar.gz 解析失败: {e}")
    if not files:
        die("包内无文件")
    return files


def parse_kv(text: str) -> dict:
    out = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


def parse_status_env(text: str) -> dict:
    """status.env：item_id|status|reason|rc|duration_ms（reason 内 \\| 与 \\\\ 反转义）。"""
    items = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = re.split(r"(?<!\\)\|", line)
        parts = [p.replace("\\|", "|").replace("\\\\", "\\") for p in parts]
        if len(parts) < 2:
            continue
        items[parts[0]] = {
            "status": parts[1] if len(parts) > 1 else "",
            "reason": parts[2] if len(parts) > 2 else "",
        }
    return items


def parse_section(raw: str):
    """data 分节文法：### BEGIN <id> / 元信息 / 内容 / ### END。返回 (meta, 内容行)。"""
    lines = raw.split("\n")
    if not lines or not lines[0].startswith("### BEGIN "):
        return None, None
    meta = {}
    idx = 1
    while idx < len(lines):
        line = lines[idx]
        if line == "### END":
            break
        if "=" in line:
            k, _, v = line.partition("=")
            if k in META_KEYS:
                meta[k] = v
                idx += 1
                continue
        break
    content_lines = lines[idx:]
    # END 后可能跟尾随空行（部分发行版 sh 的输出差异），先剥空行再剥 END
    while content_lines and content_lines[-1] == "":
        content_lines.pop()
    if content_lines and content_lines[-1] == "### END":
        content_lines = content_lines[:-1]
    if meta.get("encoding") == "b64" and content_lines:
        try:
            decoded = base64.b64decode("".join(content_lines)).decode("utf-8", "replace")
            content_lines = decoded.split("\n")
        except Exception:
            pass
    return meta, content_lines


def find_data(files: dict, item_id: str):
    for name, content in files.items():
        base = Path(name).name
        if re.fullmatch(r"\d{3}_" + re.escape(item_id) + r"\.\w+", base):
            return content.decode("utf-8", "replace")
    return None


def derive_summary(meta: dict, items: dict, data_of: dict) -> dict:
    summary = {
        "hostname": meta.get("hostname", ""),
        "fingerprint": meta.get("fingerprint", ""),
        "os_family": meta.get("os_family", ""),
        "os_id": meta.get("os_id", "unknown"),
        "os_version": meta.get("os_version", ""),
        "arch": meta.get("arch", ""),
        "package_manager": "unknown",
        "glibc": "",
        "collected_at_utc": meta.get("collected_at_utc", ""),
    }

    # 包管理器：pkg.installed 命中 rpm_qa（无 TAB，name-ver-rel.arch）还是 dpkg_l（TAB 分隔）
    pkg_raw = data_of.get("pkg.installed")
    if pkg_raw:
        first = next((l for l in pkg_raw if l.strip()), "")
        if "\t" in first:
            summary["package_manager"] = "apt"
        elif re.search(r"\.(x86_64|aarch64|noarch|i[36]86|armhfp)\b", first) or first.count("-") >= 2:
            summary["package_manager"] = "yum"
        if pkg_raw:
            summary["installed_packages_count"] = sum(1 for l in pkg_raw if l.strip())

    # glibc
    glibc_raw = data_of.get("kernel.glibc")
    if glibc_raw:
        m = re.search(r"([0-9][0-9.]*)", "\n".join(glibc_raw))
        if m:
            summary["glibc"] = m.group(1)

    # CPU 与内存（尽力而为，探测格式差异不致命）
    cpu_raw = data_of.get("cpu.info") or []
    procs = [l for l in cpu_raw if re.match(r"\s*processor\s*:", l, re.I)]
    if procs:
        summary["cpu_count"] = len(procs)
    mem_raw = data_of.get("memory.usage") or []
    for l in mem_raw:
        m = re.match(r"\s*Mem(?:Total|:)\s*:?\s*(\d+)\s*(kB?|MB?)", l, re.I)
        if m:
            val = int(m.group(1))
            unit = m.group(2).lower()
            summary["memory_mb"] = val // 1024 if unit.startswith("k") else val
            break

    # 磁盘（df -P 输出：6 列无 Type 或 7 列含 Type；过滤伪文件系统）
    disk_raw = data_of.get("disk.usage") or []
    mounts = []
    pseudo = {"tmpfs", "devtmpfs", "overlay", "squashfs", "proc", "sysfs", "cgroup", "cgroup2",
              "mqueue", "shm", "devpts", "nsfs", "efivarfs"}
    for l in disk_raw:
        parts = l.split()
        if len(parts) == 7:
            device, fstype, size_kb, used_kb, _avail, use_pct, mount = parts
        elif len(parts) == 6:
            device, size_kb, used_kb, _avail, use_pct, mount = parts
            fstype = ""
        else:
            continue
        if not device.startswith("/") or fstype in pseudo:
            continue
        mounts.append({"device": device, "mount": mount, "size_gb": round(int(size_kb) / 1048576, 1),
                       "use_pct": use_pct})
    if mounts:
        summary["disks"] = mounts[:10]
    return summary


def main() -> None:
    ap = argparse.ArgumentParser(description="解析 envprobe 结果包并输出画像要点")
    ap.add_argument("source", type=Path, help="结果包 .tar.gz 或已解开的根目录")
    ap.add_argument("--json", action="store_true", help="输出 JSON（供后续阶段引用）")
    args = ap.parse_args()

    files = load_package(args.source)
    if "MANIFEST.txt" not in files:
        die("缺少 MANIFEST.txt，不是合法结果包")
    meta = parse_kv(files["MANIFEST.txt"].decode("utf-8", "replace"))
    items = (parse_status_env(files["status.env"].decode("utf-8", "replace"))
             if "status.env" in files else {})

    data_of = {}
    for name, content in files.items():
        if name.startswith("data/"):
            text = content.decode("utf-8", "replace")
            section_meta, content_lines = parse_section(text)
            if section_meta is None:
                item_id = Path(name).stem.split("_", 1)[-1]
                items.setdefault(item_id, {"status": "failed", "reason": "malformed_section"})
                continue
            item_id = next(iter(section_meta.values()), None)
            m = re.match(r"### BEGIN (\S+)", text)
            item_id = m.group(1) if m else Path(name).stem.split("_", 1)[-1]
            data_of[item_id] = content_lines

    summary = derive_summary(meta, items, data_of)
    pm = summary["package_manager"]
    supported = summary["os_family"] == "linux" and pm in ("yum", "apt")

    result = {
        "host_summary": summary,
        "manifest": {k: meta.get(k, "") for k in (
            "format_version", "script_version", "build_hash", "collected_at_utc",
            "hostname", "fingerprint", "os_family", "os_id", "os_version", "arch",
            "item_total", "item_success", "item_skipped", "item_failed")},
        "item_status": items,
        "supported": supported,
        "route": {"package_manager": pm, "action": "继续生成流程" if supported
                  else "仅支持 Linux + apt/yum/dnf，当前目标不支持，终止"},
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    s = summary
    print("=== 环境画像要点 ===")
    print(f"主机名     : {s['hostname']}")
    print(f"指纹       : {s['fingerprint'][:16]}…")
    print(f"操作系统   : {s['os_id']} {s['os_version']}（{s['os_family']}）")
    print(f"架构       : {s['arch']}")
    print(f"包管理器   : {s['package_manager']}")
    print(f"glibc      : {s['glibc'] or '未采集/非 glibc'}")
    if "cpu_count" in s:
        print(f"CPU 逻辑核 : {s['cpu_count']}")
    if "memory_mb" in s:
        print(f"内存       : {s['memory_mb']} MB")
    if "disks" in s:
        print("磁盘挂载   :")
        for d in s["disks"]:
            print(f"  {d['device']} {d['mount']} {d['size_gb']}GB 已用 {d['use_pct']}")
    if "installed_packages_count" in s:
        print(f"已装软件包 : {s['installed_packages_count']} 个")
    failed = [k for k, v in items.items() if v.get("status") == "failed"]
    if failed:
        print(f"采集失败项 : {', '.join(failed)}（规划时相关字段标记'未验证'）")
    print(f"\n路由结论   : {'✅ ' + s['package_manager'] + ' 路线，可继续生成 fetch/install 脚本' if supported else '❌ 不支持的目标（仅 Linux + apt/yum/dnf）'}")


if __name__ == "__main__":
    main()
