# VelaShell 插件工具链

[VelaShell](https://github.com/joesdu/VelaShell) 的插件开发工具链:契约 SDK、测试替身、
构建/打包支持、`vela-plugin` 命令行、`dotnet new` 模板。

三个仓库各管一摊,别串:

| 仓库 | 管什么 |
| --- | --- |
| [joesdu/VelaShell](https://github.com/joesdu/VelaShell) | 主程序(宿主) |
| **本仓库** | 插件 SDK 与工具链:凡是插件作者会引用、会安装、会照抄的东西 |
| [joesdu/velashell-plugins](https://github.com/joesdu/velashell-plugins) | 第一方插件本身(AI / Redis / S3 / Telnet / HelloWorld 示例) |

## 仓库里有什么

| 目录 | 内容 | 产物 |
| --- | --- | --- |
| `plugin-sdk/VelaShell.PluginSdk` | 契约程序集:插件入口、能力接口、`plugin.json` 清单模型、`.vpx` 容器格式 | NuGet `VelaShell.PluginSdk` |
| `plugin-sdk/VelaShell.PluginSdk.Testing` | 测试替身:`TestPluginContext` 与各能力的内存实现,不起宿主也能测插件 | NuGet `VelaShell.PluginSdk.Testing` |
| `plugin-sdk/VelaShell.PluginSdk.Build` | 插件工程**只需引用这一个包**:MSBuild targets + 打包器 + Avalonia 版本锁 | NuGet `VelaShell.PluginSdk.Build` |
| `tools/VelaShell.Plugin.Cli` | `vela-plugin`:校验清单、打 `.vpx`、签名/验签、挂载到本机宿主调试 | NuGet `VelaShell.Plugin.Cli`(dotnet tool) |
| `templates/` | `dotnet new` 模板:`velaplugin`(基础)/ `velaplugin-ui`(带 Avalonia 面板) | NuGet `VelaShell.Plugin.Templates` |
| `tests/` | 契约测试:`.vpx` 容器格式与 `plugin.json` 清单解析 | — |
| `scripts/` | `Set-Version.ps1`:把版本号写进仓库里所有落点(发版时由流水线自动跑) | — |

## 快速上手(写自己的插件)

```bash
dotnet new install VelaShell.Plugin.Templates
dotnet new velaplugin-ui -n MyPlugin --publisher acme --authorName "Your Name"
cd MyPlugin
dotnet build -t:PackVpx          # 出 bin/vpx/*.vpx
```

细节看 [`docs/dev-guide.md`](docs/dev-guide.md);命令行手册看 [`docs/cli.md`](docs/cli.md);
发布与签名看 [`docs/publishing.md`](docs/publishing.md);API 面看 [`docs/sdk-reference.md`](docs/sdk-reference.md)。
英文版在 [`docs-en/`](docs-en/)。

插件系统的**架构蓝图**(进程模型、IPC 协议、权限系统、威胁模型等)留在主仓库的
[`docs/plugins/`](https://github.com/joesdu/VelaShell/tree/main/docs/plugins) —— 那些描述的是
宿主侧的实现,读它是为了理解插件为什么长这样,写插件本身用不到。

## 在本仓库里开发

```bash
dotnet build VelaShell.PluginToolchain.slnx
dotnet test  VelaShell.PluginToolchain.slnx -c Debug
```

`-c Debug` 不是随手写的:Release 会打开强名称签名,而签名程序集的 `InternalsVisibleTo`
要求友元也用同一把钥匙签名 —— 测试程序集不满足,用 Release 跑测试会在白盒用例上
当场 CS0122。本地没有 `VelaShell.snk` 也就构建不了 Release,这是预期的
(密钥不入库,CI 从 `STRONG_NAME_KEY` 机密还原)。

### 改了 SDK,想在真实插件上试一下

第一方插件在 [joesdu/velashell-plugins](https://github.com/joesdu/velashell-plugins),
它从 nuget.org 引用本仓库发的包 —— 与第三方插件走的是同一条路,所以本地联调要先出包:

```powershell
# 本仓库:打一个带 -dev 后缀的版本
foreach ($p in @('plugin-sdk/VelaShell.PluginSdk', 'plugin-sdk/VelaShell.PluginSdk.Build', 'plugin-sdk/VelaShell.PluginSdk.Testing')) {
  dotnet pack "$p/$(Split-Path $p -Leaf).csproj" -c Release -o artifacts/nuget -p:VelaSdkVersion=1.5.0-dev
}
# 插件仓库:打开 nuget.config 里那条注释掉的本地源,然后
dotnet build VelaShell.Plugins.slnx -p:VelaSdkVersion=1.5.0-dev
```

或者用 `vela-plugin dev init` 把某个插件工程挂到宿主的开发插件根上(见 `docs/cli.md`)。

## 版本与发布

SDK 版本(`Directory.Build.props` 的 `VelaSdkVersion`)与**主程序版本解耦** ——
主程序发 1.2.3 不代表插件契约变了,插件作者也不该为了跟版本号而重新编译。

发版方式:**在 GitHub 上发布 Release**(标签形如 `v1.5.0`),流水线会把五个包推上 nuget.org。
第一方插件的分发物不在这里发 —— 那是 [joesdu/velashell-plugins](https://github.com/joesdu/velashell-plugins)
自己的 Release 流水线的事。

版本号**发版前在本地落好、随功能改动一起合进 `main`**:跑一次
[`scripts/Set-Version.ps1`](scripts/Set-Version.ps1),它会把版本写进 `Directory.Build.props`、
两个模板的 `template.json`、`VelaPluginApi.SdkVersion` 与四份文档的版本横幅 /
`PackageReference` 片段 —— 十来处,一处都不用自己记。

```powershell
pwsh scripts/Set-Version.ps1 1.5.0            # 落盘
pwsh scripts/Set-Version.ps1 1.5.0 -Check     # 只报告(CI 每次 push/PR 都跑这个)
```

流水线在构建之前也会按 Release 标签跑一遍同样的脚本,所以**产物版本号永远等于标签**,
即便有人忘了上一步;但它只改 runner 上的工作区,**不回写仓库** —— 真忘了的话,
`main` 上的版本同步体检会红,照它给的命令本地补一个 PR 即可。

完整流程、版本号纪律(`AssemblyVersion` 主版本 == `apiLevel`)与 NuGet 可信发布的配置见
[`docs/release-process.md`](docs/release-process.md)。

## 与主程序的两个硬约束

1. **Avalonia 版本**必须与宿主一致。本仓库是这个版本号的权威(`VelaAvaloniaVersion`),
   `VelaShell.PluginSdk` 包把它导出成 `VelaSdkPinnedAvaloniaVersion`,主仓库在自己的
   构建期核对。漂了的表现是跨 ALC 的控件类型对不上,而且要等到用户装上插件才炸。
2. **强名称签名**用与宿主同一把钥匙。宿主 Release 下是签名程序集,而签名程序集
   不能引用未签名程序集。

## 许可

AGPL-3.0-only,与主仓库一致。商业授权见主仓库的 `LICENSE-COMMERCIAL.md`。
