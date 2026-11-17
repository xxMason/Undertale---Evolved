// Presses keys through the same simulated-key mechanism the original game uses for
// joypads, so the battle itself runs completely unmodified.
if (room != last_room)
{
    if (last_room == room_battle && (global.ube_test == "custom" || global.ube_test == "custom_spare" || global.ube_test == "timeline"))
    {
        ube_log("CUSTOM bullets_seen=" + string(cb_seen > 0) + " max=" + string(cb_seen));
    }
    if (room == room_battle)
    {
        battles += 1;
    }
    mt = 0;
    seq_i = 0;
    last_room = room;
}
// Scenario "trace": wait in the menu until simulated keys are accepted (the runner ignores
// them for a while after start-up), let the controller start the fight, then play it with
// the same closed-loop policy as the Godot engine's auto-play. Keys set here are seen by
// the game from the next frame on; the Begin Step records what it actually saw.
if (global.ube_test == "trace")
{
    if (room == room_ube_menu && tr_f == 0)
    {
        if (kready == 0)
        {
            kp += 1;
            if ((kp mod 10) == 1)
            {
                keyboard_key_press(81);
            }
            if ((kp mod 10) == 4)
            {
                if (keyboard_check(81))
                {
                    kready = 1;
                    global.ube_trace_ready = 1;
                }
                keyboard_key_release(81);
            }
        }
        exit;
    }
    if (room == room_ube_menu && tr_f > 0 && tr_done == 0)
    {
        tr_done = 1;
        ube_log("TRACE done frames=" + string(tr_f) + " hp=" + string(global.hp) + " left=1");
        game_end();
        exit;
    }
    if (room == room_battle || room == room_gameover)
    {
        // Run as fast as the machine allows: no battle logic reads room_speed (it is only
        // set for slow-motion effects and debug keys), so every frame is the same.
        room_speed = 150;
        var pf = tr_f + 1;
        var want = 0;
        if (room == room_gameover)
        {
            if ((pf mod 6) < 2)
            {
                want = 16;
            }
        }
        else if (global.mnfight == 2)
        {
            if (((pf div 20) mod 2) == 0)
            {
                want += 1;
            }
            else
            {
                want += 2;
            }
            if ((pf mod 12) < 2)
            {
                want += 16;
            }
            if (((pf div 15) mod 4) == 1)
            {
                want += 4;
            }
        }
        else if ((pf mod 6) < 2)
        {
            want = 16;
        }
        var kc;
        kc[0] = vk_left;
        kc[1] = vk_right;
        kc[2] = vk_up;
        kc[3] = vk_down;
        kc[4] = ord("Z");
        kc[5] = ord("X");
        kc[6] = ord("C");
        var kb;
        for (kb = 0; kb < 7; kb += 1)
        {
            var bit = power(2, kb);
            if ((want & bit) != 0 && (tr_keys & bit) == 0)
            {
                keyboard_key_press(kc[kb]);
            }
            if ((want & bit) == 0 && (tr_keys & bit) != 0)
            {
                keyboard_key_release(kc[kb]);
            }
        }
        tr_keys = want;
    }
    total += 1;
    if (total > 9000)
    {
        ube_log("TEST TIMEOUT room=" + string(room));
        game_end();
    }
    exit;
}
if (room == room_battle || room == room_gameover)
{
    t += 1;
    if (room == room_battle && t == 90 && shot == 0)
    {
        shot = 1;
        screen_save("ube_shot_battle.png");
    }
    if ((global.ube_test == "train" || global.ube_test == "gear" || global.ube_test == "custom_spare" || global.ube_test == "editor" || global.ube_test == "live" || global.ube_test == "verify") && room == room_battle)
    {
        // The runner ignores simulated keys for a few seconds after start-up, and how
        // long varies. Probe with an unused key (Q); rt counts frames since keys work.
        if (kready == 0)
        {
            kp += 1;
            if ((kp mod 10) == 1)
            {
                keyboard_key_press(81);
            }
            if ((kp mod 10) == 4)
            {
                if (keyboard_check(81))
                {
                    kready = 1;
                }
                keyboard_key_release(81);
            }
        }
        else
        {
            rt += 1;
        }
    }
    if ((global.ube_test == "custom" || global.ube_test == "custom_spare" || global.ube_test == "editor" || global.ube_test == "timeline" || global.ube_test == "live") && room == room_battle)
    {
        if (instance_number(obj_ube_bullet) > cb_seen)
        {
            cb_seen = instance_number(obj_ube_bullet);
        }
        if (t == 150 || t == 320 || t == 520)
        {
            screen_save("ube_shot_custom" + string(t) + ".png");
        }
    }
    if (global.ube_test == "custom_spare" && room == room_battle && kready == 1)
    {
        // Closed loop through the real menus: ACT -> target -> first custom act until
        // enough mercy points, then MERCY -> Spare. Everything else is "confirm".
        // Screenshots of the target list and the ACT menu once each has settled.
        if (global.bmenuno == cs_menu)
        {
            cs_menu_t += 1;
        }
        else
        {
            cs_menu = global.bmenuno;
            cs_menu_t = 0;
        }
        if (cs_menu_t == 6 && cs_menu == 2 && cs_shot2 == 0)
        {
            cs_shot2 = 1;
            screen_save("ube_shot_custom_target.png");
        }
        if (cs_menu_t == 6 && cs_menu == 10 && cs_shot10 == 0)
        {
            cs_shot10 = 1;
            screen_save("ube_shot_custom_act.png");
        }
        cs_t += 1;
        var want = 90;
        var pts = 0;
        if (instance_exists(obj_ube_boss))
        {
            pts = obj_ube_boss.spare_points;
        }
        if (global.myfight == 0 && global.mnfight == 0)
        {
            if (pts < global.ube_cb_spare_need)
            {
                if (global.bmenuno == 0)
                {
                    if (global.bmenucoord[0] != 1)
                    {
                        want = vk_right;
                    }
                }
                else if (global.bmenuno == 10)
                {
                    if (global.bmenucoord[2] != 3)
                    {
                        want = vk_right;
                    }
                }
                else if (global.bmenuno != 2)
                {
                    want = 88;
                }
            }
            else if (global.bmenuno == 0)
            {
                if (global.bmenucoord[0] != 3)
                {
                    want = vk_right;
                }
            }
        }
        if ((cs_t mod 12) == 1)
        {
            cs_key = want;
            keyboard_key_press(cs_key);
        }
        if ((cs_t mod 12) == 6)
        {
            keyboard_key_release(cs_key);
        }
    }
    if (global.ube_test == "editor" && room == room_battle && kready == 1)
    {
        // Attack lab: report the state, raise Count with the [3] key, leave with Backspace.
        if (rt == 40)
        {
            ube_log("LAB1 count=" + string(global.ube_cb_at_count[0]) + " pat=" + global.ube_cb_at_pat[0] + " mnfight=" + string(global.mnfight));
            screen_save("ube_shot_lab.png");
        }
        if (rt == 60)
        {
            keyboard_key_press(ord("3"));
        }
        if (rt == 64)
        {
            keyboard_key_release(ord("3"));
        }
        if (rt == 80)
        {
            ube_log("LAB2 count=" + string(global.ube_cb_at_count[0]) + " bullets=" + string(cb_seen > 0));
        }
        if (rt == 100)
        {
            keyboard_key_press(vk_backspace);
        }
        if (rt == 104)
        {
            keyboard_key_release(vk_backspace);
        }
    }
    if (global.ube_test == "timeline" && room == room_battle)
    {
        // Report the box the timeline attack asked for, once it has settled.
        if (tl_logged == 0 && global.mnfight == 2 && obj_lborder.x == global.idealborder[0] && obj_uborder.y == global.idealborder[2])
        {
            tl_logged = 1;
            ube_log("TL box=" + string(global.idealborder[1] - global.idealborder[0]) + "x" + string(global.idealborder[3] - global.idealborder[2]) + " border=" + string(global.border));
        }
        if (tl_shot == 0 && instance_number(obj_ube_bullet) >= 4)
        {
            tl_shot = 1;
            screen_save("ube_shot_timeline.png");
        }
    }
    if (global.ube_test == "live" && room == room_battle && kready == 1)
    {
        // Test fight started from the live-build screen: report, then leave with Backspace.
        if (rt == 60)
        {
            ube_log("LIVE lab objects=" + string(global.ube_cb_at_objn[0]) + " bullets=" + string(cb_seen > 0) + " box=" + string(global.idealborder[1] - global.idealborder[0]) + "x" + string(global.idealborder[3] - global.idealborder[2]));
            screen_save("ube_shot_live_lab.png");
        }
        if (rt == 70)
        {
            keyboard_key_press(vk_backspace);
        }
        if (rt == 74)
        {
            keyboard_key_release(vk_backspace);
        }
    }
    if ((global.ube_test == "record" || global.ube_test == "record2") && room == room_battle)
    {
        // Start recording on the first frame of the monster's attack; from then on hold
        // keys from the script (frames:keys, keys = 1 L, 2 R, 4 U, 8 D, 16 X).
        if (rec_on == 0 && global.mnfight == 2)
        {
            rec_on = 1;
            rec_f = 0;
            keyboard_key_release(ord("Z"));
            var fh = file_text_open_write("ube_record.txt");
            file_text_write_string(fh, "BOX " + string(global.idealborder[0]) + ";" + string(global.idealborder[1]) + ";" + string(global.idealborder[2]) + ";" + string(global.idealborder[3]) + ";lv=" + string(global.lv) + ";df=" + string(global.df) + ";adef=" + string(global.adef) + ";inv=" + string(global.inv) + ";sp=" + string(global.sp));
            file_text_writeln(fh);
            file_text_close(fh);
        }
        if (rec_on == 1)
        {
            var seg = "15:0,25:2,10:4,10:8,20:1,15:17,25:5,40:8,20:6,10:3,12:9,8:24,20:4,10:0,";
            if (global.ube_test == "record2")
            {
                seg = "10:0,30:1,20:8,25:2,15:4,20:9,30:6,25:1,20:4,15:10,30:0,";
            }
            var acc = 0;
            var want = 0;
            while (string_length(seg) > 0)
            {
                var cp = string_pos(",", seg);
                var part = string_copy(seg, 1, cp - 1);
                seg = string_delete(seg, 1, cp);
                var colon = string_pos(":", part);
                acc += real(string_copy(part, 1, colon - 1));
                if (rec_f < acc)
                {
                    want = real(string_delete(part, 1, colon));
                    seg = "";
                }
            }
            var kc;
            kc[0] = vk_left;
            kc[1] = vk_right;
            kc[2] = vk_up;
            kc[3] = vk_down;
            kc[4] = ord("X");
            var kb;
            for (kb = 0; kb < 5; kb += 1)
            {
                var bit = power(2, kb);
                if ((want & bit) != 0 && (rec_keys & bit) == 0)
                {
                    keyboard_key_press(kc[kb]);
                }
                if ((want & bit) == 0 && (rec_keys & bit) != 0)
                {
                    keyboard_key_release(kc[kb]);
                }
            }
            rec_keys = want;
        }
    }
    if (global.ube_test == "verify" && room == room_battle)
    {
        // Let the timeline attack loop a few times in the lab, then report what the
        // bullets really did and leave.
        if (t == 300)
        {
            screen_save("ube_shot_verify.png");
        }
        if (t >= 620 && kready == 1 && v_done == 0)
        {
            v_done = 1;
            var avg = 0;
            if (global.ube_v_n > 0)
            {
                avg = global.ube_v_sum / global.ube_v_n;
            }
            var hits = 0;
            if (instance_exists(obj_ube_boss))
            {
                hits = obj_ube_boss.lab_hits;
            }
            ube_log("VERIFY spawned=" + string(global.ube_v_spawned) + " measured=" + string(global.ube_v_n) + " life_error_avg=" + string(avg) + " life_error_worst=" + string(global.ube_v_max) + " off_by_more_than_3=" + string(global.ube_v_bad) + " first_step_offset=" + string(global.ube_v_ofs) + " hits=" + string(hits) + " box=" + string(global.idealborder[1] - global.idealborder[0]) + "x" + string(global.idealborder[3] - global.idealborder[2]));
            keyboard_key_press(vk_backspace);
        }
        if (v_done >= 1)
        {
            v_done += 1;
            if (v_done == 6)
            {
                keyboard_key_release(vk_backspace);
            }
        }
    }
    if (global.ube_test == "train" && room == room_battle)
    {
        if (t == 20)
        {
            ube_log("TRAIN speed=" + string(room_speed) + " trainer=" + string(instance_exists(obj_ube_trainer)));
        }
        if (t == 200 || t == 280)
        {
            screen_save("ube_shot_train" + string(t) + ".png");
        }
        // Press R once, after simulated keys are known to work.
        if (rt == 60 && train_r == 0)
        {
            keyboard_key_press(82);
        }
        if (rt == 64 && train_r == 0)
        {
            keyboard_key_release(82);
            train_r = 1;
        }
    }
    if (global.ube_test == "gear" && room == room_battle)
    {
        // Report what the original battle code ended up with, then use the first item
        // through the real ITEM menu (right twice, confirm twice).
        if (t == 30)
        {
            ube_log("GEAR weapon=" + string(global.weapon) + " wstr=" + string(global.wstrength) + " armor=" + string(global.armor) + " adef=" + string(global.adef) + " item0=" + string(global.item[0]) + " item1=" + string(global.item[1]) + " item2=" + string(global.item[2]) + " hp=" + string(global.hp));
        }
        // Closed loop: keep tapping Right until the ITEM button (index 2) is selected,
        // then let the confirm presses below open the menu and use the first item.
        if (kready == 1 && gear_go == 0)
        {
            if (global.bmenuno == 0 && global.bmenucoord[0] == 2)
            {
                keyboard_key_release(vk_right);
                gear_go = 1;
            }
            else
            {
                if ((rt mod 12) == 1)
                {
                    keyboard_key_press(vk_right);
                }
                if ((rt mod 12) == 5)
                {
                    keyboard_key_release(vk_right);
                }
            }
        }
        if (gear_go == 1 && gear_done == 0 && global.item[0] != 11)
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
    if ((t mod 8) == 0 && !((global.ube_test == "record" || global.ube_test == "record2") && rec_on == 1) && (global.ube_test != "gear" || gear_go == 1) && ((global.ube_test != "custom_spare" && global.ube_test != "editor" && global.ube_test != "live" && global.ube_test != "verify") || room != room_battle))
    {
        keyboard_key_press(ord("Z"));
    }
    if ((t mod 8) == 4 && ((global.ube_test != "custom_spare" && global.ube_test != "editor" && global.ube_test != "live" && global.ube_test != "verify") || room != room_battle))
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
if ((global.ube_test == "ui" || global.ube_test == "wasd" || global.ube_test == "editor") && room == room_ube_menu)
{
    var seq;
    var n;
    if (global.ube_test == "editor")
    {
        // CUSTOM BATTLES -> NEW BOSS -> HP 100 to 130 -> ATTACKS -> attack 1 -> pattern
        // rain to aimed -> COUNT 2 to 4 -> TEST LIVE. Nothing is pressed after the lab.
        n = 0;
        if (battles == 0)
        {
            var codes = "40,40,40,90,38,38,90,40,39,39,39,38,38,38,38,38,90,90,39,40,39,39,38,38,38,38,90,";
            while (string_length(codes) > 0)
            {
                var cpos = string_pos(",", codes);
                seq[n] = real(string_copy(codes, 1, cpos - 1));
                codes = string_delete(codes, 1, cpos);
                n += 1;
            }
        }
    }
    else if (battles == 0 && global.ube_test == "wasd")
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
            if (global.ube_test == "editor" && battles == 0 && (seq_i == 6 || seq_i == 11 || seq_i == 17 || seq_i == 23))
            {
                screen_save("ube_shot_editor" + string(seq_i) + ".png");
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
        if (t > 2700 + (global.ube_sweep_power * 6300))
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
