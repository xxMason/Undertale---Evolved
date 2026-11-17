// Extracts the assets the Godot prototype needs from the player's own data.win.
// Read-only: never saves the data file. Output is never committed (godot/extracted/).
// Usage: UndertaleModCli load <data.win> -s scripts/extract_for_godot.csx
// Env:   UBE_GODOT_OUT = output folder
using System;
using System.IO;
using System.Linq;
using System.Text;
using UndertaleModLib.Util;

EnsureDataLoaded();

string outDir = Environment.GetEnvironmentVariable("UBE_GODOT_OUT");
if (string.IsNullOrEmpty(outDir)) throw new Exception("UBE_GODOT_OUT is not set");
string sprDir = Path.Combine(outDir, "sprites");
string fntDir = Path.Combine(outDir, "fonts");
string sndDir = Path.Combine(outDir, "sounds");
Directory.CreateDirectory(sprDir);
Directory.CreateDirectory(fntDir);
Directory.CreateDirectory(sndDir);

string[] sprites = { "spr_heart", "spr_fightbt", "spr_talkbt", "spr_itembt", "spr_sparebt", "spr_border",
    "spr_battlebg", "spr_hpname", "spr_bulletmd", "spr_bulletsm", "spr_dummybattle",
    "spr_target", "spr_targetchoice", "spr_strike", "spr_dmgnum_o", "spr_dmgmiss_o", "spr_heartgtfo" };
string[] fonts = { "fnt_main", "fnt_maintext", "fnt_curs", "fnt_dmg", "fnt_small" };
string[] sounds = { "snd_hurt1", "snd_select", "snd_squeak", "snd_damage", "snd_power",
    "SND_TXT2", "snd_laz", "snd_ehurt1", "snd_heal_c", "snd_vaporized", "snd_escaped" };

static string J(string s) => "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
var meta = new StringBuilder();
meta.Append("{\n");

using (var worker = new TextureWorker())
{
    // ---- Sprites: every frame as a full-size PNG, plus origin, bounding box and mask.
    meta.Append("\"sprites\": {\n");
    bool firstSprite = true;
    foreach (string name in sprites)
    {
        var spr = Data.Sprites.ByName(name) ?? throw new Exception("Missing sprite " + name);
        for (int i = 0; i < spr.Textures.Count; i++)
            worker.ExportAsPNG(spr.Textures[i].Texture, Path.Combine(sprDir, $"{name}_{i}.png"), null, true);
        // Collision masks as rows of 0/1 (one file per mask).
        for (int m = 0; m < spr.CollisionMasks.Count; m++)
        {
            byte[] bits = spr.CollisionMasks[m].Data;
            int stride = ((int)spr.Width + 7) / 8;
            var rows = new StringBuilder();
            for (int y = 0; y < spr.Height; y++)
            {
                for (int x = 0; x < spr.Width; x++)
                {
                    int idx = (y * stride) + (x / 8);
                    bool on = idx < bits.Length && (bits[idx] & (0x80 >> (x % 8))) != 0;
                    rows.Append(on ? '1' : '0');
                }
                rows.Append('\n');
            }
            File.WriteAllText(Path.Combine(sprDir, $"{name}_mask{m}.txt"), rows.ToString());
        }
        if (!firstSprite) meta.Append(",\n");
        firstSprite = false;
        meta.Append($"  {J(name)}: {{\"frames\": {spr.Textures.Count}, \"width\": {spr.Width}, \"height\": {spr.Height}, " +
            $"\"xoff\": {spr.OriginX}, \"yoff\": {spr.OriginY}, \"bbox_left\": {spr.MarginLeft}, \"bbox_right\": {spr.MarginRight}, " +
            $"\"bbox_top\": {spr.MarginTop}, \"bbox_bottom\": {spr.MarginBottom}, \"mask_kind\": {J(spr.SepMasks.ToString())}, " +
            $"\"bbox_mode\": {spr.BBoxMode}, \"masks\": {spr.CollisionMasks.Count}}}");
    }
    meta.Append("\n},\n");

    // ---- Fonts: glyph sheet PNG + glyph table.
    meta.Append("\"fonts\": {\n");
    bool firstFont = true;
    foreach (string name in fonts)
    {
        var font = Data.Fonts.ByName(name) ?? throw new Exception("Missing font " + name);
        worker.ExportAsPNG(font.Texture, Path.Combine(fntDir, $"{name}.png"));
        var glyphs = new StringBuilder();
        foreach (var g in font.Glyphs)
            glyphs.Append($"{g.Character};{g.SourceX};{g.SourceY};{g.SourceWidth};{g.SourceHeight};{g.Shift};{g.Offset}\n");
        File.WriteAllText(Path.Combine(fntDir, $"{name}.glyphs"), glyphs.ToString());
        if (!firstFont) meta.Append(",\n");
        firstFont = false;
        meta.Append($"  {J(name)}: {{\"size\": {font.EmSize}, \"scale_x\": {font.ScaleX}, \"scale_y\": {font.ScaleY}, \"glyphs\": {font.Glyphs.Count}}}");
    }
    meta.Append("\n},\n");
}

// ---- Sound effects embedded in data.win (music files sit next to it as .ogg).
meta.Append("\"sounds\": [");
bool firstSound = true;
foreach (string name in sounds)
{
    var snd = Data.Sounds.ByName(name) ?? throw new Exception("Missing sound " + name);
    if (snd.AudioFile is null) throw new Exception("Sound " + name + " is not embedded");
    File.WriteAllBytes(Path.Combine(sndDir, name + ".wav"), snd.AudioFile.Data);
    meta.Append((firstSound ? "" : ", ") + J(name));
    firstSound = false;
}
meta.Append("]\n}\n");
File.WriteAllText(Path.Combine(outDir, "assets.json"), meta.ToString());
Console.WriteLine($"UBE-GODOT-EXTRACT ok sprites={sprites.Length} fonts={fonts.Length} sounds={sounds.Length}");
