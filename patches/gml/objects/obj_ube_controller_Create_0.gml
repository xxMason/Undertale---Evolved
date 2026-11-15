// States: 0 MENU, 1 CONFIGURING, 2 INITIALISING, 3 IN_BATTLE, 4 VICTORY,
//         5 DEFEAT, 6 RESULTS, 7 RETURNING_TO_MENU, 8 ERROR
if (!variable_global_exists("ube_boot"))
{
    global.ube_boot = 1;
    global.ube_state = 0;
    global.ube_result = 0;
    global.ube_lv = 1;
    global.ube_hp = 0;
    global.ube_last = 0;
    global.ube_xp0 = 0;
    global.ube_test = "";
    global.ube_test_runs = 0;
    global.ube_tab_area = 0;
    global.ube_tab_cat = 0;
    ube_catalogue();
    ini_open("ube_config.ini");
    global.ube_lv = clamp(floor(ini_read_real("Player", "LOVE", 1)), 1, 20);
    global.ube_hp = floor(ini_read_real("Player", "HP", 0));
    global.ube_test = ini_read_string("Test", "Scenario", "");
    ini_close();
    ube_log("BOOT build=" + global.ube_build + " lv=" + string(global.ube_lv) + " hp=" + string(global.ube_hp) + " test=" + global.ube_test + " steam=" + string(steam_initialised()));
    if (global.ube_test != "")
    {
        instance_create(0, 0, obj_ube_testdriver);
    }
}
page = 0;
sel = 0;
ptimer = 0;
hold = 0;
mx_prev = mouse_x;
my_prev = mouse_y;
row_x = 0;
row_y0 = 0;
row_h = 0;
row_n = 0;
// Fight Select: focus 0 = area tabs, 1 = Monsters/Bosses tabs, 2 = fight list.
focus = 2;
fn = 0;
res_win = 0;
res_kills = 0;
res_xp = 0;
res_gold = 0;
res_hp = 0;
res_maxhp = 0;
menu_n = 7;
menu_txt[0] = "FIGHT SELECT";
menu_txt[1] = "PLAYER SETUP";
menu_txt[2] = "TRAINING MODE";
menu_txt[3] = "CUSTOM BATTLES";
menu_txt[4] = "STATISTICS";
menu_txt[5] = "SETTINGS";
menu_txt[6] = "EXIT";
menu_on[0] = 1;
menu_on[1] = 1;
menu_on[2] = 0;
menu_on[3] = 0;
menu_on[4] = 0;
menu_on[5] = 0;
menu_on[6] = 1;
if (global.ube_state == 3 || global.ube_state == 7)
{
    // We just came back from a battle (victory, mercy, flee or game over).
    // State 7 is accepted too because the original obj_gameover issues room_goto twice,
    // which re-creates this room (and this controller) before the result is processed.
    global.ube_state = 7;
    page = 4;
}
else
{
    global.ube_state = 0;
}
