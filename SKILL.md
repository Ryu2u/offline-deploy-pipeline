---
name: offline-deploy-pipeline
description: 离线环境部署脚本流水线：探测目标服务器环境 → 规划 → 生成 fetch 制备脚本与 install 离线安装脚本 → 静态校验交付。覆盖"有网机制包 → U 盘摆渡 → 离线机安装"全流程，支持 yum/dnf 与 apt/dpkg 双路线
version: 1.0.0
category: deploy
---

## 描述

本技能封装离线环境软件部署脚本的全生命周期制备能力：**探测目标机环境 → 生成规划 → 逐软件生成 fetch/install 成对脚本 → 确定性拼装 total 入口 → 静态校验 → 交付**。产物为一组自包含 POSIX sh 脚本（2N+2 个文件），在有网机器跑 `total_fetch.sh` 制备 `fetch-artifacts.tar.gz`，与脚本包一起摆渡到离线目标机跑 `total_install.sh` 完成安装。

本技能源自 task_engine（EnvProbe）项目沉淀的方法论与实测资产（gotchas 知识库、闭包求解模板），total 脚本由 `assemble_total.py` 确定性拼装，**不由模型生成**，防止幻觉改写闭包求解与离线安装逻辑。

## 触发条件

- 用户要求"离线部署"、"离线安装 xxx"、"生成 fetch/install 脚本"、"制备离线安装包"
- 用户提到"目标机不能联网，怎么装软件"、"摆渡部署"、"U 盘部署"
- 用户要求"先探测服务器环境再生成部署脚本"
- 用户提供 envprobe 结果包要求分析并出部署方案

## 目录资产

| 资产 | 路径 | 用途 |
|---|---|---|
| 探测脚本 | `scripts/collect.sh` | 单文件 POSIX sh，零依赖，目标机直接执行（源自 task_engine 编译产物） |
| 结果解析器 | `scripts/parse_result.py` | 解析结果包 → 画像要点（os_id/arch/package_manager/glibc/磁盘/已装包） |
| total 拼装器 | `scripts/assemble_total.py` | 从 bundle.json 确定性生成 total_fetch.sh / total_install.sh（yum/apt 双路线模板） |
| 静态检查器 | `scripts/validate_scripts.py` | 交付前强制检查：sh -n、文件集、角色、禁用模式、bashism |
| 规划协议 | `references/plan-protocol.md` | 规划段纯文本协议（===ARTIFACTS=== 等）与包源证据判定规则 |
| 组件规则 | `references/component-rules.md` | <slug>_fetch.sh / <slug>_install.sh 生成规则与回滚安全硬规则 |
| 管线契约 | `references/pipeline-spec.md` | 制品包结构、RPM/APT 闭包硬性规则、Docker 验收方法 |
| 陷阱知识库 | `references/gotchas-kb.yaml` | 17 条双容器实测 OS 陷阱（按 os_id/version/package_manager 命中注入） |

## 执行流程

### 阶段①：环境探测

1. 把 `scripts/collect.sh` 交付到目标机执行（scp/U 盘/粘贴均可），产出 `envprobe-*.tar.gz`
   - 本机即目标机时直接 `sh scripts/collect.sh` 执行
2. 解析结果包：
   ```bash
   python3 scripts/parse_result.py <结果包.tar.gz> --json   # 机器可读
   python3 scripts/parse_result.py <结果包.tar.gz>          # 人类可读摘要
   ```
3. 路由判定：`host_summary.package_manager` 必须为 `yum` 或 `apt`，否则**终止并告知**（仅支持 Linux + apt/yum/dnf）
4. 采集失败项对应字段在后续规划中一律标"未验证"，不得臆断

### 阶段②：软件栈确认 [强制暂停点]

向用户收集并确认（以编号列表展示）：

| 字段 | 说明 | 示例 |
|---|---|---|
| slug | 软件稳定 ID（小写字母数字下划线） | `nginx` |
| 名称/版本 | 版本可 auto（运行时从仓库索引解析） | nginx / auto |
| packages | 该软件需要的系统包名（不含版本） | `nginx` |
| install_dir / config_dir / run_user | 部署约定 | `/usr/local/nginx` 等 |
| process_name | 健康探针进程名（mysql→mysqld 等有内置映射） | `nginx` |
| start_cmd / stop_cmd | 启停方式 | `systemctl start nginx` |

展示探测摘要 + 软件清单 + 组件依赖顺序（被依赖者排前），**等待用户明确确认后方可继续**。

### 阶段③：规划

1. 按 `references/plan-protocol.md` 输出规划文本（===ARTIFACTS===/===ASSUMPTIONS===/===RISKS===/===VERIFY===/===RPM_PACKAGES=== 或 ===APT_PACKAGES===/===END===）
2. 按画像 `os_id`/`os_version`/`package_manager` 从 `references/gotchas-kb.yaml` 命中条目，注入规划上下文（来源不匹配的 gotcha 不得引用）
3. 校验：包名白名单正则、包管理器与画像一致、依赖顺序正确

