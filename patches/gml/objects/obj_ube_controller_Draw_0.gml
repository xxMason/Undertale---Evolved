draw_set_alpha(1);
draw_set_color(c_black);
draw_rectangle(0, 0, 640, 480, false);
// page 4 = returning from a battle; ptimer 0 = the frame a page was switched, before
// Step has laid that page out.
if (page == 4 || ptimer == 0)
{
    exit;
}
scr_setfont(fnt_maintext);

var i;
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
var wname = scr_gettext("item_name_" + string(global.ube_weapon));
var aname = scr_gettext("item_name_" + string(global.ube_armor));

// ---- Title
if (page == 0)
{
    var lw = sprite_get_width(spr_undertaletitle) * logo_s;
    draw_sprite_ext(spr_undertaletitle, 0, (320 - (lw / 2)) + (sprite_get_xoffset(spr_undertaletitle) * logo_s), -76 + (sprite_get_yoffset(spr_undertaletitle) * logo_s), logo_s, logo_s, 0, c_white, 1);
    var sub = "ULTIMATE BATTLE ENGINE";
    draw_set_color(c_white);
    draw_text_transformed(320 - string_width(sub), 142, sub, 2, 2, 0);
}
else
{
    var title = "FIGHT SELECT";
    draw_set_color(c_white);
    if (page == 2)
    {
        title = "PLAYER SETUP";
    }
    if (page == 6)
    {
        title = "ITEMS";
    }
    if (page == 5)
    {
        title = "SETTINGS";
    }
    if (page == 7)
    {
        title = "TRAINING MODE";
    }
    if (page == 3)
    {
        title = "DEFEAT";
        draw_set_color(c_red);
        if (res_win == 1)
        {
            title = "BATTLE COMPLETE";
            draw_set_color(c_yellow);
        }
    }
    draw_text_transformed(320 - (string_width(title) * 1.5), 26, title, 3, 3, 0);
}

// ---- Box around the rows, in the style of the battle box
var nvis = min(row_n, vis);
var bx1 = row_x - 64;
var bx2 = 640 - bx1;
var by1 = row_y0 - 16;
var by2 = row_y0 + (nvis * row_h) + 4;
if (page == 2)
{
    by2 += 50;
}
if (page == 5)
{
    by2 += 76;
}
if (page == 7)
{
    by2 += 56;
}
if (page == 3)
{
    bx1 = 60;
    bx2 = 580;
    by1 = 96;
}
draw_set_color(c_white);
draw_rectangle(bx1, by1, bx2, by2, false);
draw_set_color(c_black);
draw_rectangle(bx1 + 5, by1 + 5, bx2 - 5, by2 - 5, false);

