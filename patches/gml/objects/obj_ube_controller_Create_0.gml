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
    global.ube_sweep_i = floor(ini_read_real("Test", "Start", 0));
    global.ube_sweep_power = floor(ini_read_real("Test", "Power", 0));
    global.ube_wasd = clamp(floor(ini_read_real("Settings", "Movement", 0)), 0, 1);
    // Equipment lists are exactly the item IDs handled by scr_weaponeq / scr_armoreq.
    global.ube_wlist[0] = 3;
    global.ube_wlist[1] = 13;
    global.ube_wlist[2] = 14;
    global.ube_wlist[3] = 25;
    global.ube_wlist[4] = 45;
    global.ube_wlist[5] = 47;
    global.ube_wlist[6] = 49;
    global.ube_wlist[7] = 51;
    global.ube_wlist[8] = 52;
    global.ube_wn = 9;
    global.ube_alist[0] = 4;
    global.ube_alist[1] = 12;
    global.ube_alist[2] = 15;
    global.ube_alist[3] = 24;
    global.ube_alist[4] = 44;
    global.ube_alist[5] = 46;
    global.ube_alist[6] = 48;
    global.ube_alist[7] = 50;
    global.ube_alist[8] = 53;
    global.ube_alist[9] = 64;
    global.ube_an = 10;
    global.ube_item_max = 64;
    var cfg_w = floor(ini_read_real("Player", "Weapon", 3));
    var cfg_a = floor(ini_read_real("Player", "Armor", 4));
    var ci;
    global.ube_weapon = 3;
    global.ube_armor = 4;
    for (ci = 0; ci < global.ube_wn; ci += 1)
    {
        if (global.ube_wlist[ci] == cfg_w)
        {
            global.ube_weapon = cfg_w;
        }
    }
    for (ci = 0; ci < global.ube_an; ci += 1)
    {
        if (global.ube_alist[ci] == cfg_a)
        {
            global.ube_armor = cfg_a;
        }
    }
    for (ci = 0; ci < 8; ci += 1)
    {
        global.ube_item[ci] = clamp(floor(ini_read_real("Player", "Item" + string(ci), 0)), 0, global.ube_item_max);
    }
    global.ube_mus_on = 0;
    // Training Mode (all of it is ignored while Enabled is 0 = Authentic Mode).
    global.ube_training = clamp(floor(ini_read_real("Training", "Enabled", 0)), 0, 1);
    global.ube_t_infhp = clamp(floor(ini_read_real("Training", "InfiniteHP", 1)), 0, 1);
    global.ube_t_retry = clamp(floor(ini_read_real("Training", "Retry", 1)), 0, 1);
    global.ube_t_hitbox = clamp(floor(ini_read_real("Training", "Hitboxes", 0)), 0, 1);
    global.ube_t_speedlist[0] = 50;
    global.ube_t_speedlist[1] = 75;
    global.ube_t_speedlist[2] = 100;
    global.ube_t_speedlist[3] = 125;
    global.ube_t_speedlist[4] = 150;
    global.ube_t_speedlist[5] = 200;
    global.ube_t_speed = 100;
    var cfg_s = floor(ini_read_real("Training", "Speed", 100));
    for (ci = 0; ci < 6; ci += 1)
    {
        if (global.ube_t_speedlist[ci] == cfg_s)
        {
            global.ube_t_speed = cfg_s;
        }
    }
    global.ube_t_hits = 0;
    global.ube_t_dmg = 0;
    global.ube_t_lethal = 0;
    ini_close();
    instance_create(0, 0, obj_ube_input);
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
scroll = 0;
vis = 99;
// Title logo (the game's own sprite). The sprite is mostly transparent padding around
// the logo, so it is drawn 300 px tall and positioned so the logo sits above the subtitle.
logo_s = 300 / sprite_get_height(spr_undertaletitle);
res_win = 0;
res_kills = 0;
res_xp = 0;
res_gold = 0;
res_hp = 0;
res_maxhp = 0;
res_story = 0;
res_training = 0;
res_hits = 0;
res_dmg = 0;
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
menu_on[2] = 1;
menu_on[3] = 0;
menu_on[4] = 0;
menu_on[5] = 1;
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
