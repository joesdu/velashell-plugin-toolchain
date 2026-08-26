# 发版流程

本仓库一次发布产出五个 NuGet 包,共用同一个版本号:

| 产物 | 去处 | 谁消费 |
| --- | --- | --- |
| 五个 NuGet 包 | nuget.org | 插件作者(`dotnet new` / `PackageReference`)、VelaShell 主仓库、第一方插件仓库 |

> 第一方插件的分发物(`velashell-plugins-<版本>.zip` 与各插件的 `.vpx`)**不在这里发** ——
> 插件已搬去 [joesdu/velashell-plugins](https://github.com/joesdu/velashell-plugins),
> 那个仓库有自己的 Release 流水线与自己的版本号(`VelaPluginsVersion`)。
> 两边解耦:SDK 发 1.5.0 不代表插件必须跟着发,插件发 1.4.1 也不代表契约动了。

## 一、怎么发

**发 Release,不再打 `sdk-v*` 标签;版本号在合 `main` 之前用脚本一次落好。**

发版三步:

1. **破坏性变更才需要**先手工把 `VelaPluginApi.Level` +1 —— "契约破没破"是人的判断,
   不是版本号能推出来的,脚本刻意不代改(但会核对,对不上就拒绝发版)。
2. 本地跑一次版本号脚本,连同功能改动一起合进 `main`:

   ```powershell
   pwsh scripts/Set-Version.ps1 1.5.0
   ```

   它一次改完那十来处落点(`Directory.Build.props`、两个 `template.json`、
   `VelaPluginApi.SdkVersion`、四份文档的版本横幅与 `PackageReference` 片段),
   漏一处的后果各不相同、且大多不会在你手上暴露 —— 详见下方"版本号纪律"。

3. 在 GitHub 上发 Release:

```
GitHub → Releases → Draft a new release
  Tag:    v1.5.0          ← 版本号取自这里(去掉前导 v)
  Title:  1.5.0
  Notes:  …
  [ ] Set as a pre-release   ← 预发布版本(1.5.0-preview.1)勾上
  Publish release
```

> **2026-08-26:版本号回写 `main` 的 `sync-main` 任务已删除。** 发版本来就是
> "改完合进 `main` → 在 Release 页面发布",版本号在第 2 步已经落定,回写在正常路径上
> 永远是空操作 —— 为此常驻一个需要 `contents` + `pull-requests` 写权限的 job
> (还得配 PAT 才能让它开的 PR 亮绿灯),不划算。忘了第 2 步的兜底改由 CI 的
> **版本同步体检**(`Set-Version.ps1 -Check`,每次 push/PR 都跑)承担:它会在 `main` 上
> 红一次,照它给的命令跑一遍再补一个 PR 即可。同时可选机密 `VERSION_SYNC_TOKEN`
> 也一并作废,仓库机密里若还留着可以清掉。

发布动作触发 [`.github/workflows/release.yml`](../.github/workflows/release.yml),它按顺序做:

1. 解析并**校验**版本号 —— 标签必须能化成合法 SemVer。这一步是硬拦截:
   nuget.org 的包版本**不可删除、不可覆盖**,标签打错一次就永久占掉一个版本号。
2. **把版本号写进 runner 上的工作区**:跑 [`scripts/Set-Version.ps1`](../scripts/Set-Version.ps1),
   把标签里那个版本落到 `Directory.Build.props`、两个模板的 `template.json`、
   `VelaPluginApi.SdkVersion` 以及四份文档的版本横幅/`PackageReference` 片段
   (详见下方"版本号纪律")。放在构建之前的第一步,产物因此**永远与标签一致**,
   与仓库里当时提交了什么无关。
   正常路径上这一步是**空操作**(上面第 2 步已经把版本号落进 `main` 了);
   留着它是为了不正常的那次 —— 有人忘了改,或者标签填的版本与 `main` 里的不一致。
   它**只改工作区、不回写仓库**;真的落后了,`git diff --stat` 会把它打出来,
   `main` 上的 CI 版本同步体检也会同时红。
3. 从 `STRONG_NAME_KEY` 机密还原 `VelaShell.snk`。
4. 跑全量测试(`-c Debug`,理由见下方"为什么测试必须 Debug")。
5. `dotnet pack` 五个包,版本经 `-p:VelaSdkVersion=` 覆盖。
6. **模板端到端冒烟**:装模板 → 生成工程 → 还原 → 构建 → 出 `.vpx` → 用刚打出的
   CLI 读回容器 → 确认共享程序集没漏进插件输出目录。
7. NuGet 可信发布换密钥 → 推送五个包。

整条流水线**不写仓库**:工作流级 `permissions` 只有 `contents: read` 加
Trusted Publishing 需要的 `id-token: write`。

手动兜底:Actions 页面 → Release → Run workflow,填标签即可补跑
(推送用 `--skip-duplicate`、上传用 `--clobber`,重复跑幂等)。勾 `dryRun` 只验不推。

### 忘了在发版前落版本号怎么办

包不受影响 —— 上面第 2 步按标签盖过版本号了,nuget.org 上那五个包的版本一定等于标签。
受影响的只有仓库自己:`main` 里的版本号还停在上一版,CI 的版本同步体检会红。补法:

```powershell
git switch -c chore/version-1.5.0 main
pwsh scripts/Set-Version.ps1 1.5.0
git commit -am "chore: 版本号同步到 1.5.0"
```

推上去提个 PR 合掉即可,内容是纯版本号替换。

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

### 版本号的落点(由脚本统一维护)

[`scripts/Set-Version.ps1`](../scripts/Set-Version.ps1) 是这些落点的唯一权威:

| 落点 | 漏改的后果 |
| --- | --- |
| `Directory.Build.props` 的 `VelaSdkVersion` | 包版本的默认值,PR 验证用它 |
| `templates/content/velaplugin{,-ui}/.template.config/template.json` 的 `sdkVersion.defaultValue` | 生成出来的工程去还原旧包;构建期由 `VerifyTemplateSdkVersion`(VELA1004)拦下 |
| `plugin-sdk/VelaShell.PluginSdk/VelaPluginApi.cs` 的 `SdkVersion` | **什么都不会报错** —— 只是 `vela-plugin doctor` 从此汇报一个错的宿主 SDK 版本,插件的 `minSdkVersion` 门槛跟着判错 |
| `docs{,-en}/cli.md`、`docs{,-en}/sdk-reference.md` 的版本横幅 | 不影响功能,但过期版本号会被人照抄 |
| `docs{,-en}/dev-guide.md`、`docs{,-en}/sdk-reference.md` 的 `PackageReference` 片段 | 同上,而且是最容易被整段复制走的那一段 |

发版时由流水线自动写(见"怎么发"第 2 步),平时也可以本地先跑一遍再提交 ——
那样发版时脚本就是个空操作:

```powershell
pwsh scripts/Set-Version.ps1 1.5.0            # 落盘
pwsh scripts/Set-Version.ps1 1.5.0 -Check     # 只报告,不同步就退出码 1
```

几条刻意的设计:

* **锚定上下文匹配,不做"全局替换旧版本号"**。后者会误伤示例输出里那些碰巧等于当前
  版本的数字 —— `docs/cli.md` 里 `1.4.2  api 1  sdk 1.4.0 …` 那行的 `1.4.2` 是**宿主**
  版本,与 SDK 版本无关,不该跟着动。
* **模式失配就直接失败**,不静默跳过。文件结构改了而脚本没跟上时,静默跳过等于把
  "漏改一处"原样放回来 —— 那正是这个脚本要消灭的东西。
* **不自动改 `VelaPluginApi.Level`**,只核对"SDK 主版本 == apiLevel"。破没破契约是人的
  判断;但判断做完之后忘了落到代码里是完全可能的,所以在这里挡住。
* **保留各文件原有的 BOM 状态**(`.cs` 带、`.props/.json/.md` 不带),否则 diff 里会多出
  一堆与版本号无关的整文件改动。

CI(`ci.yml`)每次 push/PR 都会跑一遍 `-Check`。删掉 `sync-main` 之后,这是"仓库里那十来处
版本号是否一致"的**唯一**守门人:有人手改了 `Directory.Build.props` 却没动模板和文档,
或者发版前忘了跑一遍脚本,都会在这里显形。

## 四、和主仓库的联动

主仓库 [joesdu/VelaShell](https://github.com/joesdu/VelaShell) 通过一个 pin 消费本仓库:

```xml
<!-- 主仓库 Directory.Build.props -->
<VelaSdkVersion>1.4.0</VelaSdkVersion>              <!-- SDK 包版本(本仓库) -->
<VelaPluginsBundleVersion>1.4.0</VelaPluginsBundleVersion>  <!-- 插件分发包所在的 Release 标签(velashell-plugins 仓库) -->
```

第二个 pin 指的是 [joesdu/velashell-plugins](https://github.com/joesdu/velashell-plugins)
的 Release,与本仓库无关 —— 别把两个版本号看成必须一致的一对。

所以顺序是:**先发本仓库的 Release,再去主仓库把 `VelaSdkVersion` 抬上去**;
插件那条线各走各的。

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
