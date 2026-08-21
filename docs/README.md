# 文档索引

写 VelaShell 插件需要的东西都在这里。英文版见 [`../docs-en/`](../docs-en/)。

| 文档 | 内容 |
| --- | --- |
| [dev-guide.md](dev-guide.md) | **开发指南**:快速上手、清单、生命周期、能力 API、隔离模式、测试、部署、性能纪律 |
| [cli.md](cli.md) | **`vela-plugin` 手册**:开发内环(`dev init`)、体检(`doctor`)、校验/打包/签名、宿主启动参数 |
| [publishing.md](publishing.md) | **打包与发布**:Release 构建、`.vpx`、签名与信任、发布到[插件商店](http://market.easilynet.top)、CI 出包 |
| [sdk-reference.md](sdk-reference.md) | **SDK 参考**:包结构、入口契约、能力域一览、SDK 版本历史、测试替身、装载模型 |
| [release-process.md](release-process.md) | **本仓库自己怎么发版**:Release 流程、NuGet 可信发布配置、版本号纪律、与主仓库的联动 |

第一次写插件的话,按 `dev-guide.md` → `cli.md` → `publishing.md` 的顺序读。

## 不在这里的东西

插件系统的**架构蓝图**(进程模型、IPC 协议、权限系统、UI 扩展、威胁模型、路线图,
编号 01–15 的那批)留在主仓库:
<https://github.com/joesdu/VelaShell/tree/main/docs/plugins>

那些文档描述的是**宿主侧**的设计与实现 —— 读它是为了理解插件为什么长这样,
写插件本身用不到。
