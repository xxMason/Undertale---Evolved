t += 1;
if (t == 2)
{
    window_center();
}

// ---- Mouse (room coordinates; the view is 1:1)
mx = mouse_x;
my = mouse_y;
mclick = mouse_check_button_pressed(mb_left);
var mdn = mouse_check_button(mb_left);

// ---- Self-tests feed their own pointer instead of the real mouse.
if (global.ube_test == "bigwin")
{
    if (t == 12)
    {
        ube_log("BIGWIN window=" + string(window_get_width()) + "x" + string(window_get_height()) + " surface=" + string(surface_get_width(application_surface)) + "x" + string(surface_get_height(application_surface)) + " room=" + string(room_width) + "x" + string(room_height));
        surface_save(application_surface, "ube_shot_big_surface.png");
    }
    if (t == 20)
    {
        ube_live_leave();
        room_goto(room_ube_menu);
    }
    exit;
}
if (global.ube_test == "live")
{
    mclick = 0;
    mdn = 0;
    var bcy = 385 - (boxh / 2);
    var tk = -1;
    if (t >= 20 && ((t - 20) mod 8) == 0)
    {
        tk = (t - 20) div 8;
    }
    if (global.ube_live_visits == 1)
    {
        // Arm the first palette entry, place it; arm the second, place it; open EDIT;
        // raise ANGLE twice; TEST IT.
        if (tk == 0) { mx = PX + 90; my = 188; mclick = 1; }
        if (tk == 1) { mx = (SX + 320) - 40; my = (SY + bcy) - 20; mclick = 1; }
        if (tk == 2) { mx = PX + 280; my = 188; mclick = 1; }
        if (tk == 3) { mx = (SX + 320) + 40; my = (SY + bcy) + 10; mclick = 1; }
        if (tk == 4) { mx = PR - 60; my = 80; mclick = 1; }
        if (tk == 5 || tk == 6) { mx = PR - 16; my = 290; mclick = 1; }
        if (tk == 7) { mx = 780; my = 873; mclick = 1; }
        if (t == 50)
        {
            surface_save(application_surface, "ube_shot_live1.png");
        }
        if (t == 74)
        {
            surface_save(application_surface, "ube_shot_live2.png");
        }
    }
    else
    {
        // Back from the test fight: DONE.
        if (tk == 1) { mx = PR - 60; my = 28; mclick = 1; }
    }
    if (tk < 0)
    {
        mx = -100;
        my = -100;
    }
}
if (mdn)
{
    mhold += 1;
}
else
{
    mhold = 0;
}
mdown = mdn;

// ---- Preview clock
if (playing == 1)
{
    if (slow == 1)
    {
        T += 0.125;
    }
    else
    {
        T += 0.5;
    }
    if (T >= dur)
    {
        T = 0;
    }
}

// ---- Box geometry in battle coordinates (same rule as obj_ube_boss)
var bl = 320 - round(boxw / 2);
var bt = 385 - boxh;
var cxb = 320;
var cyb = 385 - (boxh / 2);
var i;

