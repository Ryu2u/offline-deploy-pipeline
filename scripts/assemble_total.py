#!/usr/bin/env python3
"""assemble_total.py — 从组件清单确定性拼装 total_fetch.sh / total_install.sh。

total 脚本不是 AI 生成的：组件调用序列、包名并集、健康探针分支均由本工具
从 bundle.json 按固定规则填充模板，防止模型幻觉改写闭包求解与离线安装逻辑。

用法:
    python3 assemble_total.py --bundle bundle.json --output-dir <dir> [--skill-dir <dir>]

bundle.json 格式:
    {
      "package_manager": "yum" | "apt",
      "os_id": "centos", "os_version": "7", "architecture": "x86_64",
      "releasever": "7",                      # yum 路线必填（目标大版本）
      "components": [
        {"slug": "nginx", "packages": ["nginx"], "process_name": "nginx"},
        {"slug": "myapp", "packages": ["myapp"], "process_name": "java"}   # 可省略 process_name
      ]
    }
"""
import argparse
import json
import re
import sys
from pathlib import Path

SLUG = re.compile(r"[a-z0-9]+(?:_[a-z0-9]+)*")
RPM = re.compile(r"[A-Za-z0-9][A-Za-z0-9+_.-]*")
APT = re.compile(r"[a-z0-9][a-z0-9+.-]*")
RELEASE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
TARGET_VALUE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
TARGET_VERSION_VALUE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._ -]*")
PROCESS = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.+-]*")

# 未配置 process_name 时的内置健康探针表（与 task_engine SoftwareScriptBundleAssembler 一致）
BUILTIN_PROBES = {
    "mysql": ("mysqld", False),
    "redis": ("redis-server", False),
    "nginx": ("nginx", False),
    "postgresql": ("postgres", False),
    "postgres": ("postgres", False),
    "rabbitmq": ("beam.smp", False),
    "rabbitmq_server": ("beam.smp", False),
    "kafka": ("kafka.Kafka", True),
    "elasticsearch": ("org.elasticsearch.bootstrap.Elasticsearch", True),
    "jdk": None,
}


def die(msg: str) -> None:
    print(f"assemble_total: {msg}", file=sys.stderr)
    sys.exit(1)


def load_bundle(path: Path) -> dict:
    try:
        bundle = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        die(f"读取 bundle.json 失败: {e}")
    pm = bundle.get("package_manager", "").lower()
    if pm not in ("yum", "apt"):
        die(f"模块化部署不支持包管理器: {bundle.get('package_manager')!r}（仅 yum/apt）")
    comps = bundle.get("components") or []
    if not comps:
        die("components 为空：请至少提供一个软件组件")
    slugs = []
    all_pkgs = []
    for c in comps:
        slug = c.get("slug")
        if not slug or not SLUG.fullmatch(slug) or slug == "total" or slug in slugs:
            die(f"非法或重复的软件 slug: {slug!r}")
        slugs.append(slug)
        for name in c.get("packages") or []:
            pat = APT if pm == "apt" else RPM
            if not pat.fullmatch(name):
                die(f"非法 {'APT' if pm == 'apt' else 'RPM'} 包名: {name!r}")
            all_pkgs.append(name)
    if pm == "yum":
        rv = bundle.get("releasever")
        if not rv or not RELEASE.fullmatch(str(rv)):
            die(f"yum 路线要求合法 releasever（目标大版本）: {rv!r}")
    for key in ("os_id", "architecture"):
        v = bundle.get(key)
        if not v or not TARGET_VALUE.fullmatch(str(v)):
            die(f"目标画像 {key} 缺失或格式非法: {v!r}")
    v = bundle.get("os_version")
    if v is None or not TARGET_VERSION_VALUE.fullmatch(str(v).strip()):
        die(f"目标画像 os_version 缺失或格式非法: {v!r}")
    return bundle


def probe_for(c: dict):
    configured = (c.get("process_name") or "").strip()
    slug = c["slug"]
    if configured.lower() == "none":
        return None  # 显式声明无守护进程（CLI 工具类组件，如 jq）
    if not configured:
        if slug in BUILTIN_PROBES:
            return BUILTIN_PROBES[slug]
        if slug == "jdk":
            return None
        die(f"软件 {slug} 缺少可执行健康探针；请在 bundle.json 配置 process_name")
    name = configured.rstrip("/").split("/")[-1].strip()
    if not PROCESS.fullmatch(name):
        die(f"process_name 不是可精确匹配的可执行文件名: {slug}")
    java_args = name.startswith("org.") or name == "kafka.Kafka"
    return name, java_args


MARKER_LINE = re.compile(r"#@@(?:BEGIN|END)_[A-Z_]+@@\n")


def strip_marker_sections(text: str) -> str:
    """删除成对标记段（含标记行自身）。"""
    return re.sub(r"#@@BEGIN_[A-Z_]+@@\n.*?#@@END_[A-Z_]+@@\n", "", text, flags=re.S)


def render(template: str, values: dict) -> str:
    values = {k.strip("@"): v for k, v in values.items()}
    for key, val in values.items():
        template = template.replace(f"@@{key}@@", val)
    template = MARKER_LINE.sub("", template)  # 保留段内容的场景只删标记行
    residual = sorted(set(re.findall(r"@@[A-Z_]+@@", template)))
    if residual:
        die(f"模板存在未替换占位符: {residual}")
    return template


