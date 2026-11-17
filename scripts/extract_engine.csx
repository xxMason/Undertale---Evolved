// Extracts everything the Godot battle engine needs to run the original battle code
// from the player's own data.win. Read-only; output goes to godot/extracted/ (never
// committed). Usage:
//   UndertaleModCli load <data.win> -s scripts/extract_engine.csx      (env UBE_GODOT_OUT)
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using UndertaleModLib.Util;

EnsureDataLoaded();

string outDir = Environment.GetEnvironmentVariable("UBE_GODOT_OUT");
if (string.IsNullOrEmpty(outDir)) throw new Exception("UBE_GODOT_OUT is not set");
string codeDir = Path.Combine(outDir, "code");
string sprDir = Path.Combine(outDir, "sprites");
string bgDir = Path.Combine(outDir, "backgrounds");
string fntDir = Path.Combine(outDir, "fonts");
string sndDir = Path.Combine(outDir, "sounds");
foreach (var d in new[] { codeDir, sprDir, bgDir, fntDir, sndDir }) Directory.CreateDirectory(d);

static string J(string s) => s == null ? "null" : "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "") + "\"";
string N(UndertaleNamedResource r) => r == null ? "null" : J(r.Name.Content);

// ---- Code: every top-level code entry, decompiled.
int okCode = 0, badCode = 0;
var bad = new StringBuilder();
foreach (var code in Data.Code)
{
    if (code.ParentEntry != null) continue;
    try { File.WriteAllText(Path.Combine(codeDir, code.Name.Content + ".gml"), GetDecompiledText(code)); okCode++; }
    catch (Exception e) { badCode++; bad.AppendLine(code.Name.Content + ": " + e.Message); }
}
File.WriteAllText(Path.Combine(outDir, "code_failures.txt"), bad.ToString());

var meta = new StringBuilder("{\n");

// ---- Asset index tables (for asset_get_index and numeric references).
void Table(string key, IEnumerable<UndertaleNamedResource> items)
{
    meta.Append($"\"{key}\": [" + string.Join(",", items.Select(i => i == null ? "null" : J(i.Name.Content))) + "],\n");
}
Table("sprite_names", Data.Sprites);
Table("sound_names", Data.Sounds);
Table("object_names", Data.GameObjects);
Table("room_names", Data.Rooms);
Table("script_names", Data.Scripts);
Table("font_names", Data.Fonts);
Table("background_names", Data.Backgrounds);
Table("path_names", Data.Paths);
meta.Append("\"paths\": {" + string.Join(",", Data.Paths.Where(pa => pa != null).Select(pa => J(pa.Name.Content) + ":[" + (pa.IsClosed ? 1 : 0) + "," + (pa.IsSmooth ? 1 : 0) + "," + pa.Precision + ",[" + string.Join(",", pa.Points.Select(pt => "[" + pt.X + "," + pt.Y + "," + pt.Speed + "]")) + "]]")) + "},\n");
meta.Append("\"script_code\": {" + string.Join(",", Data.Scripts.Where(s => s?.Code != null).Select(s => J(s.Name.Content) + ":" + J(s.Code.Name.Content))) + "},\n");

// ---- Objects: parent, sprite, mask, depth, flags and events (type, subtype, code entry).
meta.Append("\"objects\": [\n");
for (int i = 0; i < Data.GameObjects.Count; i++)
{
    var o = Data.GameObjects[i];
    var ev = new List<string>();
    for (int t = 0; t < o.Events.Count; t++)
        foreach (var e in o.Events[t])
        {
            var act = e.Actions.FirstOrDefault(a => a.CodeId != null);
            if (act != null) ev.Add($"[{t},{e.EventSubtype},{J(act.CodeId.Name.Content)}]");
        }
    meta.Append($"{{\"name\":{J(o.Name.Content)},\"parent\":{N(o.ParentId)},\"sprite\":{N(o.Sprite)},\"mask\":{N(o.TextureMaskId)}," +
        $"\"depth\":{o.Depth},\"visible\":{(o.Visible ? 1 : 0)},\"persistent\":{(o.Persistent ? 1 : 0)},\"solid\":{(o.Solid ? 1 : 0)},\"events\":[{string.Join(",", ev)}]}}" +
        (i < Data.GameObjects.Count - 1 ? ",\n" : "\n"));
}
meta.Append("],\n");

// ---- Rooms the battle uses: size, speed, creation code, instances.
meta.Append("\"rooms\": {\n");
string[] rooms = { "room_battle", "room_gameover" };
for (int ri = 0; ri < rooms.Length; ri++)
{
    var r = Data.Rooms.ByName(rooms[ri]);
    var inst = r.GameObjects.Select(g => $"[{J(g.ObjectDefinition?.Name?.Content)},{g.X},{g.Y},{g.ScaleX},{g.ScaleY},{g.InstanceID},{(g.CreationCode == null ? "null" : J(g.CreationCode.Name.Content))}]");
    meta.Append($"  {J(rooms[ri])}: {{\"width\":{r.Width},\"height\":{r.Height},\"speed\":{r.Speed},\"code\":{(r.CreationCodeId == null ? "null" : J(r.CreationCodeId.Name.Content))},\"instances\":[{string.Join(",", inst)}]}}" + (ri < rooms.Length - 1 ? ",\n" : "\n"));
}
meta.Append("},\n");

