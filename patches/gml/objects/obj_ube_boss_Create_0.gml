// Data-driven custom boss. It follows the same protocol the original monsters use with
// obj_battlecontroller (modelled on obj_fakefroggit / obj_froggit): scr_monstersetup,
// global.hurtanim, alarm 5/6 for the speech turn, global.mnfight == 2 for the attack
// turn, whatiheard for ACTs and scr_mercystandard for sparing.
scr_monstersetup(0, 0, 0, 0, 0);
global.monstername[myself] = global.ube_cb_name;
global.monstermaxhp[myself] = global.ube_cb_hp;
global.monsterhp[myself] = global.ube_cb_hp;
global.monsteratk[myself] = global.ube_cb_atk;
global.monsterdef[myself] = global.ube_cb_def;
global.xpreward[myself] = global.ube_cb_xp;
global.goldreward[myself] = global.ube_cb_gold;

// Sprite: a PNG next to the boss file, else one of the game's sprites by name.
var spr = -1;
if (global.ube_cb_spritefile != "")
{
    if (file_exists("custom/" + global.ube_cb_spritefile))
    {
        spr = sprite_add("custom/" + global.ube_cb_spritefile, 1, false, false, 0, 0);
    }
}
if (spr < 0)
{
    spr = asset_get_index(global.ube_cb_sprite);
    if (spr >= 0)
    {
        if (asset_get_type(global.ube_cb_sprite) != asset_sprite)
        {
            spr = -1;
        }
    }
}
if (spr < 0)
{
    spr = object_get_sprite(obj_dummymonster);
}
sprite_index = spr;
image_speed = 0;
image_index = 0;
image_xscale = global.ube_cb_scale;
image_yscale = global.ube_cb_scale;
x = round((320 - (sprite_width / 2)) + (sprite_get_xoffset(spr) * global.ube_cb_scale));
y = round((236 - sprite_height) + (sprite_get_yoffset(spr) * global.ube_cb_scale));
ht = sprite_height;
wd = sprite_width;

hurtanim = 0;
hurtsound = snd_ehurt1;
hurt_started = 0;
shudder = 0;
talked = 0;
whatiheard = -1;
attacked = 0;
killed = 0;
global.heard = 0;
takedamage = 0;
mycommand = 0;
dmgwriter = noone;
blcon = noone;
blconwd = noone;
spare_points = 0;
turn_n = 0;
cur = -1;
atk_t = 0;
wall_side = 0;
// scr_mercystandard: mercy = HP - AT - weapon + DEF - mercymod, spareable when below 0.
// A huge negative mercymod means "never spareable"; a huge positive one "spareable".
mercymod = -99999;
if (global.ube_cb_spare_lowhp == 1)
{
    mercymod = 3;
}

// ACT menu. The original lays six slots out as a left column (0, 1, 2) and a right
// column (3, 4, 5). Check is slot 0; custom acts fill 3, 1, 4, 2, 5 so they read
// left-to-right, top-to-bottom.
var order;
order[0] = 3;
order[1] = 1;
order[2] = 4;
order[3] = 2;
order[4] = 5;
var k;
for (k = 0; k < 6; k += 1)
{
    slot_name[k] = "";
    slot_act[k] = -1;
    ch[k] = 0;
}
slot_name[0] = "Check";
ch[0] = 1;
for (k = 0; k < global.ube_cb_act_n; k += 1)
{
    slot_name[order[k]] = global.ube_cb_act_name[k];
    slot_act[order[k]] = k;
    ch[order[k]] = 1;
}
menu_str = "";
var r;
for (r = 0; r < 3; r += 1)
{
    if (slot_name[r] != "" || slot_name[r + 3] != "")
    {
        if (menu_str != "")
        {
            menu_str += "&";
        }
        var left = slot_name[r];
        var row = "     ";
        if (left != "")
        {
            row = "   * ";
        }
        row += left;
        if (slot_name[r + 3] != "")
        {
            repeat (14 - string_length(left))
            {
                row += " ";
            }
            row += "* " + slot_name[r + 3];
        }
        menu_str += row;
    }
}
ube_log("CUSTOM boss=" + global.ube_cb_name + " hp=" + string(global.monsterhp[myself]) + " atk=" + string(global.monsteratk[myself]) + " def=" + string(global.monsterdef[myself]) + " acts=" + string(global.ube_cb_act_n) + " attacks=" + string(global.ube_cb_atk_n) + " slot=" + string(myself));