// ---- Stage: select, drag, rotate, or place the armed object
var in_stage = (mx >= SX && mx < SX + 640 && my >= SY && my < SY + 480);
if (mclick == 1 && in_stage)
{
    var hit = -1;
    var hit_mode = 0;
    for (i = 0; i < on; i += 1)
    {
        var px = SX + cxb + o_x[i];
        var py = SY + cyb + o_y[i];
        var hx = px + lengthdir_x(30, o_ang[i]);
        var hy = py + lengthdir_y(30, o_ang[i]);
        if (i == sel && o_aim[i] == 0 && point_distance(mx, my, hx, hy) <= 9)
        {
            hit = i;
            hit_mode = 2;
        }
        else if (point_distance(mx, my, px, py) <= 10 && hit_mode != 2)
        {
            hit = i;
            hit_mode = 1;
        }
    }
    if (hit >= 0)
    {
        ube_live_push();
        sel = hit;
        drag = hit_mode;
        tab = 2;
    }
    else if (armed != "" && on < 40)
    {
        ube_live_push();
        o_spr[on] = armed;
        o_time[on] = floor(T);
        o_x[on] = round((mx - SX) - cxb);
        o_y[on] = round((my - SY) - cyb);
        // Point it at the middle of the box to start with.
        o_ang[on] = (round(point_direction(o_x[on], o_y[on], 0, 0) / 5) * 5) mod 360;
        o_spd[on] = 3;
        o_aim[on] = 0;
        o_cnt[on] = 1;
        o_every[on] = 10;
        o_dmg[on] = max(1, ube_ed_get("Boss|ATK"));
        o_size[on] = 1;
        o_spin[on] = 0;
        o_face[on] = 0;
        sel = on;
        on += 1;
        ube_log("LIVE add n=" + string(on) + " spr=" + armed + " x=" + string(o_x[sel]) + " y=" + string(o_y[sel]) + " t=" + string(o_time[sel]));
    }
    else
    {
        sel = -1;
    }
    mclick = 0;
}
if (mdown == 0)
{
    drag = 0;
}
if (drag == 1 && sel >= 0)
{
    o_x[sel] = clamp(round((mx - SX) - cxb), -320, 320);
    o_y[sel] = clamp(round((my - SY) - cyb), -330, 150);
}
if (drag == 2 && sel >= 0)
{
    o_ang[sel] = (round(point_direction(SX + cxb + o_x[sel], SY + cyb + o_y[sel], mx, my) / 5) * 5) mod 360;
}

// ---- Timeline, all by mouse:
//   drag an object's bar (or its numbered box)  -> change when it starts
//   drag the last tick of a repeating object    -> change the gap between repeats
//   drag anywhere else (ruler or empty row)     -> move the playhead
//   click a row                                 -> select that object
//   mouse wheel                                 -> scroll the rows
var tm = ((mx - TLX) / TLW) * dur;
var in_tl = (mx >= TLX - 10 && mx <= TLX + TLW + 10 && my >= TLY - 34 && my < TLY + 186);
if (mclick == 1 && in_tl && drag == 0)
{
    drag = 5;
    if (my >= TLY)
    {
        var row = floor((my - TLY) / 26) + tscroll;
        if (row >= 0 && row < on)
        {
            var fx = TLX + ((o_time[row] / dur) * TLW);
            var lx = TLX + (((o_time[row] + ((o_cnt[row] - 1) * o_every[row])) / dur) * TLW);
            sel = row;
            tab = 2;
            if (o_cnt[row] > 1 && abs(mx - lx) <= 6 && abs(mx - fx) > 9)
            {
                ube_live_push();
                drag = 4;
            }
            else if (mx >= fx - 9 && mx <= max(lx, fx) + 9)
            {
                ube_live_push();
                drag = 3;
                drag_off = 0;
                if (abs(mx - fx) > 9)
                {
                    // Grabbed the bar: keep the same spot under the pointer.
                    drag_off = tm - o_time[row];
                }
            }
        }
    }
    mclick = 0;
}
if (drag == 3 && sel >= 0)
{
    o_time[sel] = clamp(round(tm - drag_off), 0, dur - 1);
}
if (drag == 4 && sel >= 0)
{
    o_every[sel] = clamp(round((tm - o_time[sel]) / (o_cnt[sel] - 1)), 1, 600);
}
if (drag == 5)
{
    T = clamp(tm, 0, dur - 1);
    playing = 0;
}
if (in_tl || (mx < PX - 12 && my >= TLY - 34))
{
    if (mouse_wheel_down())
    {
        tscroll += 1;
    }
    if (mouse_wheel_up())
    {
        tscroll = max(0, tscroll - 1);
    }
}
// ---- Keys
if (keyboard_check_pressed(vk_space))
{
    playing = 1 - playing;
}
if (sel >= 0)
{
    var nudge = 1;
    if (keyboard_check(vk_shift))
    {
        nudge = 10;
    }
    var kx = keyboard_check_pressed(vk_right) - keyboard_check_pressed(vk_left);
    var ky = keyboard_check_pressed(vk_down) - keyboard_check_pressed(vk_up);
    if (kx != 0 || ky != 0)
    {
        ube_live_push();
        o_x[sel] += kx * nudge;
        o_y[sel] += ky * nudge;
    }
    if (keyboard_check_pressed(vk_delete))
    {
        act = "delete";
    }
}

