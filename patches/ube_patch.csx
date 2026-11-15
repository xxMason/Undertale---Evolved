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

foreach (string fn in new[] { "file_text_open_append", "file_text_write_string", "file_text_writeln", "file_text_close",
    "ini_open", "ini_close", "ini_read_real", "ini_read_string", "ini_write_real", "screen_save", "game_end",
    "keyboard_key_press", "keyboard_key_release", "mouse_check_button_pressed", "window_set_caption",
    "variable_global_exists", "steam_initialised", "draw_text_transformed", "string_width", "clamp" })
    Data.Functions.EnsureDefined(fn, Data.Strings);

// ---- 3. Encounter catalogue generated from config/encounters.json ------------------------
string GmlString(string s) => "\"" + s.Replace("\\", "").Replace("\"", "'") + "\"";
var cat = new StringBuilder();
cat.AppendLine("global.ube_build = " + GmlString(BuildId) + ";");
using (var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "config", "encounters.json"))))
{
    int n = 0;
    foreach (var e in doc.RootElement.GetProperty("encounters").EnumerateArray())
    {
        string adapter = e.GetProperty("adapter").GetString();
        int adapterId = adapter == "generic_battlegroup" ? 0 : throw new Exception("Unknown adapter " + adapter);
        cat.AppendLine($"global.ube_enc_id[{n}] = {GmlString(e.GetProperty("id").GetString())};");
        cat.AppendLine($"global.ube_enc_name[{n}] = {GmlString(e.GetProperty("displayName").GetString())};");
        cat.AppendLine($"global.ube_enc_area[{n}] = {GmlString(e.GetProperty("area").GetString())};");
        cat.AppendLine($"global.ube_enc_group[{n}] = {e.GetProperty("requiredGlobals").GetProperty("battlegroup").GetInt32()};");
        cat.AppendLine($"global.ube_enc_adapter[{n}] = {adapterId};");
        cat.AppendLine($"global.ube_enc_enabled[{n}] = {(e.GetProperty("enabled").GetBoolean() ? 1 : 0)};");
        n++;
    }
    cat.AppendLine($"global.ube_enc_count = {n};");
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
importGroup.QueueReplace(controller.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_controller_Create_0.gml"));
importGroup.QueueReplace(controller.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_controller_Step_0.gml"));
importGroup.QueueReplace(controller.EventHandlerFor(EventType.Draw, (uint)0, Data), Gml("objects/obj_ube_controller_Draw_0.gml"));
importGroup.QueueReplace(testdriver.EventHandlerFor(EventType.Create, Data), Gml("objects/obj_ube_testdriver_Create_0.gml"));
importGroup.QueueReplace(testdriver.EventHandlerFor(EventType.Step, (uint)0, Data), Gml("objects/obj_ube_testdriver_Step_0.gml"));

// The ONLY change to original game code: after the original game-over sequence returns to
// global.currentroom, the game would reload the last save (scr_tempload -> file9), which
// must not exist here. Record a defeat for the menu controller instead.
importGroup.QueueFindReplace(Data.Code.ByName("gml_Object_obj_gameover_Step_0"),
    "script_execute(scr_tempload);",
    "global.ube_result = 2;");

importGroup.Import();

Console.WriteLine("UBE-PATCH ok build=" + BuildId + " name=" + Data.GeneralInfo.Name.Content + " rooms=" + Data.Rooms.Count);
