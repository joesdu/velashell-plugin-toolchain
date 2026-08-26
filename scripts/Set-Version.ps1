#Requires -Version 7.0
<#
.SYNOPSIS
    把 SDK 版本号写进仓库里所有需要它的地方。

.DESCRIPTION
    版本号在本仓库有一串落点,少改一处的后果各不相同、且都不会在你手上暴露:

      Directory.Build.props            <VelaSdkVersion>          —— 包版本的默认值
      templates/…/velaplugin/…         sdkVersion.defaultValue   —— 生成的插件工程引用哪版包
      templates/…/velaplugin-ui/…      sdkVersion.defaultValue   —— 同上
      plugin-sdk/…/VelaPluginApi.cs    SdkVersion 常量           —— 宿主写进 host.json 的值,
                                                                    vela-plugin doctor 拿它跟
                                                                    插件的 minSdkVersion 比对
      docs{,-en}/cli.md                版本横幅
      docs{,-en}/sdk-reference.md      版本横幅 + PackageReference 片段
      docs{,-en}/dev-guide.md          PackageReference 片段

    忘了改模板那两处:新建出来的工程去还原一个旧包(构建期由 VELA1004 拦下)。
    忘了改 VelaPluginApi.SdkVersion:**没有任何东西会报错** —— 只是 `vela-plugin doctor`
    从此汇报一个错的宿主 SDK 版本,插件的 minSdkVersion 门槛跟着判错。这一处此前甚至
    不在发版清单里。docs 那几处不影响功能,但它们是给人照抄的,过期版本号会被原样
    粘进别人的工程。

    所以这件事不该靠人记 —— 但**得由人来跑**:发版前在本地跑一遍,把改动连同功能改动
    一起合进 main。

    发版流水线在解析出 Release 标签之后**第一件事**也会跑本脚本
    (见 .github/workflows/release.yml),因此产物永远与标签一致,与仓库里当时提交了什么
    无关。正常路径上那一次是空操作(版本号已经在 main 里了);它只改 runner 上的工作区,
    **不回写仓库**(原 sync-main 任务已于 2026-08-26 删除)。忘了在本地跑的兜底是
    CI 的 -Check 体检:它会在 main 上红一次,照提示补一个 PR 即可。

.PARAMETER Version
    目标版本,SemVer(1.5.0 或 1.5.0-preview.1)。

.PARAMETER Check
    只报告不落盘;有任何一处不同步就以退出码 1 结束。CI 用它做"仓库是否已同步"的体检。

.EXAMPLE
    pwsh scripts/Set-Version.ps1 1.5.0

.EXAMPLE
    pwsh scripts/Set-Version.ps1 1.5.0 -Check
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [string] $Version,
    [switch] $Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?$') {
    throw "'$Version' 不是合法 SemVer。用 1.5.0 或 1.5.0-preview.1 这种形式。"
}
$major = [int]$Matches[1]

$root = Split-Path -Parent $PSScriptRoot

# ── apiLevel 纪律的硬检查 ────────────────────────────────────────────────────
# 纪律:SDK 主版本 == apiLevel。主版本变意味着契约破了,那一刻 VelaPluginApi.Level 必须
# 同步 +1 —— 老宿主于是在**发现期**按 apiLevel 干净拒载(可读原因 + Incompatible 状态),
# 而不是等装载时抛一个看不懂的程序集绑定异常。
#
# 这一步刻意**不自动改** Level:「契约破没破」是人的判断,不是版本号的推论。
# 但判断做完之后忘了落到代码里,是完全可能的 —— 所以在这里挡住。
$apiFile = Join-Path $root 'plugin-sdk/VelaShell.PluginSdk/VelaPluginApi.cs'
$levelMatch = [regex]::Match((Get-Content -Raw $apiFile), 'public const int Level = (\d+);')
if (-not $levelMatch.Success) { throw "在 plugin-sdk/VelaShell.PluginSdk/VelaPluginApi.cs 里找不到 VelaPluginApi.Level。" }
$level = [int]$levelMatch.Groups[1].Value
if ($level -ne $major) {
    throw @"
版本 $Version 的主版本是 $major,但 VelaPluginApi.Level 是 $level。
纪律是「SDK 主版本 == apiLevel」:
  · 要发 $major.x.x,先把 VelaPluginApi.Level 改成 $major —— 但那等于宣布契约破了,
    确认破坏性变更确实存在再动;
  · 若契约其实没破,那就不该跳主版本,发 $level.x.x 系列即可。
"@
}

# ── 落点清单 ────────────────────────────────────────────────────────────────
# 每条都用**锚定到上下文**的模式,不做"全局替换旧版本号"。后者会误伤示例输出里那些
# 只是碰巧等于当前版本的数字(docs/cli.md 的 `1.4.2  api 1  sdk 1.4.0 …` 就是一例:
# 那行里的 1.4.2 是宿主版本,与 SDK 版本无关,不该跟着动)。
$edits = [System.Collections.Generic.List[hashtable]]::new()