// ---- Actions queued by the buttons in Draw (and the Delete key)
if (act == "delete" && sel >= 0)
{
    ube_live_push();
    for (i = sel; i < on - 1; i += 1)
    {
        ube_live_parse(i, ube_live_line(i + 1));
    }
    on -= 1;
    sel = -1;
}
if (act == "copy" && sel >= 0 && on < 40)
{
    ube_live_push();
    ube_live_parse(on, ube_live_line(sel));
    o_x[on] += 16;
    o_y[on] += 16;
    sel = on;
    on += 1;
}
if (act == "undo" && un > 0)
{
    redo[rn] = ube_live_pack();
    rn += 1;
    un -= 1;
    ube_live_unpack(undo[un]);
}
if (act == "redo" && rn > 0)
{
    undo[un] = ube_live_pack();
    un += 1;
    rn -= 1;
    ube_live_unpack(redo[rn]);
}
if (act == "prev" || act == "next" || act == "new")
{
    // Move to another timeline attack of this boss (pattern attacks are skipped).
    ube_live_store();
    var target = -1;
    var k;
    if (act == "prev")
    {
        for (k = lidx - 1; k >= 1 && target < 0; k -= 1)
        {
            if (ube_ed_get("Attack" + string(k) + "|Pattern") == "timeline")
            {
                target = k;
            }
        }
    }
    if (act == "next")
    {
        for (k = lidx + 1; k <= 8 && target < 0; k += 1)
        {
            if (ube_ed_get("Attack" + string(k) + "|Pattern") == "timeline")
            {
                target = k;
            }
        }
    }
    if (act == "new")
    {
        for (k = 1; k <= 8 && target < 0; k += 1)
        {
            if (ube_ed_get("Attack" + string(k) + "|Pattern") == "")
            {
                target = k;
                var pre = "Attack" + string(k) + "|";
                ube_ed_set(pre + "Pattern", "timeline");
                ube_ed_set(pre + "Duration", 240);
                ube_ed_set(pre + "BoxW", 160);
                ube_ed_set(pre + "BoxH", 135);
                ube_ed_set(pre + "Objects", 0);
            }
        }
    }
    if (target >= 0)
    {
        lidx = target;
        global.ube_live_idx = target;
        ube_live_load();
    }
}
if (act == "test")
{
    // Play this attack in the real battle (the attack lab), then come back here.
    ube_live_store();
    global.ube_cbl_name[global.ube_ed_i] = ube_ed_get("Boss|Name");
    ube_index_write();
    global.ube_ed_pending = 2;
    global.ube_lab_pending = lidx - 1;
    global.ube_ed_rlive = 1;
    global.ube_ed_rpage = 4;
    global.ube_ed_ridx = lidx;
    global.ube_ed_rsel = 0;
    ube_live_leave();
    ube_start_encounter(1000 + global.ube_ed_i);
    exit;
}
if (act == "done")
{
    ube_live_store();
    global.ube_ed_reopen = 1;
    ube_live_leave();
    room_goto(room_ube_menu);
    exit;
}
act = "";
if (sel >= 0 && sel != prev_sel)
{
    // Bring a newly selected object's row into view.
    if (sel < tscroll)
    {
        tscroll = sel;
    }
    if (sel >= tscroll + 7)
    {
        tscroll = sel - 6;
    }
}
prev_sel = sel;
if (tscroll > max(0, on - 7))
{
    tscroll = max(0, on - 7);
}
