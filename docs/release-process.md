# 发版流程

本仓库一次发布同时产出两类东西,共用同一个版本号:

| 产物 | 去处 | 谁消费 |
| --- | --- | --- |
| 五个 NuGet 包 | nuget.org | 插件作者(`dotnet new` / `PackageReference`)、VelaShell 主仓库 |
| `velashell-plugins-<版本>.zip` | 本仓库 Release 资产 | VelaShell 主仓库的发布流水线(解进安装包的 `plugins/`) |
| 各插件的 `.vpx` | 本仓库 Release 资产 | 用户手工安装、插件商店 |

## 一、怎么发

**发 Release,不再打 `sdk-v*` 标签。**

```
GitHub → Releases → Draft a new release
  Tag:    v1.4.0          ← 版本号取自这里(去掉前导 v)
  Title:  1.4.0
  Notes:  …
  [ ] Set as a pre-release   ← 预发布版本(1.4.0-preview.1)勾上
  Publish release
```

发布动作触发 [`.github/workflows/release.yml`](../.github/workflows/release.yml),它按顺序做:

1. 解析并**校验**版本号 —— 标签必须能化成合法 SemVer。这一步是硬拦截:
   nuget.org 的包版本**不可删除、不可覆盖**,标签打错一次就永久占掉一个版本号。
2. 从 `STRONG_NAME_KEY` 机密还原 `VelaShell.snk`。
3. 跑全量测试(`-c Debug`,理由见下方"为什么测试必须 Debug")。
4. `dotnet pack` 五个包,版本经 `-p:VelaSdkVersion=` 覆盖。
5. **模板端到端冒烟**:装模板 → 生成工程 → 还原 → 构建 → 出 `.vpx` → 用刚打出的
   CLI 读回容器 → 确认共享程序集没漏进插件输出目录。
6. 打插件分发包与各插件的 `.vpx`。
7. NuGet 可信发布换密钥 → 推送五个包。
8. 插件分发物 `gh release upload --clobber` 挂到该 Release。

手动兜底:Actions 页面 → Release → Run workflow,填标签即可补跑
(推送用 `--skip-duplicate`、上传用 `--clobber`,重复跑幂等)。勾 `dryRun` 只验不推。

### 从旧的打标签方式迁移过来的注意点

* 旧标签 `sdk-v1.3.1` 这类**不再触发任何工作流**,留着不碍事,但别再用。
* 旧的 `nuget.yml` 已随主仓库的拆分一并移除;流水线现在叫 `release.yml`——
  **nuget.org 上的可信发布策略必须跟着改**,见下一节。

## 二、NuGet 可信发布(Trusted Publishing)怎么调

推送不存 API Key:工作流拿本次运行的 GitHub OIDC 令牌去 nuget.org 换一把 1 小时有效的
临时密钥。nuget.org 那边靠一条**策略**决定"哪个仓库的哪个工作流可以代表我推包"。

拆库改了三件事里的两件,所以策略必须动:

| 策略字段 | 拆库前 | 拆库后 |
| --- | --- | --- |
| Policy owner(策略归属) | `joes_du` | 不变 |
| Repository Owner | `joesdu` | 不变 |
| **Repository** | `VelaShell` | `velashell-plugin-toolchain` |
| **Workflow File** | `nuget.yml` | `release.yml` |
| Environment | 空 | 空(工作流没用 GitHub Environments) |

### 建议做法:新建一条策略,而不是改旧的

nuget.org 在**第一次成功发布**时会把 GitHub 的 repository ID 与 owner ID 记进策略,
用来把它钉死在那个仓库上(防"删库重建同名仓库"的复活攻击)。旧策略已经钉在
`joesdu/VelaShell` 的仓库 ID 上了 —— 换个仓库名不是改个字符串的事。所以:

1. 登录 nuget.org → 右上角用户名 → **Trusted Publishing**。
2. **Add** 一条新策略:
   * Policy name:随意,例如 `velashell-plugin-toolchain`
   * Policy owner:`joes_du`(策略对**该账号名下的全部包**生效,五个包共用这一条,不必开五条)
   * Repository Owner:`joesdu`
   * Repository:`velashell-plugin-toolchain`
   * Workflow File:`release.yml` —— **只填文件名**,不要写 `.github/workflows/` 前缀
   * Environment:留空
3. 确认旧的那条(指向 `VelaShell` / `nuget.yml`)已经**删除** —— 主仓库不再推任何包,
   留着就是一条多余的信任面。
