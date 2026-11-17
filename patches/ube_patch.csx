// Ultimate Battle Engine - reproducible data.win patch.
// Run by the launcher / build script:
//   UndertaleModCli load <ORIGINAL data.win> -s patches/ube_patch.csx -o <working copy>/data.win
// The original file is only ever opened for reading; output goes to the working copy.
// Env: UBE_ROOT = project root (contains patches/ and config/).
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

EnsureDataLoaded();

const string IsolatedName = "UltimateBattleEngine";
const string BuildId = "0.1.0-m1";

string root = Environment.GetEnvironmentVariable("UBE_ROOT");
if (string.IsNullOrEmpty(root) || !Directory.Exists(Path.Combine(root, "patches")))
    throw new Exception("UBE_ROOT is not set to the project root");
string gmlDir = Path.Combine(root, "patches", "gml");

// ---- 0. Compatibility guard -------------------------------------------------------------
if (Data.GeneralInfo.Name.Content != "UNDERTALE" || Data.GeneralInfo.BytecodeVersion != 16 || Data.IsGameMaker2())
    throw new Exception("Unsupported data file: expected unmodified UNDERTALE v1.08 (GMS 1.4, bytecode 16)");
foreach (string required in new[] { "obj_time", "obj_screen", "obj_gameover", "obj_battlecontroller", "obj_froggit", "obj_heart" })
    if (Data.GameObjects.ByName(required) == null) throw new Exception("Missing expected object " + required);
foreach (string required in new[] { "room_start", "room_battle", "room_gameover" })
    if (Data.Rooms.ByName(required) == null) throw new Exception("Missing expected room " + required);
if (Data.GeneralInfo.RoomOrder[0].Resource != Data.Rooms.ByName("room_start"))
    throw new Exception("Unexpected room order");
if (Data.Rooms.ByName("room_ube_menu") != null)
    throw new Exception("This data file is already patched");

// ---- 1. Save isolation ------------------------------------------------------------------
// The GMS 1.4 runner derives its save directory (%LOCALAPPDATA%\<name>) from GEN8.
// New string objects are created so the shared "UNDERTALE" string is left untouched.
Data.GeneralInfo.Name = Data.Strings.MakeString(IsolatedName);
Data.GeneralInfo.DisplayName = Data.Strings.MakeString(IsolatedName);
Data.GeneralInfo.FileName = Data.Strings.MakeString(IsolatedName);
Data.GeneralInfo.SteamAppID = 0;

// ---- 2. New assets ----------------------------------------------------------------------
UndertaleGameObject NewObject(string name, bool persistent)
{
    var o = new UndertaleGameObject() { Name = Data.Strings.MakeString(name), Persistent = persistent, Visible = true };
    Data.GameObjects.Add(o);
    return o;
}
UndertaleCode NewScript(string name)
{
    var code = UndertaleCode.CreateEmptyEntry(Data, "gml_Script_" + name);
    Data.Scripts.Add(new UndertaleScript() { Name = Data.Strings.MakeString(name), Code = code });
    return code;
}

var controller = NewObject("obj_ube_controller", false);
controller.Depth = -1000;
var testdriver = NewObject("obj_ube_testdriver", true);
var inputHelper = NewObject("obj_ube_input", true);
var trainer = NewObject("obj_ube_trainer", true);
trainer.Depth = -9999;
var scrHitboxes = NewScript("ube_draw_hitboxes");

// Battle Creator runtime: a data-driven monster and its bullet. Both inherit from the
// game's own parents, so targeting, collision, damage and end-of-turn clean-up are the
// original code. Type/battlegroup 777 must be unused so no original case matches it.
const int CustomType = 777;
foreach (string scriptName in new[] { "gml_Script_SCR_TEXT", "gml_Script_scr_battlegroup", "gml_Script_scr_monstersetup" })
{
    string txt = GetDecompiledText(Data.Code.ByName(scriptName));
    if (txt.Contains("case " + CustomType + ":") || txt.Contains("case " + (1000 + CustomType) + ":") || txt.Contains("case " + (3000 + CustomType) + ":") || txt.Contains("== " + CustomType + ")"))
        throw new Exception("Custom monster type " + CustomType + " collides with " + scriptName);
}
var customBoss = NewObject("obj_ube_boss", false);
customBoss.ParentId = Data.GameObjects.ByName("obj_monsterparent") ?? throw new Exception("obj_monsterparent missing");
var customBullet = NewObject("obj_ube_bullet", false);
customBullet.ParentId = Data.GameObjects.ByName("blt_parent") ?? throw new Exception("blt_parent missing");
var scrLoadBoss = NewScript("ube_load_boss");

