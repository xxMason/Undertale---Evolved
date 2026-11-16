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
        res_story = 0;
        if (global.ube_result == 4)
        {
            // The story guard caught the fight leaving for a story scene.
            res_story = 1;
            ube_log("STATE STORY_EXIT");
        }
        if (global.ube_result == 3)
        {
            // Only the sweep test aborts a battle.
            res_win = 0;
            ube_log("STATE ABORTED");
        }
        res_kills = global.kills;
        res_xp = global.xp - global.ube_xp0;
        res_gold = global.gold;
        res_hp = global.hp;
        res_maxhp = global.maxhp;
        caster_free(all);
        global.ube_mus_on = 0;
        global.inbattle = 0;
        global.border = 0;
        global.ube_state = 4;
        if (res_win == 0)
        {
            global.ube_state = 5;
            ube_log("STATE DEFEAT hp=" + string(res_hp));
        }
        else if (res_story == 0)
        {
            ube_log("STATE VICTORY kills=" + string(res_kills) + " xp=" + string(res_xp) + " gold=" + string(res_gold) + " hp=" + string(res_hp) + "/" + string(res_maxhp));
        }
        res_training = global.ube_training;
        res_hits = global.ube_t_hits;
        res_dmg = global.ube_t_dmg;
        if (res_training == 1)
        {
            ube_log("TRAIN hits=" + string(res_hits) + " dmg=" + string(res_dmg) + " lethal=" + string(global.ube_t_lethal));
            if (global.ube_t_lethal > 0 && res_win == 1)
            {
                ube_log("TRAIN survived_lethal_hit");
            }
        }
        global.ube_state = 6;
        page = 3;
        sel = 0;
        ptimer = 0;
    }
    exit;
}