4. 发一次 Release 把新策略跑通。

### ⚠️ 新策略有 7 天窗口

私有仓库上新建的策略是"**临时激活**"状态,7 天内必须成功发布一次,否则自动失效
(可以随时重开窗口)。原因就是上面说的仓库 ID:没有一次真实发布,nuget.org 拿不到
那两个 ID,也就没法把策略永久钉住。所以**建好策略就尽快发一次**(哪怕是 preview 版)。

如果仓库是公开的,通常直接是永久激活状态,但发一次验证仍然是省事的做法。

### 换不到密钥时先看这三样

`NuGet login` 那一步失败,九成是策略对不上:

* Workflow File 还写着 `nuget.yml`;
* Repository 还写着 `VelaShell`;
* `NUGET_USER` 填成了邮箱 —— 要的是 nuget.org 的**用户名**(profile name)。
  本工作流默认取 `vars.NUGET_USER`,没配则回落到 `joes_du`。

另外 job 上的 `permissions: id-token: write` 不能少,否则 GitHub 根本不签发 OIDC 令牌。

## 三、版本号纪律

`Directory.Build.props` 的 `VelaSdkVersion` 是本仓库的默认版本,发布时由标签覆盖。
三个版本号各司其职,别混:

| 版本号 | 取值 | 作用 |
| --- | --- | --- |
| `AssemblyVersion` | `<主版本>.0.0.0` | **绑定标识**,只随主版本动 |
| `FileVersion` | `1.4.0` | 资源管理器属性页看到的 |
| `InformationalVersion` | `1.4.0-preview.1` | `vela-plugin --version` 报的 |

`AssemblyVersion` 只钉主版本,是因为插件是编译期绑到这个标识上的 ——
每发一个补丁就让它变,等于要求所有已编译插件重新绑定,毫无收益。

**主版本变了就意味着契约破了,那一刻 `apiLevel` 必须同步 +1**
(纪律:`AssemblyVersion` 主版本 == `apiLevel`)。这样老宿主在**发现期**就按 `apiLevel`
干净拒载,而不是等装载时抛一个看不懂的绑定异常。

### 发新版时要一起改的地方

* `Directory.Build.props` 的 `VelaSdkVersion`(默认值,PR 验证用它)
* `templates/content/*/.template.config/template.json` 的 `sdkVersion` 默认值 ——
  忘了改的话生成出来的工程会去还原旧包。构建期由 `VerifyTemplateSdkVersion`(VELA1004)拦下。

## 四、和主仓库的联动

主仓库 [joesdu/VelaShell](https://github.com/joesdu/VelaShell) 通过两个 pin 消费本仓库:

```xml
<!-- 主仓库 Directory.Build.props -->
<VelaSdkVersion>1.4.0</VelaSdkVersion>              <!-- SDK 包版本 -->
<VelaPluginsBundleVersion>1.4.0</VelaPluginsBundleVersion>  <!-- 插件分发包所在的 Release 标签 -->
```

所以顺序是:**先发本仓库的 Release,再去主仓库把两个 pin 抬上去**。
主仓库发版时会从
`https://github.com/joesdu/velashell-plugin-toolchain/releases/download/v<版本>/velashell-plugins-<版本>.zip`
下载插件分发包解进安装包的 `plugins/`;这个地址取不到东西,主仓库的发布会直接失败,
不会悄悄出一个没插件的包。

主仓库还会在构建期核对自己引用的 Avalonia 与 SDK 锁定的版本是否一致
(`VerifyAvaloniaMatchesSdk`,读的是 `VelaShell.PluginSdk` 包导出的
`VelaSdkPinnedAvaloniaVersion`)。要动 Avalonia 版本,两个仓库必须同一波发布。

## 五、为什么测试必须 Debug

Release 会打开强名称签名(见 `plugin-sdk/Directory.Build.props`),而签名程序集的
`InternalsVisibleTo` 必须带友元公钥、友元也得用同一把钥匙签名 —— 测试程序集两条都不满足。
用 Release 跑测试就等于丢掉友元关系,白盒用例引用的 internal 类型当场 CS0122
(而且只会报第一个:声明期出错后 Roslyn 直接跳过方法体编译,后面还有一批同类错误没露面)。

这些用例验的是契约、包格式与插件逻辑,与优化级别无关,Debug 等价;且 Debug 的 `obj`/`bin`
与 Pack 用的 Release 目录彼此隔离,不会把未签名产物混进要发布的包里。