using (var worker = new TextureWorker())
{
    // ---- Sprites: every frame (padded to full size), collision masks as raw bytes.
    meta.Append("\"sprites\": {\n");
    bool first = true;
    foreach (var spr in Data.Sprites)
    {
        if (spr == null) continue;
        int frames = 0;
        for (int i = 0; i < spr.Textures.Count; i++)
        {
            if (spr.Textures[i]?.Texture == null) continue;
            worker.ExportAsPNG(spr.Textures[i].Texture, Path.Combine(sprDir, $"{spr.Name.Content}_{i}.png"), null, true);
            frames++;
        }
        int stride = ((int)spr.Width + 7) / 8;
        for (int m = 0; m < spr.CollisionMasks.Count; m++)
        {
            byte[] bits = spr.CollisionMasks[m].Data;
            var outb = new byte[spr.Width * spr.Height];
            for (int y = 0; y < spr.Height; y++)
                for (int x = 0; x < spr.Width; x++)
                {
                    int idx = (y * stride) + (x / 8);
                    outb[y * spr.Width + x] = (byte)(idx < bits.Length && (bits[idx] & (0x80 >> (x % 8))) != 0 ? 1 : 0);
                }
            File.WriteAllBytes(Path.Combine(sprDir, $"{spr.Name.Content}_mask{m}.bin"), outb);
        }
        if (!first) meta.Append(",\n");
        first = false;
        meta.Append($"  {J(spr.Name.Content)}: [{frames},{spr.Width},{spr.Height},{spr.OriginX},{spr.OriginY},{spr.MarginLeft},{spr.MarginRight},{spr.MarginTop},{spr.MarginBottom},{(int)spr.SepMasks},{spr.CollisionMasks.Count}]");
    }
    meta.Append("\n},\n");

    // ---- Backgrounds.
    meta.Append("\"backgrounds\": {");
    first = true;
    foreach (var bg in Data.Backgrounds)
    {
        if (bg?.Texture == null) continue;
        worker.ExportAsPNG(bg.Texture, Path.Combine(bgDir, bg.Name.Content + ".png"));
        meta.Append((first ? "" : ",") + $"{J(bg.Name.Content)}:[{bg.Texture.BoundingWidth},{bg.Texture.BoundingHeight}]");
        first = false;
    }
    meta.Append("},\n");

    // ---- Fonts: glyph sheet + table.
    meta.Append("\"fonts\": {");
    first = true;
    foreach (var font in Data.Fonts)
    {
        if (font == null) continue;
        worker.ExportAsPNG(font.Texture, Path.Combine(fntDir, font.Name.Content + ".png"));
        var g = new StringBuilder();
        foreach (var gl in font.Glyphs) g.Append($"{gl.Character};{gl.SourceX};{gl.SourceY};{gl.SourceWidth};{gl.SourceHeight};{gl.Shift};{gl.Offset}\n");
        File.WriteAllText(Path.Combine(fntDir, font.Name.Content + ".glyphs"), g.ToString());
        meta.Append((first ? "" : ",") + $"{J(font.Name.Content)}:[{font.EmSize},{font.ScaleX},{font.ScaleY}]");
        first = false;
    }
    meta.Append("},\n");
}

// ---- Sounds: embedded ones as files; external ones are the .ogg files beside data.win.
meta.Append("\"sounds\": {");
bool firstS = true;
foreach (var snd in Data.Sounds)
{
    if (snd == null) continue;
    string file = "";
    // Only sounds flagged as embedded live in the data file; the others (all music) are
    // .ogg files beside it, and their AudioFile points at an unrelated embedded clip.
    if (snd.AudioFile != null && snd.Flags.HasFlag(UndertaleSound.AudioEntryFlags.IsEmbedded))
    {
        file = snd.Name.Content + ".wav";
        File.WriteAllBytes(Path.Combine(sndDir, file), snd.AudioFile.Data);
    }
    else if (snd.File != null)
        file = "ext:" + snd.File.Content;
    meta.Append((firstS ? "" : ",") + $"{J(snd.Name.Content)}:[{J(file)},{snd.Volume},{snd.Pitch}]");
    firstS = false;
}
meta.Append("}\n}\n");
File.WriteAllText(Path.Combine(outDir, "engine.json"), meta.ToString());
Console.WriteLine($"UBE-ENGINE-EXTRACT ok code={okCode} code_failed={badCode} sprites={Data.Sprites.Count} sounds={Data.Sounds.Count} objects={Data.GameObjects.Count}");
