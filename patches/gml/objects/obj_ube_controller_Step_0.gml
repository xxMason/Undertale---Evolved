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
    row_y0 = 120;
    row_h = 36;
    row_n = global.ube_enc_count + 1;
    for (i = 0; i < global.ube_enc_count; i += 1)
    {
        row_on[i] = global.ube_enc_enabled[i];
    }
    row_on[global.ube_enc_count] = 1;
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
    if (k_back || (k_ok && sel == global.ube_enc_count))
    {
        snd_play(snd_select);
        page = 0;
        sel = 0;
        ptimer = 0;
        exit;
    }
    if (k_ok && row_on[sel] == 1)
    {
        snd_play(snd_select);
        ube_start_encounter(sel);
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
