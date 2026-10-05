# 组件脚本生成规则（<slug>_fetch.sh / <slug>_install.sh）

每个软件产出两个 POSIX sh 脚本；`total_fetch.sh` 和 `total_install.sh` 由 `scripts/assemble_total.py` 确定性拼装，**不由模型生成**。

## 全局硬规则（两个脚本都适用）

1. 以 `#!/bin/sh` 开头，兼容 dash/busybox sh；**禁用** bash 数组、`[[ ]]`、`local`、进程替换、here-string
2. 设置 `set -eu`（或 `set -euo pipefail` 的 POSIX 等价形式；pipefail 非 POSIX 时用 `set -eu` 并对管道谨慎处理）
3. 必须支持 `--dry-run`、`--rollback`，且幂等可重跑
4. 错误必须非零退出并输出 `DEPLOY_FAIL: <CODE> <安全说明>` 到 stderr
5. 从环境变量 `ARTIFACT_DIR` 读取共享制品目录；未传时使用脚本同目录下 `artifacts`
6. 所有目录/运行用户/版本及启停命令以用户确认的软件配置为准，不擅自发明
7. 官方源和镜像源均可使用；下载前逐 URL 预检，失败时输出具体 URL
8. 变量集中文件头声明；变更前快照（被改文件 `.bak`、安装清单落盘）

## 回滚安全硬规则

- `--rollback` 只允许撤销**本脚本自身执行过的变更**。删除任何目录前必须先证明该目录由本脚本本次执行创建（例如安装前写入标记文件再核对），**严禁删除先于脚本存在的目录**——尤其 `/var/lib/mysql`、`/var/lib/nginx`、`/var/lib/redis` 等服务数据目录，安装失败同样不得删除
- 严禁停止、禁用或卸载先于脚本执行已存在的服务；`systemctl stop/disable/mask` 只允许作用于本脚本新装并启动的服务
- `--dry-run` 与 `--rollback` 路径不得安装任何软件包，不得修改包管理器与系统服务状态

## <slug>_fetch.sh（制备脚本）

只下载该软件负责的**源码包、JDK、配置**，写入共享 `$ARTIFACT_DIR` 的 `src/`、`jdk/`、`conf/`：

- 标准系统包（RPM/.deb）及其依赖由 total_fetch 统一闭包制备，组件 fetch **不下载**它们
- 不能清空其他软件制品；不得修改 total_fetch 管理的包仓库目录（`rpms/`、`debs/`）、repodata、本地包索引、`MANIFEST.txt` 或 `fetch-artifacts.tar.gz`
- 目标仓库缺包时为闭包贡献额外软件源：repodata 完整下载到 `src/<slug>/`，`.repo` 文件写 `conf/<slug>/`（见 plan-protocol.md）
- **yum 路线额外约束**：若脚本声明已有的 `file://` YUM 仓库，必须保留其 repodata 元数据校验信息。任何步骤改写 `primary.xml.gz` 或 `repomd.xml` 时，都必须让 primary 条目中的 checksum、open-checksum、size、open-size 与落盘文件内容一致；禁止全局删除 checksum/open-checksum，也不得保留与元数据不符的 size/open-size。total_fetch 会在临时副本中复核并修复 primary 条目，组件原始制品必须保持不变
- 逐源预检并记录具体 URL 与结果；目标架构与包管理器标记为架构无关（noarch）的包均允许

## <slug>_install.sh（离线安装脚本）

total_install 已通过 yum（本地 RPM 仓库）或 `apt-get --no-download`（本地 .deb 仓库）安装统一包清单；本脚本**只做目录、配置、初始化、启动和真实健康检查**：

- **不得执行 yum、dnf、rpm、apt、apt-get、dpkg 或任何联网安装**（yum 目标与 apt 目标同等禁止）
- 安装必须真正启动服务并做进程或端口健康检查；**不可因 systemd 不可用而假报成功**
- 独立运行时也要检查所需制品、已安装包与前置服务，任何失败非零退出
- 服务未启动或健康检查失败必须非零退出，不能以警告代替成功

## 常见陷阱（节选自 gotchas，完整库见 gotchas-kb.yaml）

- 严禁凭记忆硬编码 rpm/deb 版本号——版本必须运行时从仓库索引解析（`auto`）
- CentOS 7 官方源已归档（vault.centos.com），目录结构 `7.9.2009/` 易写错，URL 中 `+` 须编码为 `%2B`
- mysqld 必须 `--user=mysql` 启动；归档自检必须把符号链接算进成员集合（Temurin JDK 自带 205 个 legal 软链）
- el8 上游模块包（mysql-server/nginx/redis…）依赖 platform:el8 流，需 `module_hotfixes=1` 按普通包求解
- **最小系统/容器没有 procps**：`pgrep` 可能不存在（redis 等服务包不依赖 procps），进程健康检查必须带 `/proc/[0-9]*/comm` 扫描兜底（total 模板的 `process_running` 即此实现）。2026-09-30 debian:12 容器实测
- **容器内 policy-rc.d 拒绝服务自启**：apt 安装成功但服务不会自动启动属预期，组件 install 必须自己负责启动（systemctl 不可用时直接守护化拉起，pidfile 目录如 `/var/run/redis/` 需先 mkdir）

## 数据库类组件实测补充（2026-09-30）

- mysql/mariadb 初始化幂等：判据用"系统库目录是否存在"（`[ -d /var/lib/mysql/mysql ]`）而非"数据目录是否为空"——中断的半初始化会留下 aria_log/ibdata 而无系统库，直接重跑 `--initialize` 会报非空目录错误，应识别后清理重试
- mysqld 必须 `--user=mysql` 启动（gotcha 既有条目）；容器无 systemd 时 `mysqld --user=mysql` 后台拉起 + `mysqladmin -uroot ping` 等待循环（initialize-insecure 后 root 无密码）
- PostgreSQL（debian）：postinst 已自动 initdb，容器内用 `pg_ctlcluster 15 main start`；健康检查 `pg_isready -q`
- RabbitMQ：erlang 启动 10-40s，健康等待循环 ≥60s；进程名 beam.smp

## 多发行版实测补充（2026-10-06，10 OS 矩阵）

- **redis 包名差异**：el8/9 仓库服务包名是 `redis`（redis-server 是文件不是包），deb 系是 `redis-server`——bundle 包名按路线区分
- **fetch 机准备基线**：apt 系预装 dpkg-dev；rocky/openeuler 预装 findutils createrepo_c；el8/9 系按发行版换源（见 gotchas el8-el9-repo-layout-variants）；debian 11 用 archive 归档源
- **ubuntu 画像 os_version 为主版本**（22）而 fetch 机 VERSION_ID 带点版本（22.04）——apt 模板已改主版本匹配，生成 bundle 时直接用画像值即可