// Battle Creator editor screen: its own larger room so a dense, mouse-driven layout fits.
var editUi = NewObject("obj_ube_editui", false);
var editorRoom = new UndertaleRoom()
{
    Name = Data.Strings.MakeString("room_ube_editor"),
    Caption = Data.Strings.MakeString(""),
    Width = 1280,
    Height = 960,
    Speed = 60
};
// Without a view the runner shows only a 640x480 corner of the room; view 0 maps the
// whole room 1:1 onto the enlarged window.
editorRoom.Flags |= UndertaleRoom.RoomEntryFlags.EnableViews;
editorRoom.Views[0].Enabled = true;
editorRoom.Views[0].ViewX = 0;
editorRoom.Views[0].ViewY = 0;
editorRoom.Views[0].ViewWidth = 1280;
editorRoom.Views[0].ViewHeight = 960;
editorRoom.Views[0].PortX = 0;
editorRoom.Views[0].PortY = 0;
editorRoom.Views[0].PortWidth = 1280;
editorRoom.Views[0].PortHeight = 960;
editorRoom.GameObjects.Add(new UndertaleRoom.GameObject()
{
    InstanceID = Data.GeneralInfo.LastObj++,
    ObjectDefinition = editUi,
    X = 0,
    Y = 0
});
Data.Rooms.Add(editorRoom);
Data.GeneralInfo.RoomOrder.Add(new UndertaleResourceById<UndertaleRoom, UndertaleChunkROOM>() { Resource = editorRoom });

// Battle Creator editor.
var editor = NewObject("obj_ube_editor", false);
editor.Depth = -1100;
string[] editorScripts = { "ube_csv", "ube_csvr", "ube_ed_keys", "ube_ed_get", "ube_ed_set", "ube_ed_load", "ube_ed_save", "ube_index_write", "ube_row", "ube_list_n", "ube_list_get",
    "ube_ui_btn", "ube_ui_step", "ube_live_line", "ube_live_parse", "ube_live_pack", "ube_live_unpack", "ube_live_push", "ube_live_store", "ube_live_load", "ube_live_leave" };
var editorScriptCode = editorScripts.ToDictionary(s => s, s => NewScript(s));

// Hitbox list for Training Mode: every object that has a collision event with obj_heart
// (children are covered by GML's "with"). Generated here so nothing is assumed.
var heartObj = Data.GameObjects.ByName("obj_heart");
uint heartIndex = (uint)Data.GameObjects.IndexOf(heartObj);
var hitboxGml = new StringBuilder();
int hitboxCount = 0;
foreach (var o in Data.GameObjects)
{
    if (o == heartObj || o.Name.Content.StartsWith("obj_ube_")) continue;
    if (!o.Events[(int)EventType.Collision].Any(ev => ev.EventSubtype == heartIndex)) continue;
    hitboxGml.AppendLine("with (" + o.Name.Content + ") { if (sprite_index >= 0 || mask_index >= 0) { draw_rectangle(bbox_left, bbox_top, bbox_right, bbox_bottom, true); } }");
    hitboxCount++;
}
if (hitboxCount == 0) throw new Exception("No objects collide with obj_heart; hitbox list would be empty");

var menuRoom = new UndertaleRoom()
{
    Name = Data.Strings.MakeString("room_ube_menu"),
    Caption = Data.Strings.MakeString(""),
    Width = 640,
    Height = 480,
    Speed = 30
};
menuRoom.GameObjects.Add(new UndertaleRoom.GameObject()
{
    InstanceID = Data.GeneralInfo.LastObj++,
    ObjectDefinition = controller,
    X = 0,
    Y = 0
});
Data.Rooms.Add(menuRoom);
// Boot hook without touching obj_time: its start-up code ends with room_goto_next() from
// room_start, so placing our room second in the room order makes it the first screen.
Data.GeneralInfo.RoomOrder.Insert(1, new UndertaleResourceById<UndertaleRoom, UndertaleChunkROOM>() { Resource = menuRoom });