// ---- Menu music: "Home", the track obj_housemusic plays in Toriel's house.
if (global.ube_mus_on == 0)
{
    global.ube_mus = caster_load("music/house1.ogg");
    caster_loop(global.ube_mus, 0.8, 1);
    global.ube_mus_on = 1;
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
vis = 99;
if (page != 1)
{
    scroll = 0;
}
if (page == 0)
{
    row_x = 214;
    row_y0 = 196;
    row_h = 34;
    row_n = menu_n;
    for (i = 0; i < row_n; i += 1)
    {
        row_on[i] = menu_on[i];
    }
}
if (page == 1)
{
    row_x = 96;
    row_y0 = 180;
    row_h = 34;
    vis = 6;
    // Fights in the current area tab and Monsters/Bosses tab, then BACK.
    fn = 0;
    for (i = 0; i < global.ube_enc_count; i += 1)
    {
        if (global.ube_enc_areaidx[i] == global.ube_tab_area && global.ube_enc_cat[i] == global.ube_tab_cat)
        {
            flist[fn] = i;
            row_on[fn] = (global.ube_enc_enabled[i] > 0);
            fn += 1;
        }
    }
    row_on[fn] = 1;
    row_n = fn + 1;
    // Tab positions (shared with Draw and the mouse).
    scr_setfont(fnt_maintext);
    var tx = 32;
    for (i = 0; i < global.ube_area_count; i += 1)
    {
        tabx[i] = tx;
        tabw[i] = string_width("[" + global.ube_area_name[i] + "]");
        tx += tabw[i] + 12;
    }
    ctxt[0] = "[MONSTERS]";
    ctxt[1] = "[BOSSES]";
    tx = 32;
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
    row_x = 96;
    row_y0 = 112;
    row_h = 38;
    row_n = 6;
    for (i = 0; i < row_n; i += 1)
    {
        row_on[i] = 1;
    }
}
if (page == 6)
{
    row_x = 96;
    row_y0 = 104;
    row_h = 34;
    row_n = 9;
    for (i = 0; i < row_n; i += 1)
    {
        row_on[i] = 1;
    }
}
if (page == 3)
{
    row_x = 214;
    row_y0 = 304;
    row_h = 36;
    row_n = 3;
    row_on[0] = 1;
    row_on[1] = 1;
    row_on[2] = 1;
}
if (page == 7)
{
    // Training Mode: the modifier rows are only selectable while the mode is on.
    row_x = 96;
    row_y0 = 112;
    row_h = 38;
    row_n = 6;
    row_on[0] = 1;
    for (i = 1; i < 5; i += 1)
    {
        row_on[i] = global.ube_training;
    }
    row_on[5] = 1;
}
if (page == 5)
{
    row_x = 96;
    row_y0 = 130;
    row_h = 40;
    row_n = 2;
    row_on[0] = 1;
    row_on[1] = 1;
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
    mrow = floor((mouse_y - row_y0) / row_h) + scroll;
    if (mrow >= row_n || (mrow - scroll) >= vis)
    {
        mrow = -1;
    }
}
if (global.ube_test != "")
{
    // Self-tests must not be disturbed by wherever the real mouse pointer happens to be.
    mrow = -1;
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
    if (mouse_check_button_pressed(mb_left) && ptimer >= 4 && global.ube_test == "")
    {
        if (mouse_y >= 94 && mouse_y < 116)
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
        if (mouse_y >= 128 && mouse_y < 150)
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

// ---- Keep the selected row inside the visible window (long fight lists scroll)
if (sel < scroll)
{
    scroll = sel;
}
if (sel >= scroll + vis)
{
    scroll = (sel - vis) + 1;
}

// ---- Sweep test: start every catalogue entry in turn, enabled or not.
if (global.ube_test == "sweep")
{
    if ((page == 0 || page == 3) && ptimer == 5)
    {
        if (page == 3)
        {
            global.ube_sweep_i += 1;
        }
        // Power sweep: only entries not yet verified, with Real Knife, The Locket and
        // infinite HP, so bosses can actually be fought to their endings.
        if (global.ube_sweep_power == 1)
        {
            while (global.ube_sweep_i < global.ube_enc_count && global.ube_enc_enabled[global.ube_sweep_i] == 1)
            {
                global.ube_sweep_i += 1;
            }
            global.ube_weapon = 52;
            global.ube_armor = 53;
            global.ube_training = 1;
            global.ube_t_infhp = 1;
            global.ube_t_speed = 500;
            global.ube_t_retry = 0;
            global.ube_t_hitbox = 0;
        }
        if (global.ube_sweep_i >= global.ube_enc_count)
        {
            ube_log("SWEEP done");
            game_end();
            exit;
        }
        global.ube_lv = 20;
        global.ube_hp = 0;
        ube_log("SWEEP start i=" + string(global.ube_sweep_i) + " id=" + global.ube_enc_id[global.ube_sweep_i]);
        ube_start_encounter(global.ube_sweep_i);
    }
    exit;
}

// ---- Automated self-test hooks (only when the launcher wrote [Test] Scenario)
if (global.ube_test == "keys")
{
    exit;
}
if (global.ube_test != "" && global.ube_test != "ui" && global.ube_test != "wasd")
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
                // Show the ITEMS page with sample contents for a screenshot (not saved).
                global.ube_item[0] = 11;
                global.ube_item[2] = 43;
                global.ube_training = 1;
                page = 7;
                sel = 2;
                ptimer = 0;
                exit;
            }
            global.ube_lv = 20;
            global.ube_hp = 0;
            if (global.ube_test == "train")
            {
                // Training Mode at 1 HP: every hit would be lethal without infinite HP.
                global.ube_lv = 1;
                global.ube_hp = 1;
                global.ube_training = 1;
                global.ube_t_infhp = 1;
                global.ube_t_speed = 200;
                global.ube_t_retry = 1;
                global.ube_t_hitbox = 1;
            }
            if (global.ube_test == "gear")
            {
                // Real Knife, The Locket, Butterscotch Pie in slot 2 (slot 1 left empty
                // on purpose to check that the inventory is packed).
                global.ube_lv = 1;
                global.ube_hp = 5;
                global.ube_weapon = 52;
                global.ube_armor = 53;
                global.ube_item[0] = 0;
                global.ube_item[1] = 11;
                global.ube_item[2] = 1;
            }
            if (global.ube_test == "lose" || global.ube_test == "lose_then_win")
            {
                global.ube_lv = 1;
                global.ube_hp = 1;
            }
            ube_start_encounter(0);
            exit;
        }
    }
    if (page == 7)
    {
        if (ptimer == 20)
        {
            screen_save("ube_shot_training.png");
        }
        if (ptimer == 30)
        {
            page = 6;
            sel = 2;
            ptimer = 0;
            exit;
        }
    }
    if (page == 6)
    {
        if (ptimer == 20)
        {
            screen_save("ube_shot_items.png");
        }
        if (ptimer == 30)
        {
            ube_log("EXIT test=menu");
            game_end();
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
        else if (sel == 2)
        {
            page = 7;
            sel = 0;
            ptimer = 0;
        }
        else if (sel == 5)
        {
            page = 5;
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

if (page == 5)
{
    if (sel == 0 && (k_left || k_right || k_ok))
    {
        // MOVEMENT: 0 = arrow keys, 1 = WASD (applied by obj_ube_input).
        global.ube_wasd = 1 - global.ube_wasd;
        snd_play(snd_select);
        ube_save_config();
        ube_log("SETTINGS movement=" + string(global.ube_wasd));
        exit;
    }
    if (k_back || (k_ok && sel == 1))
    {
        snd_play(snd_select);
        page = 0;
        sel = 5;
        ptimer = 0;
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
    if (d != 0 && (sel == 2 || sel == 3))
    {
        // WEAPON / ARMOR: step through the original equipment lists.
        var li;
        var pos = 0;
        if (sel == 2)
        {
            for (li = 0; li < global.ube_wn; li += 1)
            {
                if (global.ube_wlist[li] == global.ube_weapon)
                {
                    pos = li;
                }
            }
            pos = ((pos + d) + global.ube_wn) mod global.ube_wn;
            global.ube_weapon = global.ube_wlist[pos];
        }
        else
        {
            for (li = 0; li < global.ube_an; li += 1)
            {
                if (global.ube_alist[li] == global.ube_armor)
                {
                    pos = li;
                }
            }
            pos = ((pos + d) + global.ube_an) mod global.ube_an;
            global.ube_armor = global.ube_alist[pos];
        }
        snd_play(snd_squeak);
    }
    if (k_ok && sel == 4)
    {
        snd_play(snd_select);
        page = 6;
        sel = 0;
        ptimer = 0;
        exit;
    }
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
    if (k_back || (k_ok && sel == 5))
    {
        snd_play(snd_select);
        ube_save_config();
        ube_log("CONFIG lv=" + string(global.ube_lv) + " hp=" + string(global.ube_hp) + " weapon=" + string(global.ube_weapon) + " armor=" + string(global.ube_armor));
        global.ube_state = 0;
        page = 0;
        sel = 1;
        ptimer = 0;
    }
    exit;
}

if (page == 7)
{
    var td = k_right - k_left;
    var toggle = (td != 0 || k_ok);
    if (sel == 0 && toggle)
    {
        global.ube_training = 1 - global.ube_training;
        snd_play(snd_select);
    }
    else if (sel == 1 && toggle)
    {
        global.ube_t_infhp = 1 - global.ube_t_infhp;
        snd_play(snd_squeak);
    }
    else if (sel == 2 && toggle)
    {
        var si;
        var sp = 2;
        for (si = 0; si < 6; si += 1)
        {
            if (global.ube_t_speedlist[si] == global.ube_t_speed)
            {
                sp = si;
            }
        }
        if (td == 0)
        {
            td = 1;
        }
        sp = ((sp + td) + 6) mod 6;
        global.ube_t_speed = global.ube_t_speedlist[sp];
        snd_play(snd_squeak);
    }
    else if (sel == 3 && toggle)
    {
        global.ube_t_retry = 1 - global.ube_t_retry;
        snd_play(snd_squeak);
    }
    else if (sel == 4 && toggle)
    {
        global.ube_t_hitbox = 1 - global.ube_t_hitbox;
        snd_play(snd_squeak);
    }
    else if (k_back || (k_ok && sel == 5))
    {
        snd_play(snd_select);
        ube_save_config();
        ube_log("TRAINING enabled=" + string(global.ube_training) + " infhp=" + string(global.ube_t_infhp) + " speed=" + string(global.ube_t_speed) + " retry=" + string(global.ube_t_retry) + " hitbox=" + string(global.ube_t_hitbox));
        page = 0;
        sel = 2;
        ptimer = 0;
    }
    exit;
}

if (page == 6)
{
    // ITEMS: eight slots; left/right steps through item IDs 0 (empty) to 64.
    if (sel < 8)
    {
        var di = k_right - k_left;
        if (di != 0)
        {
            global.ube_item[sel] = ((global.ube_item[sel] + di) + (global.ube_item_max + 1)) mod (global.ube_item_max + 1);
            snd_play(snd_squeak);
        }
        if (keyboard_check_pressed(ord("C")) || keyboard_check_pressed(vk_control))
        {
            global.ube_item[sel] = 0;
            snd_play(snd_squeak);
        }
    }
    if (k_back || (k_ok && sel == 8))
    {
        snd_play(snd_select);
        ube_save_config();
        page = 2;
        sel = 4;
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
