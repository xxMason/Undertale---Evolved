// UBE inspection script (read-only: never saves the data file).
// Usage: UndertaleModCli load <data.win> -s scripts/inspect.csx
// Env:   UBE_INSPECT_OUT = output directory for the report and decompiled code.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

EnsureDataLoaded();

string outDir = Environment.GetEnvironmentVariable("UBE_INSPECT_OUT");
if (string.IsNullOrEmpty(outDir)) throw new Exception("UBE_INSPECT_OUT is not set");
string codeDir = Path.Combine(outDir, "code");
Directory.CreateDirectory(codeDir);

var sb = new StringBuilder();
var gi = Data.GeneralInfo;
sb.AppendLine("## GeneralInfo");
sb.AppendLine($"Name={gi.Name?.Content}");
sb.AppendLine($"DisplayName={gi.DisplayName?.Content}");
sb.AppendLine($"FileName={gi.FileName?.Content}");
sb.AppendLine($"Config={gi.Config?.Content}");
sb.AppendLine($"BytecodeVersion={gi.BytecodeVersion}");
sb.AppendLine($"Version={gi.Major}.{gi.Minor}.{gi.Release}.{gi.Build}");
sb.AppendLine($"GameID={gi.GameID}");
sb.AppendLine($"Info={gi.Info}");
sb.AppendLine($"DefaultWindow={gi.DefaultWindowWidth}x{gi.DefaultWindowHeight}");
sb.AppendLine($"SteamAppID={gi.SteamAppID}");
sb.AppendLine($"IsGameMaker2={Data.IsGameMaker2()}");
sb.AppendLine($"Counts: objects={Data.GameObjects.Count} rooms={Data.Rooms.Count} scripts={Data.Scripts.Count} code={Data.Code.Count} sprites={Data.Sprites.Count} sounds={Data.Sounds.Count} fonts={Data.Fonts.Count}");

sb.AppendLine();
sb.AppendLine("## Rooms (index name WxH instances)");
for (int i = 0; i < Data.Rooms.Count; i++)
{
    var r = Data.Rooms[i];
    sb.AppendLine($"{i}\t{r.Name.Content}\t{r.Width}x{r.Height}\tpersistent={r.Persistent}\tobjs=[{string.Join(",", r.GameObjects.Select(o => o.ObjectDefinition?.Name?.Content))}]");
}
sb.AppendLine();
sb.AppendLine("## RoomOrder (first 5)");
foreach (var ro in gi.RoomOrder.Take(5)) sb.AppendLine(ro.Resource?.Name?.Content);

sb.AppendLine();
sb.AppendLine("## Objects (index name persistent parent sprite)");
for (int i = 0; i < Data.GameObjects.Count; i++)
{
    var o = Data.GameObjects[i];
    sb.AppendLine($"{i}\t{o.Name.Content}\tpersistent={o.Persistent}\tparent={o.ParentId?.Name?.Content}\tsprite={o.Sprite?.Name?.Content}");
}
sb.AppendLine();
sb.AppendLine("## Scripts");
for (int i = 0; i < Data.Scripts.Count; i++) sb.AppendLine($"{i}\t{Data.Scripts[i].Name.Content}");
sb.AppendLine();
sb.AppendLine("## Fonts");
for (int i = 0; i < Data.Fonts.Count; i++) sb.AppendLine($"{i}\t{Data.Fonts[i].Name.Content}");
sb.AppendLine();
sb.AppendLine("## Sounds");
for (int i = 0; i < Data.Sounds.Count; i++) sb.AppendLine($"{i}\t{Data.Sounds[i].Name.Content}\tfile={Data.Sounds[i].File?.Content}");

File.WriteAllText(Path.Combine(outDir, "datafile-report.txt"), sb.ToString());

int ok = 0, failed = 0;
var failures = new StringBuilder();
foreach (var code in Data.Code)
{
    if (code.ParentEntry != null) continue;
    try
    {
        string text = GetDecompiledText(code);
        File.WriteAllText(Path.Combine(codeDir, code.Name.Content + ".gml"), text);
        ok++;
    }
    catch (Exception e)
    {
        failed++;
        failures.AppendLine(code.Name.Content + ": " + e.Message);
    }
}
File.WriteAllText(Path.Combine(outDir, "decompile-failures.txt"), failures.ToString());
Console.WriteLine($"UBE-INSPECT done: code ok={ok} failed={failed} -> {outDir}");