var scrLog = NewScript("ube_log");
var scrCatalogue = NewScript("ube_catalogue");
var scrApply = NewScript("ube_apply_player");
var scrStart = NewScript("ube_start_encounter");
var scrSave = NewScript("ube_save_config");

foreach (string fn in new[] { "file_text_open_append", "file_text_write_string", "file_text_writeln", "file_text_close",
    "ini_open", "ini_close", "ini_read_real", "ini_read_string", "ini_write_real", "screen_save", "game_end",
    "keyboard_key_press", "keyboard_key_release", "mouse_check_button_pressed", "window_set_caption",
    "variable_global_exists", "steam_initialised", "room_get_name", "keyboard_check_direct", "sprite_get_width", "sprite_get_height", "sprite_get_xoffset", "sprite_get_yoffset", "draw_sprite_ext", "min", "max", "asset_get_index", "asset_get_type", "sprite_add", "object_get_sprite",
    "lengthdir_x", "lengthdir_y", "point_direction", "string_upper", "string_copy", "string_pos", "string_length",
    "ds_map_create", "ds_map_clear", "ds_map_exists", "ds_map_add", "ds_map_replace", "ds_map_find_value",
    "string_replace_all", "chr", "real", "string_delete", "power", "string_char_at", "window_set_size", "window_center", "make_color_rgb", "string_format", "mouse_wheel_up", "mouse_wheel_down", "abs", "draw_triangle", "draw_line", "draw_line_width", "point_distance", "ceil", "mouse_check_button", "surface_resize", "surface_save", "window_get_width",
    "window_get_height", "surface_get_width", "surface_get_height", "window_mouse_get_x", "window_mouse_get_y", "ini_write_string", "draw_self", "instance_destroy", "instance_number",
    "file_exists", "file_delete", "random", "floor", "round", "instance_exists", "caster_loop", "draw_text_transformed", "string_width", "clamp" })
    Data.Functions.EnsureDefined(fn, Data.Strings);

// ---- 3. Encounter catalogue generated from config/encounters.json ------------------------
string GmlString(string s) => "\"" + s.Replace("\\", "").Replace("\"", "'") + "\"";
var cat = new StringBuilder();
cat.AppendLine("global.ube_build = " + GmlString(BuildId) + ";");
using (var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "config", "encounters.json"))))
{
    // Areas and their Monsters (0) / Bosses (1) tabs.
    var areaIds = new System.Collections.Generic.List<string>();
    var areaTabs = new System.Collections.Generic.List<bool[]>();
    foreach (var a in doc.RootElement.GetProperty("areas").EnumerateArray())
    {
        var has = new bool[2];
        foreach (var t in a.GetProperty("tabs").EnumerateArray())
        {
            string tab = t.GetString();
            if (tab == "monsters") has[0] = true;
            else if (tab == "bosses") has[1] = true;
            else throw new Exception("Unknown tab " + tab);
        }
        if (!has[0] && !has[1]) throw new Exception("Area without tabs: " + a.GetProperty("id").GetString());
        int ai = areaIds.Count;
        areaIds.Add(a.GetProperty("id").GetString());
        areaTabs.Add(has);
        cat.AppendLine($"global.ube_area_name[{ai}] = {GmlString(a.GetProperty("label").GetString())};");
        cat.AppendLine($"global.ube_area_has[{ai * 2}] = {(has[0] ? 1 : 0)};");
        cat.AppendLine($"global.ube_area_has[{ai * 2 + 1}] = {(has[1] ? 1 : 0)};");
    }
    cat.AppendLine($"global.ube_area_count = {areaIds.Count};");

    int n = 0;
    foreach (var e in doc.RootElement.GetProperty("encounters").EnumerateArray())
    {
        string adapter = e.GetProperty("adapter").GetString();
        int adapterId = adapter == "generic_battlegroup" ? 0 : throw new Exception("Unknown adapter " + adapter);
        string encId = e.GetProperty("id").GetString();
        int areaIdx = areaIds.IndexOf(e.GetProperty("area").GetString());
        if (areaIdx < 0) throw new Exception("Encounter " + encId + " uses an undeclared area");
        string cls = e.GetProperty("classification").GetString();
        int catIdx = cls == "enemy" ? 0 : (cls == "boss" || cls == "miniboss") ? 1 : throw new Exception("Unknown classification " + cls);
        if (!areaTabs[areaIdx][catIdx]) throw new Exception("Encounter " + encId + " needs a tab its area does not declare");
        cat.AppendLine($"global.ube_enc_id[{n}] = {GmlString(encId)};");
        cat.AppendLine($"global.ube_enc_name[{n}] = {GmlString(e.GetProperty("displayName").GetString())};");
        cat.AppendLine($"global.ube_enc_areaidx[{n}] = {areaIdx};");
        cat.AppendLine($"global.ube_enc_cat[{n}] = {catIdx};");
        cat.AppendLine($"global.ube_enc_group[{n}] = {e.GetProperty("battlegroup").GetInt32()};");
        cat.AppendLine($"global.ube_enc_adapter[{n}] = {adapterId};");
        // 0 = disabled, 1 = verified to the end, 2 = starts and runs but ending unverified.
        int enabledVal = !e.GetProperty("enabled").GetBoolean() ? 0 : e.GetProperty("status").GetString() == "verified" ? 1 : 2;
        cat.AppendLine($"global.ube_enc_enabled[{n}] = {enabledVal};");
        n++;
    }
    cat.AppendLine($"global.ube_enc_count = {n};");
}

