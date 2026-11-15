window_set_caption("UNDERTALE - Ultimate Battle Engine");
ptimer += 1;

// ---- RETURNING_TO_MENU: wait for the original game-over object to finish, then clean up.
if (page == 4)
{
    if (ptimer >= 3 && !instance_exists(obj_gameover))
    {
        res_win = 1;
        if (global.ube_result == 2)
        {
            res_win = 0;
        }
        res_kills = global.kills;
        res_xp = global.xp - global.ube_xp0;
        res_gold = global.gold;
        res_hp = global.hp;
        res_maxhp = global.maxhp;
        caster_free(all);
        global.inbattle = 0;
        global.border = 0;
        global.ube_state = 4;
        if (res_win == 0)
        {
            global.ube_state = 5;
            ube_log("STATE DEFEAT hp=" + string(res_hp));
        }
        else
        {
            ube_log("STATE VICTORY kills=" + string(res_kills) + " xp=" + string(res_xp) + " gold=" + string(res_gold) + " hp=" + string(res_hp) + "/" + string(res_maxhp));
        }
        global.ube_state = 6;
        page = 3;
        sel = 0;
        ptimer = 0;
    }
    exit;
}

// ---- Input
var k_up = keyboard_check_pressed(vk_up);
var k_down = keyboard_check_pressed(vk_down);
var k_left = keyboard_check_pressed(vk_left);
var k_right = keyboard_check_pressed(vk_right);
var k_ok = control_check_pressed(0);
var k_back = control_check_pressed(1);
if (ptimer < 4)
{
    k_ok = 0;
    k_back = 0;
}
if (keyboard_check(vk_left) || keyboard_check(vk_right))
{
    hold += 1;
}
else
{
    hold = 0;
}
if (hold > 15 && (hold mod 2) == 0)
{
    if (keyboard_check(vk_left))
    {
        k_left = 1;
    }
    if (keyboard_check(vk_right))
    {
        k_right = 1;
    }
}

// ---- Row layout for the current page (shared by mouse handling and Draw)
var i;
row_x = 120;
if (page == 0)
{
    row_y0 = 120;
    row_h = 40;
    row_n = menu_n;
    for (i = 0; i < row_n; i += 1)
    {
        row_on[i] = menu_on[i];
    }
}
if (page == 1)
{
    row_y0 = 176;
    row_h = 32;
    // Fights in the current area tab and Monsters/Bosses tab, then BACK.
    fn = 0;
    for (i = 0; i < global.ube_enc_count; i += 1)
    {
        if (global.ube_enc_areaidx[i] == global.ube_tab_area && global.ube_enc_cat[i] == global.ube_tab_cat)
        {
            flist[fn] = i;
            row_on[fn] = global.ube_enc_enabled[i];
            fn += 1;
        }
    }
    row_on[fn] = 1;
    row_n = fn + 1;
    // Tab positions (shared with Draw and the mouse).
    scr_setfont(fnt_maintext);
    var tx = 48;
    for (i = 0; i < global.ube_area_count; i += 1)
    {
        tabx[i] = tx;
        tabw[i] = string_width("[" + global.ube_area_name[i] + "]");
        tx += tabw[i] + 24;
    }
    ctxt[0] = "[MONSTERS]";
    ctxt[1] = "[BOSSES]";
    tx = 48;
    for (i = 0; i < 2; i += 1)
    {
        ctabx[i] = -1;
        ctabw[i] = 0;
        if (global.ube_area_has[(global.ube_tab_area * 2) + i] == 1)
        {
            ctabx[i] = tx;
            ctabw[i] = string_width(ctxt[i]);
            tx += ctabw[i] + 24;
        }
    }
}
if (page == 2)
{
    row_y0 = 120;
    row_h = 40;
    row_n = 3;
    row_on[0] = 1;
    row_on[1] = 1;
    row_on[2] = 1;
}
if (page == 3)
{
    row_y0 = 300;
    row_h = 40;
    row_n = 3;
    row_on[0] = 1;
    row_on[1] = 1;
    row_on[2] = 1;
}
if (sel >= row_n)
{
    sel = 0;
}