// ---- Rows
var label;
var val;
var ry;
var sc;
var w;
var maxw;
for (i = 0; i < row_n; i += 1)
{
    if (i < scroll || i >= scroll + vis)
    {
        continue;
    }
    label = "";
    val = "";
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
                label += " (unavailable)";
            }
            if (global.ube_enc_enabled[flist[i]] == 2)
            {
                label += " *";
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
            label = "LOVE";
            val = "< " + string(global.ube_lv) + " >";
        }
        if (i == 1)
        {
            label = "HP";
            val = "< " + string(curhp) + " / " + string(maxhp) + " >";
        }
        if (i == 2)
        {
            label = "WEAPON";
            val = "< " + wname + " >";
        }
        if (i == 3)
        {
            label = "ARMOR";
            val = "< " + aname + " >";
        }
        if (i == 4)
        {
            var cnt = 0;
            var q;
            for (q = 0; q < 8; q += 1)
            {
                if (global.ube_item[q] > 0)
                {
                    cnt += 1;
                }
            }
            label = "ITEMS";
            val = string(cnt) + " / 8";
        }
        if (i == 5)
        {
            label = "BACK";
        }
    }
    if (page == 6)
    {
        if (i < 8)
        {
            label = string(i + 1) + ".";
            val = "< (empty) >";
            if (global.ube_item[i] > 0)
            {
                val = "< " + scr_gettext("item_name_" + string(global.ube_item[i])) + " >";
            }
        }
        else
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
            label = "MOVEMENT";
            val = "< ARROW KEYS >";
            if (global.ube_wasd == 1)
            {
                val = "< WASD >";
            }
        }
        if (i == 1)
        {
            label = "BACK";
        }
    }
    if (page == 7)
    {
        var onoff = "< OFF >";
        if (i == 0)
        {
            label = "TRAINING MODE";
            if (global.ube_training == 1)
            {
                onoff = "< ON >";
            }
            val = onoff;
        }
        if (i == 1)
        {
            label = "INFINITE HP";
            if (global.ube_t_infhp == 1)
            {
                onoff = "< ON >";
            }
            val = onoff;
        }
        if (i == 2)
        {
            label = "GAME SPEED";
            val = "< " + string(global.ube_t_speed) + "% >";
        }
        if (i == 3)
        {
            label = "RETRY WITH [R]";
            if (global.ube_t_retry == 1)
            {
                onoff = "< ON >";
            }
            val = onoff;
        }
        if (i == 4)
        {
            label = "SHOW HITBOXES";
            if (global.ube_t_hitbox == 1)
            {
                onoff = "< ON >";
            }
            val = onoff;
        }
        if (i == 5)
        {
            label = "BACK";
        }
    }
    ry = row_y0 + ((i - scroll) * row_h);
    draw_set_color(c_white);
    if (row_on[i] == 0)
    {
        draw_set_color(c_gray);
    }
    else if (sel == i && (page != 1 || focus == 2))
    {
        draw_set_color(c_yellow);
        draw_sprite(spr_heart, 0, row_x - 34, ry + 6);
    }
    // Text is drawn at 2x like the original menus; over-long names shrink to fit.
    sc = 2;
    w = string_width(label) * 2;
    maxw = (bx2 - row_x) - 20;
    if (w > maxw)
    {
        sc = (2 * maxw) / w;
    }
    draw_text_transformed(row_x, ry + (2 - sc) * 6, label, sc, sc, 0);
    if (val != "")
    {
        var vx = row_x + 170;
        if (page == 6)
        {
            vx = row_x + 50;
        }
        if (page == 7)
        {
            vx = row_x + 250;
        }
        draw_text_transformed(vx, ry, val, 2, 2, 0);
    }
}
draw_set_color(c_gray);
if (scroll > 0)
{
    draw_text(bx2 - 104, by1 + 10, "(more above)");
}
if (row_n > scroll + vis)
{
    draw_text(bx2 - 104, by2 - 24, "(more below)");
}