$edits.Add(@{
    Path    = 'Directory.Build.props'
    Pattern = '(?<pre><VelaSdkVersion Condition="[^"]*">)(?<val>[^<]+)(?<post></VelaSdkVersion>)'
    What    = 'VelaSdkVersion'
})
foreach ($template in 'velaplugin', 'velaplugin-ui') {
    $edits.Add(@{
        Path    = "templates/content/$template/.template.config/template.json"
        Pattern = '(?<pre>"sdkVersion":\s*\{[\s\S]*?"defaultValue":\s*")(?<val>[^"]+)(?<post>")'
        What    = 'sdkVersion.defaultValue'
    })
}
$edits.Add(@{
    Path    = 'plugin-sdk/VelaShell.PluginSdk/VelaPluginApi.cs'
    Pattern = '(?<pre>public const string SdkVersion = ")(?<val>[^"]+)(?<post>";)'
    What    = 'VelaPluginApi.SdkVersion'
})
$edits.Add(@{
    Path    = 'docs/cli.md'
    Pattern = '(?<pre>适用版本:VelaShell 插件 SDK \*\*)(?<val>[^*]+)(?<post>\*\*)'
    What    = '版本横幅'
})
$edits.Add(@{
    Path    = 'docs-en/cli.md'
    Pattern = '(?<pre>Applies to VelaShell plugin SDK \*\*)(?<val>[^*]+)(?<post>\*\*)'
    What    = 'version banner'
})
$edits.Add(@{
    Path    = 'docs/sdk-reference.md'
    Pattern = '(?<pre>适用版本:\*\*SDK )(?<val>\S+)(?<post> / apiLevel)'
    What    = '版本横幅'
})
$edits.Add(@{
    Path    = 'docs-en/sdk-reference.md'
    Pattern = '(?<pre>Applies to \*\*SDK )(?<val>\S+)(?<post> / apiLevel)'
    What    = 'version banner'
})
# PackageReference 片段:锚在包 id 上,四份文档各一处。
foreach ($doc in 'docs/dev-guide.md', 'docs-en/dev-guide.md', 'docs/sdk-reference.md', 'docs-en/sdk-reference.md') {
    $edits.Add(@{
        Path    = $doc
        Pattern = '(?<pre><PackageReference Include="VelaShell\.PluginSdk\.Build" Version=")(?<val>[^"]+)(?<post>")'
        What    = 'PackageReference 片段'
    })
}

# ── 应用 ────────────────────────────────────────────────────────────────────
$changed = [System.Collections.Generic.List[object]]::new()
foreach ($edit in $edits) {
    $path = Join-Path $root $edit.Path
    if (-not (Test-Path $path)) { throw "落点文件不存在:$($edit.Path)" }

    $text = [IO.File]::ReadAllText($path)
    $found = [regex]::Matches($text, $edit.Pattern)
    if ($found.Count -eq 0) {
        # 模式失配 = 文件结构变了而本脚本没跟上。静默跳过等于把"漏改一处"重新放回来,
        # 所以这里直接断掉,让人当场看见。
        throw "在 $($edit.Path) 里没匹配到「$($edit.What)」。文件结构改过了?请同步更新 scripts/Set-Version.ps1。"
    }

    $stale = @($found | Where-Object { $_.Groups['val'].Value -cne $Version })
    if ($stale.Count -eq 0) { continue }

    $changed.Add([pscustomobject]@{
        File = $edit.Path
        What = $edit.What
        From = (($stale | ForEach-Object { $_.Groups['val'].Value } | Select-Object -Unique) -join ', ')
        To   = $Version
    })
    if ($Check) { continue }

    $updated = [regex]::Replace($text, $edit.Pattern, {
        param($m) $m.Groups['pre'].Value + $Version + $m.Groups['post'].Value
    })
    # 保留文件原有的 BOM 状态:仓库里 .cs 带 BOM、.props/.json/.md 不带,
    # 顺手统一会让 diff 里多出一堆与版本号无关的整文件改动。
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($hasBom))
}

if ($changed.Count -eq 0) {
    Write-Host "版本已经是 $Version,全部落点同步,无需改动。"
    exit 0
}

$changed | Format-Table -AutoSize | Out-String | Write-Host

if ($Check) {
    Write-Host "::error::仓库里的版本号与 $Version 不同步(见上表)。跑 ``pwsh scripts/Set-Version.ps1 $Version`` 修正。"
    exit 1
}

Write-Host "已把 $($changed.Count) 处落点更新到 $Version。"

# 显式 exit 0,别靠"脚本正常结束"隐含成功。
# 调用方是 `& ./scripts/Set-Version.ps1 ...` 后面跟一句 if ($LASTEXITCODE) —— 而 .ps1
# **不调用 exit 就根本不会设置 $LASTEXITCODE**,它会原样保留调用方进程里的旧值。
# GitHub 的每个 pwsh 步骤都是全新进程,那里的旧值是 $null,于是 `$LASTEXITCODE -ne 0`
# 求值为真 —— 脚本明明改好了文件,步骤却报 exit code 1。
# 这条路一直没露面,是因为上面 $changed.Count -eq 0 那个分支有 exit 0:发版时若 main
# 已经是目标版本就走那边。真正要落版本号的那次(也就是发版本身)才会踩到。
# 2026-08-22 在 velashell-plugins 仓库发 1.0.0 时撞上,同一份脚本这边一并修。
exit 0
