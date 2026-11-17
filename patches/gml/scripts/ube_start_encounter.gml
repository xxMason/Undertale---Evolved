// ube_start_encounter(index): INITIALISING -> IN_BATTLE.
var idx = argument0;
global.ube_state = 2;
caster_free(all);
global.ube_mus_on = 0;
// Every fight starts on a clean timeline. The original keeps story memory in these files
// (death counts, what Flowey, Sans, Papyrus, Toriel and Asgore remember, reset and ending
// flags); without clearing them one fight would change the dialogue and behaviour of the
// next, and some flags redirect the game at start-up. All of this is in the simulator's
// own save folder, never the original game's.
var sf;
if (file_exists("undertale.ini"))
{
    file_delete("undertale.ini");
}
for (sf = 0; sf < 10; sf += 1)
{
    if (file_exists("file" + string(sf)))
    {
        file_delete("file" + string(sf));
    }
}
if (file_exists("system_information_962"))
{
    file_delete("system_information_962");
}
if (file_exists("system_information_963"))
{
    file_delete("system_information_963");
}
SCR_GAMESTART();
global.inbattle = 0;
global.ube_last = idx;
ube_apply_player();
// Fights started by the Battle Creator editor (1 = TEST FIGHT, 2 = attack lab) return to
// the editor instead of the results screen. Every other start clears this.
global.ube_ed_return = global.ube_ed_pending;
global.ube_lab = global.ube_lab_pending;
global.ube_ed_pending = 0;
global.ube_lab_pending = -1;
var enc_id = "";
if (idx >= 1000)
{
    // Custom boss (Battle Creator). Type and battlegroup 777 have no case in the
    // original scripts, so obj_battlecontroller sets the battle up with no monster and
    // obj_ube_input's Room Start then adds obj_ube_boss and its music.
    ube_load_boss(global.ube_cbl_file[idx - 1000]);
    global.ube_custom = 1;
    global.ube_last_name = global.ube_cb_name;
    enc_id = "custom:" + global.ube_cbl_file[idx - 1000];
    global.battlegroup = 777;
    global.monstertype[0] = 777;
    global.monstertype[1] = 0;
    global.monstertype[2] = 0;
    global.battlelv = 0;
    global.actfirst = 0;
    global.extraintro = 0;
    global.msc = 0;
    global.msg[0] = global.ube_cb_intro;
}
else
{
    global.ube_custom = 0;
    global.ube_last_name = global.ube_enc_name[idx];
    enc_id = global.ube_enc_id[idx];
    // Encounter adapters. 0 = generic_battlegroup.
    switch (global.ube_enc_adapter[idx])
    {
        case 0:
            global.battlegroup = global.ube_enc_group[idx];
            break;
    }
}
// Training Mode helper exists only while Training Mode is on.
if (global.ube_training == 1)
{
    if (!instance_exists(obj_ube_trainer))
    {
        instance_create(0, 0, obj_ube_trainer);
    }
}
else
{
    with (obj_ube_trainer)
    {
        instance_destroy();
    }
}
global.ube_t_hits = 0;
global.ube_t_dmg = 0;
global.ube_t_lethal = 0;
global.currentroom = room_ube_menu;
global.ube_result = 0;
global.ube_state = 3;
// Scenario "trace": seed the generator after SCR_GAMESTART's randomize(), right before the
// battle room is built, so the fight's random numbers are reproducible.
if (global.ube_test == "trace")
{
    global.battlegroup = global.ube_trace_group;
    random_set_seed(global.ube_trace_seed);
    // The game clock some attacks read (Toriel's helix: sin(obj_time.time / 20)) starts
    // from 0 here, as it does in the Godot engine, instead of counting the time in the menu.
    with (obj_time)
    {
        time = 0;
    }
}
ube_log("STATE IN_BATTLE id=" + enc_id +" battlegroup=" + string(global.battlegroup) + " lv=" + string(global.lv) + " hp=" + string(global.hp) + "/" + string(global.maxhp) + " training=" + string(global.ube_training));
room_goto(room_battle);
