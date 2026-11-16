// ube_start_encounter(index): INITIALISING -> IN_BATTLE.
var idx = argument0;
global.ube_state = 2;
caster_free(all);
global.ube_mus_on = 0;
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
global.currentroom = room_ube_menu;
global.ube_result = 0;
global.ube_state = 3;
ube_log("STATE IN_BATTLE id=" + global.ube_enc_id[idx] + " battlegroup=" + string(global.battlegroup) + " lv=" + string(global.lv) + " hp=" + string(global.hp) + "/" + string(global.maxhp));
room_goto(room_battle);
