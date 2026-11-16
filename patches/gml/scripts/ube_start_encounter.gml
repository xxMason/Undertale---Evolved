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
// Encounter adapters. 0 = generic_battlegroup.
switch (global.ube_enc_adapter[idx])
{
    case 0:
        global.battlegroup = global.ube_enc_group[idx];
        break;
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
ube_log("STATE IN_BATTLE id=" + global.ube_enc_id[idx] + " battlegroup=" + string(global.battlegroup) + " lv=" + string(global.lv) + " hp=" + string(global.hp) + "/" + string(global.maxhp) + " training=" + string(global.ube_training));
room_goto(room_battle);