// ---- Mouse
var m_moved = (mouse_x != mx_prev || mouse_y != my_prev);
mx_prev = mouse_x;
my_prev = mouse_y;
var mrow = -1;
if (mouse_x >= 60 && mouse_x <= 580 && mouse_y >= row_y0)
{
    mrow = floor((mouse_y - row_y0) / row_h);
    if (mrow >= row_n)
    {
        mrow = -1;
    }
}
if (mrow >= 0)
{
    if (row_on[mrow] == 1)
    {
        if (m_moved && sel != mrow)
        {
            sel = mrow;
            snd_play(snd_squeak);
        }
        if (mouse_check_button_pressed(mb_left) && ptimer >= 4)
        {
            sel = mrow;
            k_ok = 1;
        }
    }
}

// ---- Fight Select tabs
if (page == 1)
{
    var new_area = global.ube_tab_area;
    var new_cat = global.ube_tab_cat;
    var other_cat = 1 - global.ube_tab_cat;
    var has_other = (global.ube_area_has[(global.ube_tab_area * 2) + other_cat] == 1);
    if (mrow >= 0)
    {
        if (row_on[mrow] == 1 && (m_moved || k_ok))
        {
            focus = 2;
        }
    }
    if (mouse_check_button_pressed(mb_left) && ptimer >= 4)
    {
        if (mouse_y >= 84 && mouse_y < 106)
        {
            for (i = 0; i < global.ube_area_count; i += 1)
            {
                if (mouse_x >= tabx[i] && mouse_x < tabx[i] + tabw[i])
                {
                    new_area = i;
                    focus = 0;
                }
            }
        }
        if (mouse_y >= 120 && mouse_y < 142)
        {
            for (i = 0; i < 2; i += 1)
            {
                if (ctabx[i] >= 0 && mouse_x >= ctabx[i] && mouse_x < ctabx[i] + ctabw[i])
                {
                    new_cat = i;
                    focus = 1;
                }
            }
        }
    }
    if (focus == 0)
    {
        if (k_right)
        {
            new_area = (global.ube_tab_area + 1) mod global.ube_area_count;
        }
        if (k_left)
        {
            new_area = ((global.ube_tab_area - 1) + global.ube_area_count) mod global.ube_area_count;
        }
        if (k_down)
        {
            focus = 1;
            snd_play(snd_squeak);
        }
        k_up = 0;
        k_down = 0;
    }
    else if (focus == 1)
    {
        if ((k_left || k_right) && has_other)
        {
            new_cat = other_cat;
        }
        if (k_up)
        {
            focus = 0;
            snd_play(snd_squeak);
        }
        if (k_down)
        {
            focus = 2;
            sel = 0;
            snd_play(snd_squeak);
        }
        k_up = 0;
        k_down = 0;
    }
    else
    {
        // Leaving the top of the list moves up to the tabs.
        var first = 0;
        while (row_on[first] == 0)
        {
            first += 1;
        }
        if (k_up && sel == first)
        {
            focus = 1;
            k_up = 0;
            snd_play(snd_squeak);
        }
    }
    if (new_area != global.ube_tab_area)
    {
        global.ube_tab_area = new_area;
        new_cat = 0;
        if (global.ube_area_has[new_area * 2] == 0)
        {
            new_cat = 1;
        }
        global.ube_tab_cat = new_cat;
        sel = 0;
        snd_play(snd_squeak);
        exit;
    }
    if (new_cat != global.ube_tab_cat)
    {
        global.ube_tab_cat = new_cat;
        sel = 0;
        snd_play(snd_squeak);
        exit;
    }
    while (row_on[sel] == 0)
    {
        sel += 1;
    }
}

// ---- Keyboard navigation (skips disabled rows)
if (k_down)
{
    do
    {
        sel = (sel + 1) mod row_n;
    }
    until (row_on[sel] == 1);
    snd_play(snd_squeak);
}
if (k_up)
{
    do
    {
        sel = ((sel - 1) + row_n) mod row_n;
    }
    until (row_on[sel] == 1);
    snd_play(snd_squeak);
}