def main() -> None:
    ap = argparse.ArgumentParser(description="确定性拼装 total_fetch.sh / total_install.sh")
    ap.add_argument("--bundle", required=True, type=Path, help="bundle.json 组件清单")
    ap.add_argument("--output-dir", required=True, type=Path, help="脚本输出目录")
    ap.add_argument("--skill-dir", type=Path, default=Path(__file__).resolve().parent.parent,
                    help="技能根目录（定位 templates/）")
    args = ap.parse_args()

    bundle = load_bundle(args.bundle)
    pm = bundle["package_manager"].lower()
    comps = bundle["components"]
    pkg_union = []
    for c in comps:
        for name in c.get("packages") or []:
            if name not in pkg_union:
                pkg_union.append(name)
    has_pkgs = bool(pkg_union)
    pkg_str = " ".join(pkg_union)

    fetch_calls = "".join(f'  run_fetch {c["slug"]} ${{MODE:+"$MODE"}}\n' for c in comps)
    fetch_rollback = "".join(f'  run_fetch {c["slug"]} --rollback\n' for c in reversed(comps))
    install_calls = "".join(f'run_install {c["slug"]} ${{MODE:+"$MODE"}}\n' for c in comps)
    install_rollback = "".join(f'  run_install {c["slug"]} --rollback\n' for c in reversed(comps))
    check_cases = []
    check_all = []
    for c in comps:
        probe = probe_for(c)
        if probe:
            name, java_args = probe
            fn = "java_process_running" if java_args else "process_running"
            check_cases.append(
                f'    {c["slug"]}) {fn} \'{name}\' || fail SERVICE_START \'{c["slug"]} process not running\' ;;')
            check_all.append(f'  check_service {c["slug"]}')
    summary_fetch = "".join(f"printf '[component] fetch {c['slug']} ok\\n'\n" for c in comps)
    summary_install = "".join(f"printf '[component] install {c['slug']} ok\\n'\n" for c in comps)
    trap = ('trap \'rm -f "$members" "$expected"; rm -rf "$WORK"\' 0' if has_pkgs
            else 'trap \'rm -f "$members" "$expected"\' 0')

    tmpl_dir = args.skill_dir / "templates"
    fetch_tmpl = (tmpl_dir / f"total_fetch_{pm}.sh.tmpl").read_text(encoding="utf-8")
    install_tmpl = (tmpl_dir / f"total_install_{pm}.sh.tmpl").read_text(encoding="utf-8")
    if not has_pkgs:  # 纯制品交付：闭包求解与离线包事务整段移除（须在 render 删除标记行之前）
        fetch_tmpl = strip_marker_sections(fetch_tmpl)
        install_tmpl = strip_marker_sections(install_tmpl)

    common = {
        "@@COMPONENT_FETCH_CALLS@@": fetch_calls.rstrip("\n"),
        "@@COMPONENT_ROLLBACK_FETCH_CALLS@@": fetch_rollback.rstrip("\n"),
        "@@COMPONENT_ROLLBACK_INSTALL_CALLS@@": install_rollback.rstrip("\n"),
        "@@COMPONENT_CHECK_SERVICE_CASES@@": "\n".join(check_cases),
        "@@COMPONENT_INSTALL_CALLS@@": install_calls.rstrip("\n"),
        # 无任何健康探针时省略整块（空 then 体是 POSIX 语法错误）
        "@@COMPONENT_CHECK_SERVICE_BLOCK@@": (
            'if [ "$MODE" != --dry-run ]; then\n' + "\n".join(check_all) + "\nfi"
            if check_all else ""),
        "@@SUMMARY_LINES@@": "__SUMMARY__",  # fetch/install 分别替换，见下
    }
    fetch_values = dict(common, **{
        "@@COMPONENT_FETCH_CALLS@@": fetch_calls.rstrip("\n"),
        "@@SUMMARY_LINES@@": summary_fetch.rstrip("\n"),
        "@@TRAP_LINE@@": trap,
        "@@RPM_PACKAGES@@": pkg_str,
        "@@PACKAGE_NAMES@@": pkg_str,
        "@@TARGET_RELEASEVER@@": str(bundle.get("releasever", "")),
        "@@TARGET_OS_ID@@": str(bundle["os_id"]).lower(),
        "@@TARGET_OS_VERSION@@": str(bundle["os_version"]).strip(),
        "@@TARGET_ARCH@@": str(bundle["architecture"]),
    })
    install_values = dict(common, **{
        "@@COMPONENT_INSTALL_CALLS@@": install_calls.rstrip("\n"),
        "@@SUMMARY_LINES@@": summary_install.rstrip("\n"),
        "@@RPM_PACKAGES@@": pkg_str,
        "@@PACKAGE_NAMES@@": pkg_str,
    })

    fetch_out = render(fetch_tmpl, fetch_values)
    install_out = render(install_tmpl, install_values)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, text in (("total_fetch.sh", fetch_out), ("total_install.sh", install_out)):
        if not text.endswith("\n"):
            text += "\n"
        p = args.output_dir / name
        p.write_text(text, encoding="utf-8")
        p.chmod(0o755)
        print(f"生成 {p}（{len(text.splitlines())} 行）")

    print("\n组件脚本仍需按 references/component-rules.md 生成：")
    for c in comps:
        print(f"  - {c['slug']}_fetch.sh / {c['slug']}_install.sh")
    print("全部就绪后运行 validate_scripts.py 做静态检查。")


if __name__ == "__main__":
    main()
