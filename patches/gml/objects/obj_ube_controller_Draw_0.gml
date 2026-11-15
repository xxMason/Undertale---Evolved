draw_set_alpha(1);
draw_set_color(c_black);
draw_rectangle(0, 0, 640, 480, false);
if (page == 4)
{
    exit;
}
draw_set_color(c_white);
draw_rectangle(16, 16, 623, 463, false);
draw_set_color(c_black);
draw_rectangle(21, 21, 618, 458, false);
scr_setfont(fnt_maintext);
// ptimer is 0 only on the frame a page was switched, before Step has laid that page out.
if (ptimer == 0)
{
    exit;
}

var title = "ULTIMATE BATTLE ENGINE";
if (page == 1)
{
    title = "FIGHT SELECT";
}
if (page == 2)
{
    title = "PLAYER SETUP";
}
if (page == 5)
{
    title = "SETTINGS";
}
if (page == 3)
{
    title = "DEFEAT";
    if (res_win == 1)
    {
        title = "BATTLE COMPLETE";
    }
}
draw_set_color(c_white);
if (page == 3)
{
    draw_set_color(c_red);
    if (res_win == 1)
    {
        draw_set_color(c_yellow);
    }
}
draw_text_transformed(320 - string_width(title), 40, title, 2, 2, 0);

var maxhp = 16 + (global.ube_lv * 4);
if (global.ube_lv == 20)
{
    maxhp = 99;
}
var curhp = global.ube_hp;
if (curhp < 1 || curhp > maxhp)
{
    curhp = maxhp;
}

var i;
var label;
for (i = 0; i < row_n; i += 1)
{
    label = "";
    if (page == 0)
    {
        label = menu_txt[i];
    }
    if (page == 1)
    {
        if (i < fn)
        {
            label = global.ube_enc_name[flist[i]];
            if (global.ube_enc_enabled[flist[i]] == 0)
            {
                label += "  (not yet available)";
            }
        }
        else
        {
            label = "BACK";
        }
    }
    if (page == 2)
    {
        if (i == 0)
        {
            label = "LOVE          < " + string(global.ube_lv) + " >";
        }
        if (i == 1)
        {
            label = "STARTING HP   < " + string(curhp) + " / " + string(maxhp) + " >";
        }
        if (i == 2)
        {
            label = "BACK";
        }
    }
    if (page == 3)
    {
        if (i == 0)
        {
            label = "RETRY";
        }
        if (i == 1)
        {
            label = "FIGHT SELECT";
        }
        if (i == 2)
        {
            label = "MAIN MENU";
        }
    }
    if (page == 5)
    {
        if (i == 0)
        {
            label = "MOVEMENT   < ARROW KEYS >";
            if (global.ube_wasd == 1)
            {
                label = "MOVEMENT   < WASD >";
            }
        }
        if (i == 1)
        {
            label = "BACK";
        }
    }
    draw_set_color(c_white);
    if (row_on[i] == 0)
    {
        draw_set_color(c_gray);
    }
    else if (sel == i && (page != 1 || focus == 2))
    {
        draw_set_color(c_yellow);
        draw_sprite(spr_heart, 0, row_x - 32, row_y0 + (i * row_h) + 1);
    }
    draw_text(row_x, row_y0 + (i * row_h), label);
}

if (page == 1)
{
    // Area tabs, then the Monsters/Bosses tabs this area has.
    for (i = 0; i < global.ube_area_count; i += 1)
    {
        draw_set_color(c_white);
        if (i == global.ube_tab_area)
        {
            draw_set_color(c_yellow);
            if (focus == 0)
            {
                draw_sprite(spr_heart, 0, tabx[i] - 19, 89);
            }
        }
        draw_text(tabx[i], 88, "[" + global.ube_area_name[i] + "]");
    }
    for (i = 0; i < 2; i += 1)
    {
        if (ctabx[i] >= 0)
        {
            draw_set_color(c_white);
            if (i == global.ube_tab_cat)
            {
                draw_set_color(c_yellow);
                if (focus == 1)
                {
                    draw_sprite(spr_heart, 0, ctabx[i] - 19, 125);
                }
            }
            draw_text(ctabx[i], 124, ctxt[i]);
        }
    }
    if (fn == 0)
    {
        draw_set_color(c_gray);
        draw_text(120, 150, "No fights available here yet.");
    }
}
draw_set_color(c_white);
if (page == 0)
{
    draw_text(120, 86, "LV " + string(global.ube_lv) + "   HP " + string(curhp) + "/" + string(maxhp) + "   AUTHENTIC MODE");
}
if (page == 2)
{
    var at = 8 + (global.ube_lv * 2);
    var df = 9 + ceil(global.ube_lv / 4);
    if (global.ube_lv == 20)
    {
        at = 30;
        df = 30;
    }
    draw_text(120, 260, "AT " + string(at - 10) + " (0)   DF " + string(df - 10) + " (0)");
    draw_set_color(c_gray);
    draw_text(120, 300, "WEAPON  Stick     (fixed in this build)");
    draw_text(120, 332, "ARMOR   Bandage   (fixed in this build)");
    draw_text(120, 364, "ITEMS   empty     (fixed in this build)");
}
if (page == 3)
{
    draw_text(120, 120, global.ube_enc_name[global.ube_last]);
    if (res_win == 1)
    {
        if (res_kills > 0)
        {
            draw_text(120, 156, "You won by fighting.");
        }
        else
        {
            draw_text(120, 156, "The battle ended without a kill.");
        }
        draw_text(120, 192, "EXP +" + string(res_xp) + "   GOLD +" + string(res_gold));
        draw_text(120, 228, "HP left " + string(res_hp) + " / " + string(res_maxhp));
    }
    else
    {
        draw_text(120, 156, "Your HP reached 0.");
    }
}
draw_set_color(c_gray);
if (page == 5)
{
    draw_text(120, 220, "Applies to menus and to moving your SOUL in battle.");
    draw_text(120, 252, "Z, X and C keep their usual jobs.");
    draw_text(40, 420, "[LEFT/RIGHT] Change  [Z] Select  [X] Back");
}
else if (page == 2)
{
    draw_text(40, 420, "[LEFT/RIGHT] Change  [Z] Select  [X] Back");
}
else if (page == 1)
{
    draw_text(40, 420, "[UP/DOWN] Tabs and fights  [LEFT/RIGHT] Switch tab  [Z] Select  [X] Back");
}
else
{
    draw_text(40, 420, "[Z/ENTER] Select  [X/SHIFT] Back  [F4] Fullscreen");
}
draw_set_color(c_white);