// ---- Automated self-test hooks (only when the launcher wrote [Test] Scenario)
if (global.ube_test != "" && global.ube_test != "ui")
{
    k_ok = 0;
    k_back = 0;
    if (page == 0)
    {
        if (ptimer == 20)
        {
            screen_save("ube_shot_menu.png");
        }
        if (ptimer == 40)
        {
            if (global.ube_test == "menu")
            {
                ube_log("EXIT test=menu");
                game_end();
                exit;
            }
            global.ube_lv = 20;
            global.ube_hp = 0;
            if (global.ube_test == "lose" || global.ube_test == "lose_then_win")
            {
                global.ube_lv = 1;
                global.ube_hp = 1;
            }
            ube_start_encounter(0);
            exit;
        }
    }
    if (page == 3)
    {
        if (ptimer == 20)
        {
            screen_save("ube_shot_result" + string(global.ube_test_runs) + ".png");
        }
        if (ptimer == 40)
        {
            global.ube_test_runs += 1;
            if (global.ube_test == "lose_then_win" && global.ube_test_runs == 1)
            {
                global.ube_lv = 20;
                global.ube_hp = 0;
                ube_log("RETRY");
                ube_start_encounter(global.ube_last);
                exit;
            }
            ube_log("EXIT test=" + global.ube_test);
            game_end();
            exit;
        }
    }
    exit;
}

// ---- Page logic
if (page == 0)
{
    if (k_ok && menu_on[sel] == 1)
    {
        snd_play(snd_select);
        if (sel == 0)
        {
            page = 1;
            focus = 2;
            sel = 0;
            ptimer = 0;
        }
        else if (sel == 1)
        {
            global.ube_state = 1;
            page = 2;
            sel = 0;
            ptimer = 0;
        }
        else if (sel == 6)
        {
            ube_log("EXIT");
            game_end();
        }
    }
    exit;
}

if (page == 1)
{
    if (k_back || (k_ok && focus == 2 && sel == fn))
    {
        snd_play(snd_select);
        page = 0;
        sel = 0;
        ptimer = 0;
        exit;
    }
    if (k_ok && focus < 2)
    {
        // Confirming on a tab row moves down towards the list.
        snd_play(snd_select);
        focus += 1;
        sel = 0;
        exit;
    }
    if (k_ok && row_on[sel] == 1)
    {
        snd_play(snd_select);
        ube_start_encounter(flist[sel]);
    }
    exit;
}

if (page == 2)
{
    var maxhp = 16 + (global.ube_lv * 4);
    if (global.ube_lv == 20)
    {
        maxhp = 99;
    }
    var d = k_right - k_left;
    if (d != 0)
    {
        if (sel == 0)
        {
            var nl = clamp(global.ube_lv + d, 1, 20);
            if (nl != global.ube_lv)
            {
                global.ube_lv = nl;
                global.ube_hp = 0;
                snd_play(snd_squeak);
            }
        }
        if (sel == 1)
        {
            var cur = global.ube_hp;
            if (cur < 1 || cur > maxhp)
            {
                cur = maxhp;
            }
            var nh = clamp(cur + d, 1, maxhp);
            if (nh != cur)
            {
                snd_play(snd_squeak);
            }
            if (nh == maxhp)
            {
                nh = 0;
            }
            global.ube_hp = nh;
        }
    }
    if (k_back || (k_ok && sel == 2))
    {
        snd_play(snd_select);
        ini_open("ube_config.ini");
        ini_write_real("Player", "LOVE", global.ube_lv);
        ini_write_real("Player", "HP", global.ube_hp);
        ini_close();
        ube_log("CONFIG lv=" + string(global.ube_lv) + " hp=" + string(global.ube_hp));
        global.ube_state = 0;
        page = 0;
        sel = 1;
        ptimer = 0;
    }
    exit;
}

if (page == 3)
{
    if (k_ok)
    {
        snd_play(snd_select);
        if (sel == 0)
        {
            ube_log("RETRY");
            ube_start_encounter(global.ube_last);
            exit;
        }
        global.ube_state = 0;
        if (sel == 1)
        {
            page = 1;
            focus = 2;
        }
        else
        {
            page = 0;
        }
        sel = 0;
        ptimer = 0;
    }
    exit;
}
