# offline-deploy-pipeline

> **半自动运维技能**：AI 干重活（探测、规划、生成脚本、校验），人在强制暂停点做决策（软件栈确认、交付放行）。

离线环境部署脚本流水线：**探测目标服务器环境 → 规划 → 生成 fetch 制备脚本与 install 离线安装脚本 → 静态校验 → 交付**。覆盖「有网机制包 → U 盘摆渡 → 离线机安装」全流程，支持 yum/dnf 与 apt/dpkg 双路线。

这是一个 [ZCode](https://zcode.ai) Skill。安装后 **ZCode 自己就是执行引擎**：读 `SKILL.md` 流程、调用本目录 Python 工具、按规则生成组件脚本——不依赖任何外部程序（无 Java、无数据库、无服务端）。

## 快速开始

```bash
# 安装（仓库同名即技能目录名，clone 即装）
git clone git@github.com:Ryu2u/offline-deploy-pipeline.git ~/.zcode/skills/offline-deploy-pipeline

# 升级
cd ~/.zcode/skills/offline-deploy-pipeline && git pull
```

重启 ZCode 会话后生效。对它说：

- 「离线部署 redis 到那台 centos 机器」
- 「目标机不能联网，帮我制备离线安装包」
- 「生成 fetch/install 脚本」

## 它会怎么干活（八阶段）

```
① 探测      collect.sh 送到目标机执行 → parse_result.py 出画像
            （os_id / arch / package_manager / glibc / 磁盘 / 已装包）
② 软件栈确认 [强制暂停点]  展示探测摘要+软件清单，等你确认
③ 规划      按 plan-protocol 出四段协议，按 OS 命中 gotchas 陷阱库注入上下文
④ 组件生成  逐软件写 <slug>_fetch.sh / <slug>_install.sh（严格 POSIX sh）
⑤ 拼装      assemble_total.py 确定性生成 total_fetch.sh / total_install.sh
            ——total 脚本永不由模型生成，防幻觉改写闭包求解逻辑
⑥ 静态校验  validate_scripts.py：sh -n / 文件集 / 角色防颠倒 / 禁用模式，
            FAIL 未清零不得交付
⑦ Docker 成对验收（可选）  fetch 容器联网制备 → install 容器 --network none
            断网安装 → 同容器幂等重跑
⑧ 交付      2N+2 个脚本 + fetch-artifacts.tar.gz + 使用手册
```

现场使用：有网机（与目标机同 OS ID/版本/架构）跑 `total_fetch.sh` → 产物与脚本包一起摆渡 → 离线目标机跑 `total_install.sh`。全部脚本支持 `--dry-run` / `--rollback`，幂等可重跑。

## 资产结构

```
SKILL.md                      # 八阶段流程 + 强制暂停点 + 安全红线
scripts/collect.sh            # 探测脚本（单文件 POSIX sh，零依赖，dash/busybox 兼容）
scripts/parse_result.py       # 结果包 → 画像要点与 apt/yum 路由
scripts/assemble_total.py     # total 脚本确定性拼装器（内置健康探针映射表）
scripts/validate_scripts.py   # 交付前强制静态检查
templates/                    # total 模板 ×4（yum/apt × fetch/install）
references/                   # 规划协议 / 组件规则 / 管线契约 / gotchas 陷阱知识库
```

## 安全红线（摘要）

- 依赖闭包必须由包管理器求解：yum 空安装根 `--downloadonly` / apt 空 dpkg 状态 `--download-only`；**严禁手工 pin 版本号**
- install **严禁联网**、严禁自建 `rpm -Uvh` / `dpkg -i` 事务，必须本地仓库 yum / `apt-get --no-download`
- 组件不碰 total 的领地（rpms/ debs/ repodata/ MANIFEST.txt）
- 回滚只撤销本次变更，严禁删先于脚本存在的服务数据目录

## 已验证场景

八类中间件 Docker 成对验收矩阵（联网 fetch 制备 → `--network none` 容器断网安装 → 同容器幂等重跑，全部 RC=0）：

| 中间件 | apt (debian 12) | yum (almalinux 8) |
|---|---|---|
| jdk 17 / nginx | ✅ | ✅ |
| redis 7.0 | ✅ PONG | — |
| postgresql 15 | ✅ pg_isready | — |
| rabbitmq 3.x | ✅ beam.smp | — |
| elasticsearch 8.19（官方源补源） | — | ✅ 进程 + HTTP 9200 |
| jq（EPEL 补源，xz 元数据） | — | ✅ |
| mysql8 | ⚠️ Mac Docker 无法执行 mysqld 二进制（执行层环境限制；离线闭包与安装事务已验证，需真实 Linux 服务器复验进程级结果） | 同左 |

第三方源补源机制：组件 fetch 把 `.repo` 写入 `conf/<slug>/`，total_fetch 自动枚举纳入闭包求解（EPEL xz、Elastic gz 双格式实测）。

## 来源

资产提取自 EnvProbe（task_engine）项目的实测沉淀：`collect.sh` 为其清单编译产物；total 模板转译自其 `SoftwareScriptBundleAssembler`（含四处实测修复：sed 分隔符错配、install 仓库补 `module_hotfixes=1`、EPEL8 xz 元数据、ES JPMS 主类匹配）；gotchas 知识库来自双容器实证报告。