// ---- Page extras
var hint = "[Z/ENTER] Select    [X/SHIFT] Back    [F4] Fullscreen";
var hint_y = 456;
if (page == 0)
{
    var summary = "LV " + string(global.ube_lv) + "    HP " + string(curhp) + "/" + string(maxhp) + "    " + wname + "    " + aname;
    if (global.ube_training == 1)
    {
        summary += "    TRAINING MODE";
    }
    else
    {
        summary += "    AUTHENTIC MODE";
    }
    draw_set_color(c_white);
    draw_text(320 - (string_width(summary) / 2), by2 + 4, summary);
    hint_y = 462;
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
                draw_rectangle(tabx[i], 114, tabx[i] + tabw[i], 115, false);
            }
        }
        draw_text(tabx[i], 96, "[" + global.ube_area_name[i] + "]");
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
                    draw_rectangle(ctabx[i], 148, ctabx[i] + ctabw[i], 149, false);
                }
            }
            draw_text(ctabx[i], 130, ctxt[i]);
        }
    }
    draw_set_color(c_gray);
    if (fn == 0)
    {
        draw_text(row_x, by2 + 10, "No fights available here yet.");
    }
    draw_text(40, 420, "* starts and runs, but its ending has not been verified");
    hint = "[UP/DOWN] Tabs and fights    [LEFT/RIGHT] Switch tab    [Z] Select    [X] Back";
}
if (page == 2)
{
    // Preview only. The numbers match scr_weaponeq / scr_armoreq, which are what the
    // battle actually uses.
    var ws = 0;
    var ad = 0;
    if (global.ube_weapon == 13) ws = 3;
    if (global.ube_weapon == 14) ws = 5;
    if (global.ube_weapon == 25) ws = 7;
    if (global.ube_weapon == 45) ws = 2;
    if (global.ube_weapon == 47) ws = 10;
    if (global.ube_weapon == 49) ws = 12;
    if (global.ube_weapon == 51) ws = 15;
    if (global.ube_weapon == 52) ws = 99;
    if (global.ube_armor == 12) ad = 3;
    if (global.ube_armor == 15) ad = 7;
    if (global.ube_armor == 24) ad = 10;
    if (global.ube_armor == 44) ad = 5;
    if (global.ube_armor == 46) ad = 11;
    if (global.ube_armor == 48)
    {
        ad = 12;
        ws += 5;
    }
    if (global.ube_armor == 50) ad = 15;
    if (global.ube_armor == 53) ad = 99;
    if (global.ube_armor == 64)
    {
        ad = 20;
        ws += 10;
    }
    var at = 8 + (global.ube_lv * 2);
    var df = 9 + ceil(global.ube_lv / 4);
    if (global.ube_lv == 20)
    {
        at = 30;
        df = 30;
    }
    draw_set_color(c_white);
    draw_text_transformed(row_x, by2 - 44, "AT " + string(at - 10) + " (" + string(ws) + ")     DF " + string(df - 10) + " (" + string(ad) + ")", 2, 2, 0);
    hint = "[LEFT/RIGHT] Change    [Z] Select    [X] Back";
}
if (page == 7)
{
    draw_set_color(c_gray);
    if (global.ube_training == 1)
    {
        draw_text(row_x, by2 - 46, "Fights run on the original code with these helpers added.");
        draw_text(row_x, by2 - 26, "Hits and damage taken are counted and shown after the fight.");
    }
    else
    {
        draw_text(row_x, by2 - 46, "OFF = Authentic Mode: fights run exactly as in the original,");
        draw_text(row_x, by2 - 26, "and none of the options above are active.");
    }
    hint = "[LEFT/RIGHT] or [Z] Change    [X] Back";
}
if (page == 6)
{
    hint = "[LEFT/RIGHT] Change item    [C] Empty the slot    [X] Back";
}
if (page == 5)
{
    draw_set_color(c_gray);
    draw_text(row_x, by2 - 62, "Applies to menus and to moving your SOUL in battle.");
    draw_text(row_x, by2 - 38, "Z, X and C keep their usual jobs.");
    hint = "[LEFT/RIGHT] Change    [Z] Select    [X] Back";
}
if (page == 3)
{
    draw_set_color(c_white);
    draw_text_transformed(96, 116, "* " + global.ube_enc_name[global.ube_last], 2, 2, 0);
    if (res_win == 1)
    {
        if (res_story == 1)
        {
            draw_text_transformed(96, 152, "* The fight is over.", 2, 2, 0);
        }
        else if (res_kills > 0)
        {
            draw_text_transformed(96, 152, "* YOU WON!", 2, 2, 0);
        }
        else
        {
            draw_text_transformed(96, 152, "* The battle ended peacefully.", 2, 2, 0);
        }
        draw_text_transformed(96, 188, "* You earned " + string(res_xp) + " XP and " + string(res_gold) + " gold.", 2, 2, 0);
        draw_text_transformed(96, 224, "* HP left: " + string(res_hp) + " / " + string(res_maxhp), 2, 2, 0);
    }
    else
    {
        draw_text_transformed(96, 152, "* Your HP reached 0.", 2, 2, 0);
        draw_text_transformed(96, 188, "* Stay determined...", 2, 2, 0);
    }
    if (res_training == 1)
    {
        draw_set_color(c_yellow);
        if (res_hits == 0 && res_win == 1)
        {
            draw_text_transformed(96, 260, "* NO HIT!", 2, 2, 0);
        }
        else
        {
            draw_text_transformed(96, 260, "* Hit " + string(res_hits) + " times, " + string(res_dmg) + " HP lost.", 2, 2, 0);
        }
        draw_set_color(c_white);
    }
}
draw_set_color(c_gray);
draw_text(320 - (string_width(hint) / 2), hint_y, hint);
draw_set_color(c_white);
