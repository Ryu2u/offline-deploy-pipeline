# 离线部署管线契约（精简版）

源自 task_engine `docs/specs/deploy-pipeline-v1.md` §2.1/§2.2，是脚本包结构与校验的**单一事实来源**。

## 脚本包组成（2N+2）

一个含 N 个软件的交付共 4 类文件：

```
total_fetch.sh              # 确定性拼装（assemble_total.py）
total_install.sh            # 确定性拼装（assemble_total.py）
<slug>_fetch.sh             # 每软件一个，AI 按组件规则生成
<slug>_install.sh           # 每软件一个，AI 按组件规则生成
```

- `slug`：仅小写字母、数字、下划线（`[a-z0-9]+(_[a-z0-9]+)*`）；不得为 `total`；不得重复；依赖环在生成前失败
- 每软件需有可执行健康探针 `process_name`（进程名）；未配置时按内置映射兜底：mysql→mysqld、redis→redis-server、nginx→nginx、postgresql/postgres→postgres、rabbitmq→beam.smp、kafka→kafka.Kafka(java)、elasticsearch→org.elasticsearch.bootstrap.Elasticsearch(java)、jdk→无

## 制品包接口契约（fetch 与 install 必须遵守同一布局）

- 制品包唯一文件名 `fetch-artifacts.tar.gz`；归档根直接包含 `rpms/`、`debs/`、`src/`、`jdk/`、`conf/`、`MANIFEST.txt`，**不得再套一层目录**；五个目录必须存在，无对应制品时可空
- `install.sh` 将制品包解压到脚本目录下 `$SD/artifacts` 并设 `ARTIFACT_DIR="$SD/artifacts"`；解包后五项必须直接位于 `$ARTIFACT_DIR` 根
- 唯一哈希清单名 `MANIFEST.txt`：内容仅为 `sha256sum -c` 可直接读取的标准 SHA-256 记录（哈希、两个空格、相对 `$ARTIFACT_DIR` 的路径），只涵盖五目录内**常规文件**；不记录目录与 MANIFEST.txt 自身
- 校验必须从 `$ARTIFACT_DIR` 内执行 `sha256sum -c MANIFEST.txt`；**不得**生成/引用 `SHA256SUMS` 或第二份清单；不得用单数目录名 `rpm/`、`deb/`
- **符号链接**：制品目录允许软链（JDK legal 树离不开它），但 `MANIFEST.txt` 只列常规文件；软链正确性由「归档成员集合」与「软链目标安全」保证——成员类型只允许常规文件/目录/软链，软链目标必须是相对路径且解析后仍落在制品根内。fetch 归档成员自检必须把软链算进期望集合（`find … \( -type f -o -type l \)`）
- 有软件组件的交付**必须**产出至少含一个实际制品文件的 `fetch-artifacts.tar.gz`，不得按"无制品空操作"放行

## RPM 闭包（yum/dnf 路线，硬性规则）

依赖闭包由目标发行版自己的包管理器求解，**不由脚本手写**：

1. 求解前确保每个启用仓库的 repomd.xml primary 元数据摘要与落盘文件一致；远程镜像 primary.xml.gz 注入 xml:base 后必须重算并更新 checksum/open-checksum/size/open-size；组件 file:// 仓库先复制到临时副本再校验修复，不改写组件原始制品
2. 用**空 installroot** 求解全量传递闭包：`yum --installroot=<空目录> --releasever=<目标大版本> --downloadonly --downloaddir=<rpms> install <目标包>`；空 rpmdb 才能让闭包自洽（非空 rpmdb 会把"本机已装"当作满足来源，掩盖缺口）
3. 对最终 `rpms/` 生成 `rpms/repodata/`（createrepo_c，缺失先装）；repodata 是离线求解事务的唯一依据，照常列入 MANIFEST.txt 与归档
4. install **不得**自己计算升级/未装清单再拼 `rpm -Uvh` 事务；必须把 `rpms/` 当本地仓库用 yum 求解：`yum -c <生成.conf> --disablerepo='*' --enablerepo=<本地仓库> --nogpgcheck -y install <目标包名>`。禁止裸 `rpm -i/-U`、`--nodeps`、`--force`、`--skip-broken`

实测依据：整包强推 `rpm -Uvh` 会被镜像自带包的精确版本锁定打破而整体失败；yum 对"已装且满足"的包不动、只升级真正被要求换版本的包，幂等重跑退出码 0。

## APT 闭包（apt/dpkg 路线，硬性规则）

1. fetch 端必须确认自身 OS ID、版本和 dpkg 架构与目标画像匹配（不匹配 fail-fast）
2. 临时空 dpkg 状态 + 目标机软件源 + `apt-get --download-only --reinstall --no-install-recommends` 求解完整强依赖闭包，制品写入 `debs/`；不得把其他发行版或架构的 .deb 混入
3. 对最终 `debs/` 生成 `Packages` 与 `Packages.gz` 索引（dpkg-scanpackages；fetch 机需预装 dpkg-dev）
4. install 将唯一软件源指向 `debs/` 本地 flat repository，`apt-get --no-download --no-install-recommends install <目标包名>`；没有本地闭包必须失败，**不得联网回退**

## 交付与使用方式

1. 有网机器（与目标机同 OS ID/版本/架构）执行 `total_fetch.sh` → 产出 `fetch-artifacts.tar.gz`（与脚本包同目录）
2. `fetch-artifacts.tar.gz` + 全部脚本共 2N+3 个文件一起摆渡（U 盘等）到离线目标机
3. 目标机执行 `total_install.sh`：解包校验 → 离线包事务 → 按依赖顺序组件 install → 健康检查
4. `total_fetch.sh`/`total_install.sh` 均支持 `--dry-run`、`--rollback`；install 幂等可重跑

## Docker 成对验收（可选，本机有 Docker 时）

- 验收镜像按「目标 OS + 主版本 + 架构」精确映射，**不近似回退**。常用白名单：`centos:7`、`almalinux:8/9`、`rockylinux:8/9`、`debian:11/12`、`ubuntu:22.04/24.04`、`openeuler/openeuler:22.03-lts-sp3`、Kylin V10 SP3（社区镜像）。目标不在白名单时判"不支持"，不得猜近似镜像
- 流程：fetch 容器（默认 bridge 网络）跑 `total_fetch.sh` 制备归档 → install 容器（`--network none`）跑 `total_install.sh` → **同容器再跑一遍**验证幂等（换容器等于重跑首装，验证不了幂等）
- 验收容器能力集需等价于真实 root 最小必要集并含 CAP_KILL（缺它时 `kill -0 <pid>` 探测他人服务得 EPERM，健康检查假失败）
- 资源上限建议 cpu=2、memory=5g、pids-limit=512，避免服务因限制起不来产生假失败
