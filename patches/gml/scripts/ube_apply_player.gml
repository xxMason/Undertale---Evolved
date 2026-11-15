// ube_apply_player(): apply the configured LOVE and starting HP to the original globals.
// Must run after SCR_GAMESTART and before the encounter adapter.
// Stat formulas mirror gml_Object_obj_battlecontroller_Create_0 (which recomputes
// maxhp/at/df from LV at battle start) so nothing here is overwritten unexpectedly.
var xpt;
xpt[1] = 0;
xpt[2] = 10;
xpt[3] = 30;
xpt[4] = 70;
xpt[5] = 120;
xpt[6] = 200;
xpt[7] = 300;
xpt[8] = 500;
xpt[9] = 800;
xpt[10] = 1200;
xpt[11] = 1700;
xpt[12] = 2500;
xpt[13] = 3500;
xpt[14] = 5000;
xpt[15] = 7000;
xpt[16] = 10000;
xpt[17] = 15000;
xpt[18] = 25000;
xpt[19] = 50000;
xpt[20] = 99999;
global.lv = global.ube_lv;
global.xp = xpt[global.lv];
global.maxhp = 16 + (global.lv * 4);
global.at = 8 + (global.lv * 2);
global.df = 9 + ceil(global.lv / 4);
if (global.lv == 20)
{
    global.maxhp = 99;
    global.at = 30;
    global.df = 30;
}
global.hp = global.maxhp;
if (global.ube_hp >= 1 && global.ube_hp <= global.maxhp)
{
    global.hp = global.ube_hp;
}
global.ube_xp0 = global.xp;