// Pick-lists for the Battle Creator editor, generated from the game data.
{
    var monsterParent = Data.GameObjects.ByName("obj_monsterparent");
    var bulletParents = new[] { Data.GameObjects.ByName("blt_parent"), Data.GameObjects.ByName("blt_parent_noborder") };
    var music = Data.Sounds.Select(s => s.Name.Content).Where(s => s.StartsWith("mus_")).Select(s => s.Substring(4)).Distinct().OrderBy(s => s, StringComparer.Ordinal).ToList();
    var bullets = new[] { "spr_bulletmd", "spr_bulletsm" }
        .Concat(Data.GameObjects.Where(o => bulletParents.Contains(o.ParentId) && o.Sprite != null).Select(o => o.Sprite.Name.Content).OrderBy(s => s, StringComparer.Ordinal))
        .Distinct().ToList();
    var bossSprites = new[] { "spr_dummybattle" }
        .Concat(Data.GameObjects.Where(o => o.ParentId == monsterParent && o.Sprite != null).Select(o => o.Sprite.Name.Content).OrderBy(s => s, StringComparer.Ordinal))
        .Distinct().ToList();
    foreach (string required in new[] { "spr_bulletmd", "spr_bulletsm", "spr_dummybattle" })
        if (Data.Sprites.ByName(required) == null) throw new Exception("Missing expected sprite " + required);
    void EmitList(string name, System.Collections.Generic.List<string> items)
    {
        for (int li = 0; li < items.Count; li++) cat.AppendLine($"global.ube_l{name}[{li}] = {GmlString(items[li])};");
        cat.AppendLine($"global.ube_l{name}_n = {items.Count};");
    }
    EmitList("mus", music);
    EmitList("bul", bullets);
    EmitList("spr", bossSprites);
    Console.WriteLine($"UBE-PATCH editor lists: music={music.Count} bullets={bullets.Count} bossSprites={bossSprites.Count}");
}

// ---- 4. Code ----------------------------------------------------------------------------
string Gml(string rel) => File.ReadAllText(Path.Combine(gmlDir, rel));

