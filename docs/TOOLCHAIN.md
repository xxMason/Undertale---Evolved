# Toolchain

| Tool | Version | Where | Purpose |
|---|---|---|---|
| UndertaleModTool CLI | **0.9.2.0** (`UTMT_CLI_v0.9.2.0-Windows.zip`, self-contained, no .NET install needed) | `tools/utmt-cli/` (not in Git) | Reads and patches `data.win`, compiles GML to bytecode 16 |
| C# compiler | .NET Framework 4 `csc.exe` (ships with Windows) | `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319` | Builds the launcher |
| Git | 2.56 | system | Version control |
| PowerShell | 5.1 | system | Build and test scripts |

## Getting UndertaleModTool

Download `UTMT_CLI_v0.9.2.0-Windows.zip` from
<https://github.com/UnderminersTeam/UndertaleModTool/releases/tag/0.9.2.0> and extract it
so that `tools/utmt-cli/UndertaleModCli.exe` exists.

- Size: 62,585,935 bytes
- SHA-256: `E7573E45D107BE34F81F955C6E4AFC3C7C8F2628E5A6F307A871E3825B3DFB40`

## Build

```
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

This compiles `launcher/Program.cs` into `UltimateBattleEngine.exe` in the project root.
The launcher then builds the game working copy itself on first run:

1. Finds Undertale (`--undertale`, `config/settings.json`, then Steam libraries).
2. Checks the SHA-256 of `data.win` and `UNDERTALE.exe` against `config/compat.json`.
3. Copies the installation to `game/` (skipping `data.win` and `steam_api.dll`), with the
   runner renamed to `UBE_Runner.exe`.
4. Runs `UndertaleModCli load <original data.win> -s patches/ube_patch.csx -o game/data.win`.
5. Writes `game/.ube_stamp`, a hash of the source game files, every file under
   `patches/`, `config/encounters.json` and the CLI. A changed stamp triggers a rebuild;
   `--rebuild` forces one.

## Inspecting the game

```
$env:UBE_INSPECT_OUT = "$PWD\build\inspect"
tools\utmt-cli\UndertaleModCli.exe load "<Undertale>\data.win" -s scripts\inspect.csx
```

Writes an asset index and all decompiled code to `build/inspect/` (ignored by Git). The
script never saves the data file.

## Test

```
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
```
