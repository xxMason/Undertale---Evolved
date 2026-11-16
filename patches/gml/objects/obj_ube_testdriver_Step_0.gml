// Presses keys through the same simulated-key mechanism the original game uses for
// joypads, so the battle itself runs completely unmodified.
if (room != last_room)
{
    if (room == room_battle)
    {
        battles += 1;
    }
    mt = 0;
    seq_i = 0;
    last_room = room;
}
if (room == room_battle || room == room_gameover)
{
    t += 1;
    if (room == room_battle && t == 90 && shot == 0)
    {
        shot = 1;
        screen_save("ube_shot_battle.png");
    }
    if (global.ube_test == "gear" && room == room_battle)
    {
        // Report what the original battle code ended up with, then use the first item
        // through the real ITEM menu (right twice, confirm twice).
        if (t == 30)
        {
            ube_log("GEAR weapon=" + string(global.weapon) + " wstr=" + string(global.wstrength) + " armor=" + string(global.armor) + " adef=" + string(global.adef) + " item0=" + string(global.item[0]) + " item1=" + string(global.item[1]) + " item2=" + string(global.item[2]) + " hp=" + string(global.hp));
        }
        if (t == 180 || t == 195)
        {
            keyboard_key_press(vk_right);
        }
        if (t == 184 || t == 199)
        {
            keyboard_key_release(vk_right);
        }
        if (t > 220 && gear_done == 0 && global.item[0] != 11)
        {
            gear_done = 1;
            ube_log("GEAR used hp=" + string(global.hp) + "/" + string(global.maxhp) + " item0=" + string(global.item[0]));
        }
        if (gear_done >= 1)
        {
            gear_done += 1;
        }
        if (gear_done == 30 || t > 1500)
        {
            keyboard_key_release(ord("Z"));
            global.ube_result = 3;
            caster_free(all);
            room_goto(room_ube_menu);
        }
    }
    if ((t mod 8) == 0 && (global.ube_test != "gear" || t >= 220))
    {
        keyboard_key_press(ord("Z"));
    }
    if ((t mod 8) == 4)
    {
        keyboard_key_release(ord("Z"));
    }
}
else
{
    if (t > 0)
    {
        keyboard_key_release(ord("Z"));
    }
    t = 0;
}
// Scenario "ui": walk the real menus with key presses.
// 37 left, 38 up, 39 right, 40 down, 90 Z, 88 X.
if (global.ube_test == "wasd" && room == room_battle)
{
    // Hold W for a moment and report what the original input code sees.
    if (t == 40)
    {
        keyboard_key_press(87);
    }
    if (t == 46)
    {
        ube_log("WASDCHK battle timeup=" + string(obj_time.up));
        keyboard_key_release(87);
    }
}
if ((global.ube_test == "ui" || global.ube_test == "wasd") && room == room_ube_menu)
{
    var seq;
    var n;
    if (battles == 0 && global.ube_test == "wasd")
    {
        // W in arrow mode (must do nothing), up twice to SETTINGS, toggle to WASD, back,
        // then S twice (SETTINGS -> EXIT -> FIGHT SELECT) and start Froggit.
        // 87 W, 83 S.
        seq[0] = 87;
        seq[1] = 38;
        seq[2] = 38;
        seq[3] = 90;
        seq[4] = 39;
        seq[5] = 88;
        seq[6] = 83;
        seq[7] = 83;
        seq[8] = 90;
        seq[9] = 90;
        n = 10;
    }
    else if (battles == 0)
    {
        // PLAYER SETUP: LOVE 1 -> 5, starting HP 36 -> 33, back, FIGHT SELECT, Froggit.
        seq[0] = 40;
        seq[1] = 90;
        seq[2] = 39;
        seq[3] = 39;
        seq[4] = 39;
        seq[5] = 39;
        seq[6] = 40;
        seq[7] = 37;
        seq[8] = 37;
        seq[9] = 37;
        seq[10] = 88;
        seq[11] = 38;
        seq[12] = 90;
        // Fight Select tabs: up to Monsters/Bosses, Bosses and back, up to the areas,
        // SNOWDIN and back to RUINS, down twice to the list, start Froggit.
        seq[13] = 38;
        seq[14] = 39;
        seq[15] = 37;
        seq[16] = 38;
        seq[17] = 39;
        seq[18] = 37;
        seq[19] = 40;
        seq[20] = 40;
        seq[21] = 90;
        n = 22;
    }
    else
    {
        // Results: MAIN MENU, then EXIT.
        seq[0] = 40;
        seq[1] = 40;
        seq[2] = 90;
        seq[3] = 38;
        seq[4] = 90;
        n = 5;
    }
    // The runner ignores simulated keys for the first few seconds after start-up, so
    // probe with an unused key (Q) until one registers before starting the sequence.
    if (ready == 0)
    {
        probe += 1;
        if ((probe mod 10) == 1)
        {
            keyboard_key_press(81);
        }
        if ((probe mod 10) == 4)
        {
            if (keyboard_check(81))
            {
                ready = 1;
            }
            keyboard_key_release(81);
        }
    }
    else
    {
        mt += 1;
    }
    if (mt >= 30 && seq_i < n)
    {
        var ph = (mt - 30) mod 10;
        if (ph == 0)
        {
            if (global.ube_test == "wasd" && battles == 0)
            {
                if (seq_i == 1)
                {
                    ube_log("WASDCHK off sel=" + string(obj_ube_controller.sel));
                }
                if (seq_i == 4)
                {
                    screen_save("ube_shot_settings.png");
                }
                if (seq_i == 8)
                {
                    ube_log("WASDCHK on sel=" + string(obj_ube_controller.sel));
                }
            }
            if (seq_i == 2 && battles == 0 && global.ube_test == "ui")
            {
                screen_save("ube_shot_setup.png");
            }
            if (battles == 0 && global.ube_test == "ui" && (seq_i == 13 || seq_i == 15 || seq_i == 18))
            {
                screen_save("ube_shot_fights" + string(seq_i) + ".png");
                ube_log("TABS area=" + string(global.ube_tab_area) + " cat=" + string(global.ube_tab_cat) + " focus=" + string(obj_ube_controller.focus) + " rows=" + string(obj_ube_controller.fn));
            }
            keyboard_key_press(seq[seq_i]);
        }
        if (ph == 4)
        {
            keyboard_key_release(seq[seq_i]);
            seq_i += 1;
        }
    }
}
// Scenario "keys": does a simulated arrow key reach keyboard_check_direct / obj_time?
if (global.ube_test == "keys" && room == room_ube_menu)
{
    if (ready == 0)
    {
        probe += 1;
        if ((probe mod 10) == 1)
        {
            keyboard_key_press(81);
        }
        if ((probe mod 10) == 4)
        {
            if (keyboard_check(81))
            {
                ready = 1;
            }
            keyboard_key_release(81);
        }
    }
    else
    {
        mt += 1;
        if (mt == 5)
        {
            keyboard_key_press(vk_up);
        }
        if (mt == 9)
        {
            ube_log("KEYS check=" + string(keyboard_check(vk_up)) + " direct=" + string(keyboard_check_direct(vk_up)) + " timeup=" + string(obj_time.up));
            keyboard_key_release(vk_up);
        }
        if (mt == 14)
        {
            ube_log("EXIT test=keys");
            game_end();
        }
    }
}
// Scenario "sweep": run fast, record the real monster names, and abort anything that
// overruns or leaves the battle for a story room.
if (global.ube_test == "sweep")
{
    var abort = 0;
    if (room == room_battle || room == room_gameover)
    {
        room_speed = 150;
        esc = 0;
        if (room == room_battle && t == 45)
        {
            var s = "";
            var m;
            for (m = 0; m < 3; m += 1)
            {
                if (global.monster[m] == 1)
                {
                    s += global.monstername[m] + ";";
                }
            }
            ube_log("SWEEP names i=" + string(global.ube_sweep_i) + " |" + s);
        }
        if (t > 2700)
        {
            ube_log("SWEEP timeout i=" + string(global.ube_sweep_i));
            abort = 1;
        }
    }
    else if (room != room_ube_menu)
    {
        esc += 1;
        if (esc > 10)
        {
            ube_log("SWEEP escaped i=" + string(global.ube_sweep_i) + " room=" + room_get_name(room));
            abort = 1;
        }
    }
    if (abort == 1)
    {
        esc = 0;
        t = 0;
        keyboard_key_release(ord("Z"));
        global.ube_result = 3;
        caster_free(all);
        with (obj_gameover)
        {
            instance_destroy();
        }
        room_goto(room_ube_menu);
    }
}
total += 1;
if (total > 5400 && global.ube_test != "sweep")
{
    screen_save("ube_shot_timeout.png");
    ube_log("TEST TIMEOUT room=" + string(room));
    game_end();
}
