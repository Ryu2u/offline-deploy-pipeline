# offline-deploy-pipeline

离线环境部署脚本流水线技能（ZCode Skill）：**探测目标服务器环境 → 规划 → 生成 fetch 制备脚本与 install 离线安装脚本 → 静态校验交付**。覆盖「有网机制包 → U 盘摆渡 → 离线机安装」全流程，支持 yum/dnf 与 apt/dpkg 双路线。

技能运行时 **ZCode 自己就是执行引擎**：读 `SKILL.md` 流程、调用本目录 Python 工具、按规则生成组件脚本——不依赖任何外部程序。

## 安装

```bash
git clone <本仓库URL> ~/.zcode/skills/offline-deploy-pipeline
```

重启 ZCode 会话后生效。触发词：「离线部署 xxx」「生成 fetch/install 脚本」「制备离线安装包」。

## 升级

```bash
cd ~/.zcode/skills/offline-deploy-pipeline && git pull
```

## 资产结构

```
SKILL.md                      # 八阶段流程：探测→确认[暂停点]→规划→组件生成→拼装→静态校验→Docker验收→交付
scripts/collect.sh            # 探测脚本（单文件 POSIX sh，目标机直接执行）
scripts/parse_result.py       # 结果包 → 画像要点（os/arch/package_manager/glibc 路由）
scripts/assemble_total.py     # total_fetch/total_install 确定性拼装（防模型幻觉）
scripts/validate_scripts.py   # 交付前强制静态检查
templates/                    # total 模板 ×4（yum/apt × fetch/install）
references/                   # 规划协议 / 组件规则 / 管线契约 / gotchas 陷阱知识库
```

## 安全红线（摘要）

- 依赖闭包必须由包管理器求解（yum 空安装根 `--downloadonly` / apt 空 dpkg 状态 `--download-only`），严禁手工 pin 版本
- install 严禁联网、严禁自建 `rpm -Uvh`/`dpkg -i` 事务
- 组件脚本 POSIX sh（禁 bashism），支持 `--dry-run`/`--rollback`，幂等可重跑

## 已验证场景

八类中间件 Docker 成对验收矩阵（联网 fetch 制备 → `--network none` 容器断网安装 → 同容器幂等重跑）：

| 中间件 | apt(debian 12) | yum(almalinux 8) |
|---|---|---|
| jdk 17 / nginx / redis / postgresql / rabbitmq | ✅ | ✅(jdk/nginx) |
| elasticsearch 8.19（官方源补源） | — | ✅ 进程+HTTP 9200 |
| jq（EPEL 补源，xz 元数据） | — | ✅ |
| mysql8 | ⚠️ Mac Docker 无法执行 mysqld 二进制（环境限制，离线安装事务已验证） | 同左 |

## 来源与致谢

资产提取自 [EnvProbe](../task_engine)（task_engine）项目的实测沉淀：collect.sh 为其清单编译产物，total 模板转译自 `SoftwareScriptBundleAssembler`，gotchas 知识库来自双容器实证报告。