### 阶段④：组件脚本生成

逐软件生成 `<slug>_fetch.sh` 与 `<slug>_install.sh`，**严格遵守 `references/component-rules.md`**：
- fetch 只管该软件的 src/jdk/conf 制品与缺包补源（repodata→`src/<slug>/`，`.repo`→`conf/<slug>/`），标准系统包归 total
- install 只做目录/配置/初始化/启动/真实健康检查，**严禁执行任何包管理器安装或联网**
- 回滚安全硬规则：只撤销本次变更，严禁删先于脚本存在的目录、动已存在服务

### 阶段⑤：确定性拼装 total 脚本 [禁止手工生成]

写 `bundle.json` 后调用拼装器（**total 脚本永远由它生成，不要手写**）：

```bash
python3 scripts/assemble_total.py --bundle bundle.json --output-dir <交付目录>
```

bundle.json 示例：
```json
{
  "package_manager": "yum",
  "os_id": "centos", "os_version": "7", "architecture": "x86_64", "releasever": "7",
  "components": [
    {"slug": "nginx", "packages": ["nginx"], "process_name": "nginx"},
    {"slug": "redis", "packages": ["redis"], "process_name": "redis-server"}
  ]
}
```

### 阶段⑥：静态验证 [强制，不可跳过]

```bash
python3 scripts/validate_scripts.py <交付目录> --bundle bundle.json
```

FAIL 必须修复后重跑直至通过；WARN 需向用户说明并确认。

### 阶段⑦：Docker 成对验收 [可选]

本机有 Docker 且用户要求时，按 `references/pipeline-spec.md`「Docker 成对验收」节执行：
fetch 容器（联网）跑 total_fetch → install 容器（`--network none`）跑 total_install → **同容器**幂等重跑。镜像按目标 OS+版本+架构精确映射，不近似回退。

### 阶段⑧：交付

输出交付物清单与使用手册：

1. 交付目录内 2N+2 个脚本 + bundle.json（存档）
2. 使用步骤：有网机（与目标机同 OS ID/版本/架构）执行 `total_fetch.sh` → 产出 `fetch-artifacts.tar.gz` → 与全部脚本一起摆渡 → 离线机执行 `total_install.sh`
3. 提示 `--dry-run` / `--rollback` 用法与幂等特性

## 安全红线

1. **闭包必须由包管理器求解**：yum 用空 installroot `--downloadonly`，apt 用空 dpkg 状态 `--download-only`；**严禁手工 pin 版本号或手写依赖清单**
2. **install 严禁自建 rpm -Uvh / dpkg -i 事务**：必须本地仓库 yum / `apt-get --no-download` 求解
3. **install 严禁联网**：无本地闭包必须失败，不得回退网络源
4. **组件不碰 total 的领地**：rpms/、debs/、repodata、MANIFEST.txt、fetch-artifacts.tar.gz
5. **强制暂停点不可跳过**：阶段②软件栈确认必须获得用户明确确认
6. **静态验证不可跳过**：validate_scripts.py FAIL 未清零不得交付
7. **回滚安全**：只撤销本脚本本次变更；严禁删除先于脚本存在的服务数据目录（/var/lib/mysql 等）
8. **证据判定**：无实测证据（探测输出/HTTP 状态/包管理器查询）不得断言"源不可访问"或"包不存在"，只能标"未验证"
9. **脚本 POSIX sh**：禁 bashism（`[[ ]]`、数组、进程替换）；变量引用一律 `"${VAR}"`
10. **版本号运行时解析**：严禁凭记忆硬编码 rpm/deb 版本

## 注意事项

- **collect.sh 升级**：为 task_engine manifests 编译产物（build_hash 锁定）。manifests 变更后需在 task_engine 重新编译并替换本文件；解析格式见其 `docs/specs/result-package-v1.md`
- fetch 机必须与目标机 **同 OS ID、同版本、同架构**（apt 路线 total_fetch 内置强校验；yum 路线靠 releasever+arch 对齐）
- 组件 fetch 声明 file:// 仓库时必须保留 repodata 校验信息（primary 的 checksum/open-checksum/size/open-size 与落盘一致），total_fetch 会在临时副本复核
- 生成的组件脚本中所有目录/用户/启停以阶段②用户确认为准，不擅自发明
- 幂等验收必须在**同一容器**连续跑两遍（换容器等于重跑首装）
- 已知平台差异：CentOS/RHEL 服务名 sshd/crond，Debian/Ubuntu 为 ssh/cron；Kylin V10 注意 ks10-adv-* 源与 el8 上游 module_hotfixes=1

## 历史迭代

### 1.0.0（2026-09-30）

初始版本 — 从 task_engine（EnvProbe）提取探测→fetch→install 业务链路：
collect.sh 探测资产、gotchas 知识库、total 拼装模板（yum/apt）、规划协议与组件规则
