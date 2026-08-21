# Documentation index

Everything you need to write a VelaShell plugin. Chinese originals live in [`../docs/`](../docs/).

| Document | Contents |
| --- | --- |
| [dev-guide.md](dev-guide.md) | **Development guide**: quick start, manifest, lifecycle, capability APIs, isolation modes, testing, deployment, performance discipline |
| [cli.md](cli.md) | **`vela-plugin` manual**: dev inner loop (`dev init`), `doctor`, validate/pack/sign, host launch arguments |
| [publishing.md](publishing.md) | **Packaging and publishing**: Release builds, `.vpx`, signing and trust, publishing to the plugin market, CI packaging |
| [sdk-reference.md](sdk-reference.md) | **SDK reference**: package layout, entry contract, capability domains, SDK version history, test doubles, loading model |

Release process for this repository itself (Release flow, NuGet trusted publishing setup,
version discipline) is documented in Chinese only: [`../docs/release-process.md`](../docs/release-process.md).

## What is not here

The plugin system's **architecture blueprints** (process model, IPC protocol, permission
system, UI extensions, threat model, roadmap — the numbered 01–15 set) stay in the main
repository: <https://github.com/joesdu/VelaShell/tree/main/docs-en/plugins>

Those describe the **host side**. Read them to understand why plugins look the way they do;
you do not need them to write a plugin.
