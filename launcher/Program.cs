// Ultimate Battle Engine launcher.
// Targets the .NET Framework 4 compiler that ships with Windows (C# 5), see scripts/build.ps1.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace Ube
{
    static class Program
    {
        const int ExitOk = 0, ExitUsage = 1, ExitMissing = 2, ExitIsolation = 3, ExitOriginalsChanged = 4, ExitTestFailed = 5, ExitBuild = 6;
        const string RunnerName = "UBE_Runner.exe";
        const string OriginalSaveFolder = "UNDERTALE";

        static string root, logFile;
        static bool pauseOnError = true;

        static int Main(string[] args)
        {
            int code;
            try { code = Run(args); }
            catch (UbeException e) { Log("ERROR: " + e.Message); code = e.Code; }
            catch (Exception e) { Log("UNEXPECTED ERROR: " + e); code = ExitUsage; }
            if (code != ExitOk && pauseOnError && !Console.IsInputRedirected)
            {
                Console.WriteLine();
                Console.WriteLine("Press Enter to close.");
                Console.ReadLine();
            }
            return code;
        }

        static int Run(string[] args)
        {
            string undertaleArg = null, profileArg = null, exportArg = null, selftest = null;
            bool rebuild = false, prepareOnly = false, sweep = false;
            int sweepFrom = 0;
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                if (a == "--undertale" && i + 1 < args.Length) undertaleArg = args[++i];
                else if (a == "--profile" && i + 1 < args.Length) profileArg = args[++i];
                else if (a == "--export-profile" && i + 1 < args.Length) exportArg = args[++i];
                else if (a == "--selftest" && i + 1 < args.Length) selftest = args[++i];
                else if (a == "--sweep") sweep = true;
                else if (a == "--sweep-from" && i + 1 < args.Length) { sweep = true; sweepFrom = int.Parse(args[++i]); }
                else if (a == "--rebuild") rebuild = true;
                else if (a == "--prepare-only") prepareOnly = true;
                else if (a == "--no-pause") pauseOnError = false;
                else
                {
                    Console.WriteLine("Usage: UltimateBattleEngine.exe [--undertale <folder>] [--profile <json>] [--export-profile <json>]");
                    Console.WriteLine("                                [--rebuild] [--prepare-only] [--selftest menu|keys|ui|wasd|gear|win|lose|lose_then_win] [--sweep] [--sweep-from <n>] [--no-pause]");
                    return a == "--help" ? ExitOk : ExitUsage;
                }
            }
            if (selftest != null || sweep) pauseOnError = false;

            root = FindRoot();
            Directory.CreateDirectory(Path.Combine(root, "logs"));
            logFile = Path.Combine(root, "logs", "launcher.log");
            Log("==== Ultimate Battle Engine launcher, root=" + root);

            var compat = ReadJson(Path.Combine(root, "config", "compat.json"));
            string isolatedName = (string)compat["isolatedName"];
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string saveDir = Path.Combine(localAppData, isolatedName);
            string originalSaveDir = Path.Combine(localAppData, OriginalSaveFolder);
            string gameDir = Path.Combine(root, "game");

            // 1. Locate and verify the original installation (read-only).
            string install = LocateUndertale(undertaleArg);
            string label = VerifyCompatible(install, compat);
            Log("Original installation: " + install + "  [" + label + "]");
            if (undertaleArg != null)
                File.WriteAllText(Path.Combine(root, "config", "settings.json"),
                    new JavaScriptSerializer().Serialize(new Dictionary<string, object> { { "undertalePath", install } }));

            // 2. Working copy.
            PrepareWorkingCopy(install, gameDir, rebuild);

            // 3. Save-isolation gate. Nothing is launched unless every check passes.
            IsolationGate(install, gameDir, saveDir, originalSaveDir, isolatedName);

            // 4. Configuration in the isolated save directory.
            Directory.CreateDirectory(saveDir);
            string ini = Path.Combine(saveDir, "ube_config.ini");
            if (profileArg != null) ApplyProfile(profileArg, ini);
            IniSet(ini, "Test", "Scenario", selftest ?? "");
            // Self-tests always start in arrow-key mode; the user's choice is restored afterwards.
            int savedMovement = (int)IniGetNumber(ini, "Settings", "Movement", 0);
            if (selftest != null) IniSet(ini, "Settings", "Movement", "0");
            if (exportArg != null) ExportProfile(ini, exportArg);
            if (prepareOnly) { Log("Prepared. Not launching (--prepare-only)."); return ExitOk; }
            if (sweep) return RunSweep(install, originalSaveDir, gameDir, saveDir, ini, sweepFrom, savedMovement);

            // 5. Snapshot originals, launch, compare.
            var before = SnapshotOriginals(install, originalSaveDir);
            string gameLog = Path.Combine(saveDir, "ube_log.txt");
            int logLinesBefore = File.Exists(gameLog) ? File.ReadAllLines(gameLog).Length : 0;

            Log("Launching " + RunnerName + (selftest != null ? " (selftest " + selftest + ")" : ""));
            var psi = new ProcessStartInfo(Path.Combine(gameDir, RunnerName)) { WorkingDirectory = gameDir, UseShellExecute = false };
            bool timedOut = false;
            using (var p = Process.Start(psi))
            {
                if (selftest != null)
                {
                    if (!p.WaitForExit(300000)) { timedOut = true; try { p.Kill(); } catch { } p.WaitForExit(); }
                }
                else p.WaitForExit();
                Log("Game exited with code " + p.ExitCode + (timedOut ? " (killed after timeout)" : ""));
            }
            if (selftest != null)
            {
                IniSet(ini, "Test", "Scenario", "");
                IniSet(ini, "Settings", "Movement", savedMovement.ToString());
            }

            var after = SnapshotOriginals(install, originalSaveDir);
            var diffs = Diff(before, after);
            string[] newLines = File.Exists(gameLog) ? File.ReadAllLines(gameLog).Skip(logLinesBefore).ToArray() : new string[0];
            foreach (string l in newLines) Log("  game> " + l);

            if (diffs.Count > 0)
            {
                foreach (string d in diffs) Log("ORIGINAL CHANGED: " + d);
                throw new UbeException(ExitOriginalsChanged, "Original Undertale files or saves changed during this session. See the lines above.");
            }
            Log("Originals verified unchanged: " + before.Count + " entries (installation + " + originalSaveDir + ").");
            if (!newLines.Any(l => l.StartsWith("BOOT ")))
                throw new UbeException(ExitIsolation, "The game did not write its log to " + saveDir + ". Save isolation is unverified for this run.");
            Log("Isolated save directory confirmed in use: " + saveDir);

            if (selftest != null) return CheckSelfTest(selftest, newLines, timedOut);
            return ExitOk;
        }

        // ---------------------------------------------------------------- sweep
        // Starts every catalogue entry in turn inside the game (scenario "sweep"). If the
        // game exits or stops logging, the entry it was on is recorded as a crash and the
        // sweep resumes with the next one. Results go to logs\sweep-results.txt.
        static int RunSweep(string install, string originalSaveDir, string gameDir, string saveDir, string ini, int from, int savedMovement)
        {
            var before = SnapshotOriginals(install, originalSaveDir);
            string gameLog = Path.Combine(saveDir, "ube_log.txt");
            string resultsFile = Path.Combine(root, "logs", "sweep-results.txt");
            string gameOut = Path.Combine(root, "logs", "sweep-game-output.txt");
            if (from == 0) { File.Delete(resultsFile); File.Delete(gameOut); }
            int next = from;
            bool done = false;
            for (int launches = 0; launches < 150 && !done; launches++)
            {
                IniSet(ini, "Test", "Scenario", "sweep");
                IniSet(ini, "Test", "Start", next.ToString());
                IniSet(ini, "Settings", "Movement", "0");
                int linesBefore = File.Exists(gameLog) ? File.ReadAllLines(gameLog).Length : 0;
                var psi = new ProcessStartInfo(Path.Combine(gameDir, RunnerName))
                {
                    WorkingDirectory = gameDir, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true
                };
                var output = new StringBuilder();
                bool stalled = false;
                using (var p = new Process { StartInfo = psi })
                {
                    p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
                    p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
                    p.Start();
                    p.BeginOutputReadLine();
                    p.BeginErrorReadLine();
                    long lastLen = -1;
                    DateTime lastChange = DateTime.Now;
                    while (!p.WaitForExit(1000))
                    {
                        long len = File.Exists(gameLog) ? new FileInfo(gameLog).Length : 0;
                        if (len != lastLen) { lastLen = len; lastChange = DateTime.Now; }
                        else if ((DateTime.Now - lastChange).TotalSeconds > 90)
                        {
                            stalled = true;
                            try { p.Kill(); } catch { }
                            p.WaitForExit();
                            break;
                        }
                    }
                    p.WaitForExit();
                }
                string[] lines = File.Exists(gameLog) ? File.ReadAllLines(gameLog).Skip(linesBefore).ToArray() : new string[0];
                File.AppendAllLines(resultsFile, lines);
                done = lines.Any(l => l == "SWEEP done");
                int last = -1;
                foreach (string l in lines)
                    if (l.StartsWith("SWEEP start i="))
                        last = int.Parse(l.Substring(14, l.IndexOf(' ', 14) - 14));
                if (!done)
                {
                    if (last < 0) throw new UbeException(ExitTestFailed, "Sweep made no progress from entry " + next + ".");
                    string why = stalled ? "stalled" : "exited";
                    File.AppendAllText(resultsFile, "SWEEP crash i=" + last + " " + why + Environment.NewLine);
                    lock (output) File.AppendAllText(gameOut, "==== entry " + last + " (" + why + ")" + Environment.NewLine + output + Environment.NewLine);
                    Log("Sweep: entry " + last + " " + why + "; resuming at " + (last + 1));
                    next = last + 1;
                }
            }
            IniSet(ini, "Test", "Scenario", "");
            IniSet(ini, "Test", "Start", "0");
            IniSet(ini, "Settings", "Movement", savedMovement.ToString());

            var diffs = Diff(before, SnapshotOriginals(install, originalSaveDir));
            if (diffs.Count > 0)
            {
                foreach (string d in diffs) Log("ORIGINAL CHANGED: " + d);
                throw new UbeException(ExitOriginalsChanged, "Original Undertale files or saves changed during the sweep.");
            }
            Log("Originals verified unchanged after the sweep.");
            Log(done ? "Sweep finished. Results: " + resultsFile : "Sweep did not finish.");
            return done ? ExitOk : ExitTestFailed;
        }

        // ---------------------------------------------------------------- locating / verifying
        static string FindRoot()
        {
            var d = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            while (d != null)
            {
                if (File.Exists(Path.Combine(d.FullName, "patches", "ube_patch.csx"))) return d.FullName.TrimEnd('\\');
                d = d.Parent;
            }
            throw new UbeException(ExitMissing, "Cannot find the project folder (patches\\ube_patch.csx) next to or above the launcher.");
        }

        static string LocateUndertale(string arg)
        {
            string settingsPath = Path.Combine(root, "config", "settings.json");
            var candidates = new List<string>();
            if (arg != null) candidates.Add(arg); // an explicit path is never silently replaced
            else
            {
                if (File.Exists(settingsPath))
                {
                    object v;
                    if (ReadJson(settingsPath).TryGetValue("undertalePath", out v) && v is string && (string)v != "") candidates.Add((string)v);
                }
                foreach (string steam in SteamRoots()) candidates.Add(Path.Combine(steam, "steamapps", "common", "Undertale"));
            }

            foreach (string c in candidates)
            {
                if (File.Exists(Path.Combine(c, "data.win")) && File.Exists(Path.Combine(c, "UNDERTALE.exe")))
                    return Path.GetFullPath(c);
            }
            throw new UbeException(ExitMissing, "Could not find an Undertale installation (data.win + UNDERTALE.exe).\n" +
                "Checked: " + string.Join("; ", candidates) + "\n" +
                "Run:  UltimateBattleEngine.exe --undertale \"<folder containing UNDERTALE.exe>\"");
        }

        static IEnumerable<string> SteamRoots()
        {
            var roots = new List<string>();
            try
            {
                object v = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath", null);
                if (v is string) roots.Add(((string)v).Replace('/', '\\'));
            }
            catch { }
            roots.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam"));
            foreach (string r in roots.ToArray())
            {
                string vdf = Path.Combine(r, "steamapps", "libraryfolders.vdf");
                if (!File.Exists(vdf)) continue;
                foreach (string line in File.ReadAllLines(vdf))
                {
                    string t = line.Trim();
                    if (!t.StartsWith("\"path\"")) continue;
                    int q = t.IndexOf('"', 6);
                    if (q < 0) continue;
                    roots.Add(t.Substring(q + 1).TrimEnd('"').Replace("\\\\", "\\"));
                }
            }
            return roots.Distinct(StringComparer.OrdinalIgnoreCase);
        }

        static string VerifyCompatible(string install, Dictionary<string, object> compat)
        {
            string dataHash = Sha256(Path.Combine(install, "data.win"));
            string exeHash = Sha256(Path.Combine(install, "UNDERTALE.exe"));
            foreach (Dictionary<string, object> s in ((System.Collections.ArrayList)compat["supported"]))
            {
                var files = (Dictionary<string, object>)s["files"];
                if (string.Equals((string)files["data.win"], dataHash, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals((string)files["UNDERTALE.exe"], exeHash, StringComparison.OrdinalIgnoreCase))
                    return (string)s["label"];
            }
            throw new UbeException(ExitMissing, "This Undertale version is not supported yet.\n" +
                "  data.win      SHA-256 " + dataHash + "\n  UNDERTALE.exe SHA-256 " + exeHash + "\n" +
                "Supported versions are listed in config\\compat.json. Nothing was copied or modified.");
        }

        // ---------------------------------------------------------------- working copy
        static void PrepareWorkingCopy(string install, string gameDir, bool rebuild)
        {
            string cli = Path.Combine(root, "tools", "utmt-cli", "UndertaleModCli.exe");
            if (!File.Exists(cli))
                throw new UbeException(ExitMissing, "UndertaleModTool CLI not found at " + cli + ".\nSee docs\\TOOLCHAIN.md for the exact version and where to put it.");

            var sb = new StringBuilder();
            sb.Append(Sha256(Path.Combine(install, "data.win"))).Append(Sha256(Path.Combine(install, "UNDERTALE.exe")));
            foreach (string f in Directory.GetFiles(Path.Combine(root, "patches"), "*", SearchOption.AllDirectories).OrderBy(x => x, StringComparer.Ordinal))
                sb.Append(Sha256(f));
            sb.Append(Sha256(Path.Combine(root, "config", "encounters.json"))).Append(Sha256(cli));
            string stamp = Sha256Text(sb.ToString());
            string stampFile = Path.Combine(gameDir, ".ube_stamp");

            if (!rebuild && File.Exists(stampFile) && File.ReadAllText(stampFile) == stamp &&
                File.Exists(Path.Combine(gameDir, "data.win")) && File.Exists(Path.Combine(gameDir, RunnerName)))
            {
                Log("Working copy is up to date.");
                return;
            }

            // Never rebuild underneath a running game: deleting its files would break it.
            foreach (var running in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(RunnerName)))
            {
                string exePath = null;
                try { exePath = running.MainModule.FileName; } catch { }
                if (exePath == null || exePath.StartsWith(gameDir, StringComparison.OrdinalIgnoreCase))
                    throw new UbeException(ExitBuild, "Ultimate Battle Engine is already running (process " + running.Id + "). Close it before rebuilding the working copy.");
            }

            Log("Building working copy in " + gameDir + " ...");
            if (Directory.Exists(gameDir)) Directory.Delete(gameDir, true);
            Directory.CreateDirectory(gameDir);
            int copied = 0;
            foreach (string src in Directory.GetFiles(install, "*", SearchOption.AllDirectories))
            {
                string rel = src.Substring(install.Length).TrimStart('\\');
                string name = Path.GetFileName(src).ToLowerInvariant();
                // data.win is produced by the patcher; Steam integration is deliberately left out.
                if (name == "data.win" || name == "steam_api.dll" || name == "steam_appid.txt") continue;
                if (rel.Equals("UNDERTALE.exe", StringComparison.OrdinalIgnoreCase)) rel = RunnerName;
                string dst = Path.Combine(gameDir, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(dst));
                File.Copy(src, dst, true);
                copied++;
            }
            Log("Copied " + copied + " files.");

            string outTmp = Path.Combine(gameDir, "data.win.tmp");
            var psi = new ProcessStartInfo(cli)
            {
                Arguments = "load \"" + Path.Combine(install, "data.win") + "\" -s \"" + Path.Combine(root, "patches", "ube_patch.csx") + "\" -o \"" + outTmp + "\" -f",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            psi.EnvironmentVariables["UBE_ROOT"] = root; // this child process only
            var output = new StringBuilder();
            using (var p = new Process { StartInfo = psi })
            {
                p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
                p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                p.WaitForExit();
                File.WriteAllText(Path.Combine(root, "logs", "patch.log"), output.ToString());
                if (p.ExitCode != 0 || !output.ToString().Contains("UBE-PATCH ok") || !File.Exists(outTmp))
                    throw new UbeException(ExitBuild, "Patching failed (exit " + p.ExitCode + "). See logs\\patch.log.");
            }
            File.Move(outTmp, Path.Combine(gameDir, "data.win"));
            File.WriteAllText(stampFile, stamp);
            Log("Patched data.win written.");
        }

        // ---------------------------------------------------------------- isolation
        static void IsolationGate(string install, string gameDir, string saveDir, string originalSaveDir, string isolatedName)
        {
            var problems = new List<string>();
            string g = Path.GetFullPath(gameDir).TrimEnd('\\') + "\\", o = Path.GetFullPath(install).TrimEnd('\\') + "\\";
            if (g.StartsWith(o, StringComparison.OrdinalIgnoreCase) || o.StartsWith(g, StringComparison.OrdinalIgnoreCase))
                problems.Add("The working copy and the original installation overlap.");
            if (File.Exists(Path.Combine(gameDir, "steam_api.dll")) || File.Exists(Path.Combine(gameDir, "steam_appid.txt")))
                problems.Add("Steam integration files are present in the working copy (Steam Cloud could be touched).");
            if (string.Equals(Path.GetFullPath(saveDir), Path.GetFullPath(originalSaveDir), StringComparison.OrdinalIgnoreCase))
                problems.Add("The isolated save directory equals the original save directory.");
            string[] names = ReadGen8Names(Path.Combine(gameDir, "data.win"));
            if (names[0] != isolatedName || names[1] != isolatedName)
                problems.Add("Patched data.win identifies itself as '" + names[0] + "' / '" + names[1] + "', expected '" + isolatedName + "'. It would use the wrong save directory.");
            if (problems.Count > 0)
                throw new UbeException(ExitIsolation, "Save isolation cannot be guaranteed, so the game was NOT started:\n  - " + string.Join("\n  - ", problems));
            Log("Isolation gate passed: save directory will be " + saveDir);
        }

        // Returns { GEN8 Name, GEN8 DisplayName }.
        static string[] ReadGen8Names(string dataWin)
        {
            using (var fs = File.OpenRead(dataWin))
            using (var br = new BinaryReader(fs))
            {
                if (new string(br.ReadChars(4)) != "FORM") throw new UbeException(ExitIsolation, "Not a GameMaker data file: " + dataWin);
                br.ReadUInt32();
                if (new string(br.ReadChars(4)) != "GEN8") throw new UbeException(ExitIsolation, "GEN8 chunk not found first in " + dataWin);
                br.ReadUInt32();
                long gen8 = fs.Position;
                fs.Position = gen8 + 40;
                uint nameOff = br.ReadUInt32();
                fs.Position = gen8 + 100;
                uint displayOff = br.ReadUInt32();
                return new[] { ReadGmString(br, nameOff), ReadGmString(br, displayOff) };
            }
        }

        static string ReadGmString(BinaryReader br, uint offset)
        {
            br.BaseStream.Position = offset - 4;
            int len = br.ReadInt32();
            if (len < 0 || len > 1024) return "<invalid>";
            return Encoding.UTF8.GetString(br.ReadBytes(len));
        }

        static Dictionary<string, string> SnapshotOriginals(string install, string originalSaveDir)
        {
            var snap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            SnapshotDir(install, "install", snap);
            SnapshotDir(originalSaveDir, "saves", snap);
            foreach (string steam in SteamRoots())
            {
                string userdata = Path.Combine(steam, "userdata");
                if (!Directory.Exists(userdata)) continue;
                foreach (string user in Directory.GetDirectories(userdata))
                    SnapshotDir(Path.Combine(user, "391540"), "steamcloud:" + Path.GetFileName(user), snap);
            }
            return snap;
        }

        static void SnapshotDir(string dir, string tag, Dictionary<string, string> snap)
        {
            if (!Directory.Exists(dir)) { snap[tag + "|<directory>"] = "absent"; return; }
            snap[tag + "|<directory>"] = "present";
            foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                snap[tag + "|" + f.Substring(dir.Length)] = new FileInfo(f).Length + ":" + Sha256(f);
        }

        static List<string> Diff(Dictionary<string, string> a, Dictionary<string, string> b)
        {
            var d = new List<string>();
            foreach (var kv in a)
            {
                string v;
                if (!b.TryGetValue(kv.Key, out v)) d.Add("removed " + kv.Key);
                else if (v != kv.Value) d.Add("modified " + kv.Key);
            }
            foreach (var kv in b) if (!a.ContainsKey(kv.Key)) d.Add("added " + kv.Key);
            return d;
        }

        // ---------------------------------------------------------------- profiles / ini
        static void ApplyProfile(string path, string ini)
        {
            if (!File.Exists(path)) throw new UbeException(ExitUsage, "Profile not found: " + path);
            var p = ReadJson(path);
            int love = Convert.ToInt32(p["love"]);
            int hp = p.ContainsKey("startingHp") ? Convert.ToInt32(p["startingHp"]) : 0;
            if (love < 1 || love > 20) throw new UbeException(ExitUsage, "Profile 'love' must be 1-20.");
            int maxHp = love == 20 ? 99 : 16 + love * 4;
            if (hp < 0 || hp > maxHp) throw new UbeException(ExitUsage, "Profile 'startingHp' must be 0 (full) or 1-" + maxHp + " at LOVE " + love + ".");
            // Item IDs handled by the original scr_weaponeq / scr_armoreq.
            int[] weapons = { 3, 13, 14, 25, 45, 47, 49, 51, 52 }, armors = { 4, 12, 15, 24, 44, 46, 48, 50, 53, 64 };
            int weapon = p.ContainsKey("weapon") ? Convert.ToInt32(p["weapon"]) : 3;
            int armor = p.ContainsKey("armor") ? Convert.ToInt32(p["armor"]) : 4;
            if (!weapons.Contains(weapon)) throw new UbeException(ExitUsage, "Profile 'weapon' must be one of: " + string.Join(", ", weapons));
            if (!armors.Contains(armor)) throw new UbeException(ExitUsage, "Profile 'armor' must be one of: " + string.Join(", ", armors));
            var items = new int[8];
            if (p.ContainsKey("items"))
            {
                var list = (System.Collections.ArrayList)p["items"];
                if (list.Count > 8) throw new UbeException(ExitUsage, "Profile 'items' can hold at most 8 entries.");
                for (int i = 0; i < list.Count; i++)
                {
                    items[i] = Convert.ToInt32(list[i]);
                    if (items[i] < 0 || items[i] > 64) throw new UbeException(ExitUsage, "Profile item IDs must be 0 (empty) to 64.");
                }
            }
            IniSet(ini, "Player", "LOVE", love.ToString());
            IniSet(ini, "Player", "HP", hp.ToString());
            IniSet(ini, "Player", "Weapon", weapon.ToString());
            IniSet(ini, "Player", "Armor", armor.ToString());
            for (int i = 0; i < 8; i++) IniSet(ini, "Player", "Item" + i, items[i].ToString());
            Log("Applied profile " + path + ": LOVE " + love + ", starting HP " + (hp == 0 ? "full" : hp.ToString()) + ", weapon " + weapon + ", armor " + armor);
        }

        static void ExportProfile(string ini, string path)
        {
            var o = new Dictionary<string, object>
            {
                { "schema", 1 }, { "name", Path.GetFileNameWithoutExtension(path) },
                { "love", (int)IniGetNumber(ini, "Player", "LOVE", 1) }, { "startingHp", (int)IniGetNumber(ini, "Player", "HP", 0) },
                { "weapon", (int)IniGetNumber(ini, "Player", "Weapon", 3) }, { "armor", (int)IniGetNumber(ini, "Player", "Armor", 4) },
                { "items", Enumerable.Range(0, 8).Select(i => (int)IniGetNumber(ini, "Player", "Item" + i, 0)).ToArray() },
                { "authentic", true }
            };
            File.WriteAllText(path, new JavaScriptSerializer().Serialize(o));
            Log("Exported current player setup to " + path);
        }

        static double IniGetNumber(string ini, string section, string key, double def)
        {
            if (!File.Exists(ini)) return def;
            string cur = "";
            foreach (string raw in File.ReadAllLines(ini))
            {
                string l = raw.Trim();
                if (l.StartsWith("[") && l.EndsWith("]")) { cur = l.Substring(1, l.Length - 2); continue; }
                int eq = l.IndexOf('=');
                if (eq < 0 || cur != section || l.Substring(0, eq).Trim() != key) continue;
                double v;
                if (double.TryParse(l.Substring(eq + 1).Trim().Trim('"'), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v)) return v;
            }
            return def;
        }

        // Minimal INI writer producing the key="value" form GameMaker itself writes.
        static void IniSet(string ini, string section, string key, string value)
        {
            var lines = File.Exists(ini) ? File.ReadAllLines(ini).ToList() : new List<string>();
            string newLine = key + "=\"" + value + "\"";
            int secStart = lines.FindIndex(l => l.Trim() == "[" + section + "]");
            if (secStart < 0)
            {
                lines.Add("[" + section + "]");
                lines.Add(newLine);
            }
            else
            {
                int i = secStart + 1;
                for (; i < lines.Count && !lines[i].Trim().StartsWith("["); i++)
                {
                    int eq = lines[i].IndexOf('=');
                    if (eq > 0 && lines[i].Substring(0, eq).Trim() == key) { lines[i] = newLine; File.WriteAllLines(ini, lines); return; }
                }
                lines.Insert(secStart + 1, newLine);
            }
            File.WriteAllLines(ini, lines);
        }

        // ---------------------------------------------------------------- self-test
        static int CheckSelfTest(string scenario, string[] lines, bool timedOut)
        {
            string[] expect;
            if (scenario == "menu") expect = new[] { "BOOT ", "EXIT" };
            else if (scenario == "keys") expect = new[] { "BOOT ", "KEYS check=1 direct=1 timeup=1", "EXIT" };
            else if (scenario == "gear") expect = new[] { "BOOT ", "STATE IN_BATTLE id=froggit battlegroup=4 lv=1 hp=5/20", "GEAR weapon=52 wstr=99 armor=53 adef=99 item0=11 item1=1 item2=0 hp=5", "GEAR used hp=20/20 item0=1", "STATE ABORTED", "EXIT" };
            else if (scenario == "wasd") expect = new[] { "BOOT ", "WASDCHK off sel=0", "SETTINGS movement=1", "WASDCHK on sel=0", "STATE IN_BATTLE", "WASDCHK battle timeup=1", "STATE ", "EXIT" };
            else if (scenario == "win") expect = new[] { "BOOT ", "STATE IN_BATTLE", "STATE VICTORY", "EXIT" };
            else if (scenario == "lose") expect = new[] { "BOOT ", "STATE IN_BATTLE", "STATE DEFEAT", "EXIT" };
            else if (scenario == "ui") expect = new[] { "BOOT ", "CONFIG lv=5 hp=33", "TABS area=0 cat=0 focus=2", "TABS area=0 cat=1 focus=1", "TABS area=1 cat=0 focus=0", "STATE IN_BATTLE id=froggit battlegroup=4 lv=5 hp=33/36", "STATE ", "EXIT" };
            else if (scenario == "lose_then_win") expect = new[] { "BOOT ", "STATE IN_BATTLE", "STATE DEFEAT", "RETRY", "STATE IN_BATTLE", "STATE VICTORY", "EXIT" };
            else throw new UbeException(ExitUsage, "Unknown selftest scenario " + scenario);
            int pos = 0;
            foreach (string l in lines) if (pos < expect.Length && l.StartsWith(expect[pos])) pos++;
            bool steamOff = lines.Any(l => l.StartsWith("BOOT ") && l.EndsWith("steam=0"));
            if (pos == expect.Length && !timedOut && steamOff)
            {
                Log("SELFTEST " + scenario + ": PASS");
                return ExitOk;
            }
            Log("SELFTEST " + scenario + ": FAIL (matched " + pos + "/" + expect.Length + " expected log steps, timedOut=" + timedOut + ", steamOff=" + steamOff + ")");
            return ExitTestFailed;
        }

        // ---------------------------------------------------------------- helpers
        static Dictionary<string, object> ReadJson(string path)
        {
            if (!File.Exists(path)) throw new UbeException(ExitMissing, "Missing file: " + path);
            return new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(path));
        }

        static string Sha256(string file)
        {
            using (var sha = SHA256.Create())
            using (var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
        }

        static string Sha256Text(string text)
        {
            using (var sha = SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-", "");
        }

        static void Log(string msg)
        {
            Console.WriteLine(msg);
            if (logFile != null)
                try { File.AppendAllText(logFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + Environment.NewLine); } catch { }
        }
    }

    class UbeException : Exception
    {
        public readonly int Code;
        public UbeException(int code, string message) : base(message) { Code = code; }
    }
}