UndertaleModLib.Compiler.CodeImportGroup importGroup = new(Data)
{
    ThrowOnNoOpFindReplace = true,
    MainThreadAction = MainThreadAction
};
importGroup.QueueReplace(scrLog, Gml("scripts/ube_log.gml"));
importGroup.QueueReplace(scrCatalogue, cat.ToString());
importGroup.QueueReplace(scrApply, Gml("scripts/ube_apply_player.gml"));
importGroup.QueueReplace(scrStart, Gml("scripts/ube_start_encounter.gml"));
importGroup.QueueReplace(scrSave, Gml("scripts/ube_save_config.gml"));
importGroup.QueueReplace(controller.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_controller_Create_0.gml"));
importGroup.QueueReplace(controller.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_controller_Step_0.gml"));
importGroup.QueueReplace(controller.EventHandlerFor(EventType.Draw, (uint)0, Data), Gml("objects/obj_ube_controller_Draw_0.gml"));
importGroup.QueueReplace(testdriver.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_testdriver_Create_0.gml"));
importGroup.QueueReplace(testdriver.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_testdriver_Step_0.gml"));
importGroup.QueueReplace(testdriver.EventHandlerFor(EventType.Step, (uint)2, Data), Gml("objects/obj_ube_testdriver_Step_2.gml"));

importGroup.QueueReplace(inputHelper.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_input_Create_0.gml"));
importGroup.QueueReplace(inputHelper.EventHandlerFor(EventType.Step, (uint)1, Data), Gml("objects/obj_ube_input_Step_1.gml"));

importGroup.QueueReplace(scrHitboxes, hitboxGml.ToString());
importGroup.QueueReplace(scrLoadBoss, Gml("scripts/ube_load_boss.gml"));
foreach (var kv in editorScriptCode)
    importGroup.QueueReplace(kv.Value, Gml("scripts/" + kv.Key + ".gml"));
importGroup.QueueReplace(editUi.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_editui_Create_0.gml"));
importGroup.QueueReplace(editUi.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_editui_Step_0.gml"));
importGroup.QueueReplace(editUi.EventHandlerFor(EventType.Draw, (uint)0, Data), Gml("objects/obj_ube_editui_Draw_0.gml"));
importGroup.QueueReplace(editor.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_editor_Create_0.gml"));
importGroup.QueueReplace(editor.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_editor_Step_0.gml"));
importGroup.QueueReplace(editor.EventHandlerFor(EventType.Draw, (uint)0, Data), Gml("objects/obj_ube_editor_Draw_0.gml"));
importGroup.QueueReplace(customBoss.EventHandlerFor(EventType.Draw, (uint)0, Data), Gml("objects/obj_ube_boss_Draw_0.gml"));
importGroup.QueueReplace(customBullet.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_bullet_Create_0.gml"));
importGroup.QueueReplace(customBullet.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_bullet_Step_0.gml"));
importGroup.QueueReplace(customBullet.EventHandlerFor(EventType.Destroy, Data), Gml("objects/obj_ube_bullet_Destroy_0.gml"));
importGroup.QueueReplace(customBoss.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_boss_Create_0.gml"));
importGroup.QueueReplace(customBoss.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_boss_Step_0.gml"));
foreach (uint alarmNo in new uint[] { 3, 5, 6, 8 })
    importGroup.QueueReplace(customBoss.EventHandlerFor(EventType.Alarm, alarmNo, Data), Gml("objects/obj_ube_boss_Alarm_" + alarmNo + ".gml"));
importGroup.QueueReplace(customBoss.EventHandlerFor(EventType.Destroy, Data), Gml("objects/obj_ube_boss_Destroy_0.gml"));
importGroup.QueueReplace(inputHelper.EventHandlerFor(EventType.Other, (uint)4, Data), Gml("objects/obj_ube_input_Other_4.gml"));
importGroup.QueueReplace(trainer.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_trainer_Create_0.gml"));
importGroup.QueueReplace(trainer.EventHandlerFor(EventType.Other, (uint)4, Data), Gml("objects/obj_ube_trainer_Other_4.gml"));
importGroup.QueueReplace(trainer.EventHandlerFor(EventType.Step, (uint)2, Data), Gml("objects/obj_ube_trainer_Step_2.gml"));
importGroup.QueueReplace(trainer.EventHandlerFor(EventType.Draw, (uint)0, Data), Gml("objects/obj_ube_trainer_Draw_0.gml"));

// The ONLY change to original game code: after the original game-over sequence returns to
// global.currentroom, the game would reload the last save (scr_tempload -> file9), which
// must not exist here. Record a defeat for the menu controller instead.
importGroup.QueueFindReplace(Data.Code.ByName("gml_Object_obj_gameover_Step_0"),
    "script_execute(scr_tempload);",
    "global.ube_result = 2;");

importGroup.Import();

Console.WriteLine("UBE-PATCH ok build=" + BuildId + " name=" + Data.GeneralInfo.Name.Content + " rooms=" + Data.Rooms.Count);
