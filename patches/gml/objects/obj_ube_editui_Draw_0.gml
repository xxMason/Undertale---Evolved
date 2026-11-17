draw_set_alpha(1);
draw_set_color(c_black);
draw_rectangle(0, 0, room_width, room_height, false);
scr_setfont(fnt_maintext);
if (global.ube_test == "bigwin")
{
    draw_set_color(c_white);
    draw_text(20, 20, "1280x960 editor screen");
    exit;
}

var i;
var k;
var bl = 320 - round(boxw / 2);
var br = 320 + round(boxw / 2);
var bt = 385 - boxh;
var bb = 385;
var cxb = 320;
var cyb = 385 - (boxh / 2);

// =====================================================================  STAGE
draw_set_color(make_color_rgb(110, 110, 110));
draw_rectangle(SX - 2, SY - 2, SX + 641, SY + 481, true);
// Boss, placed as in the fight.
var bw = sprite_get_width(bspr) * bscale;
var bh = sprite_get_height(bspr) * bscale;
draw_sprite_ext(bspr, 0, SX + round((320 - (bw / 2)) + (sprite_get_xoffset(bspr) * bscale)), SY + round((236 - bh) + (sprite_get_yoffset(bspr) * bscale)), bscale, bscale, 0, c_white, 1);
// Box (5 px white frame, as in battle).
draw_set_color(c_white);
draw_rectangle(SX + bl, SY + bt, SX + br, SY + bb, false);
draw_set_color(c_black);
draw_rectangle(SX + bl + 5, SY + bt + 5, SX + br - 5, SY + bb - 5, false);
// The SOUL waits in the middle; "aim at you" objects aim here in the preview.
draw_sprite(spr_heart, 0, (SX + cxb) - 8, (SY + cyb) - 8);

// Preview bullets at time T. Each firing flies in a straight line and disappears when
// it leaves the box through a wall it is moving towards (the rule blt_parent uses).
var shown = 0;
for (i = 0; i < on; i += 1)
{
    var spr = asset_get_index(o_spr[i]);
    if (spr < 0)
    {
        spr = spr_bulletmd;
    }
    var x0 = cxb + o_x[i];
    var y0 = cyb + o_y[i];
    var ang = o_ang[i];
    if (o_aim[i] == 1)
    {
        ang = point_direction(x0, y0, cxb, cyb);
    }
    var vx = lengthdir_x(o_spd[i], ang);
    var vy = lengthdir_y(o_spd[i], ang);
    var life = 100000;
    if (vx > 0.001 && x0 < br)
    {
        life = min(life, (br - x0) / vx);
    }
    if (vx < -0.001 && x0 > bl)
    {
        life = min(life, (bl - x0) / vx);
    }
    if (vy > 0.001 && y0 < bb)
    {
        life = min(life, (bb - y0) / vy);
    }
    if (vy < -0.001 && y0 > bt)
    {
        life = min(life, (bt - y0) / vy);
    }
    var r;
    for (r = 0; r < o_cnt[i]; r += 1)
    {
        var age = T - (o_time[i] + (r * o_every[i]));
        if (age >= 0 && age <= life && shown < 400)
        {
            var px = x0 + (vx * age);
            var py = y0 + (vy * age);
            if (px > -40 && px < 680 && py > -40 && py < 520)
            {
                var rot = o_spin[i] * age;
                if (o_face[i] == 1)
                {
                    rot += ang;
                }
                draw_sprite_ext(spr, 0, SX + px, SY + py, o_size[i], o_size[i], rot, c_white, 1);
                if (hitb == 1)
                {
                    var hw = sprite_get_width(spr) * o_size[i];
                    var hh = sprite_get_height(spr) * o_size[i];
                    var hx = (SX + px) - (sprite_get_xoffset(spr) * o_size[i]);
                    var hy = (SY + py) - (sprite_get_yoffset(spr) * o_size[i]);
                    draw_set_color(c_red);
                    draw_rectangle(hx, hy, hx + hw, hy + hh, true);
                }
                shown += 1;
            }
        }
    }
}
// Placement markers: a diamond where each object starts, a handle for its direction.
for (i = 0; i < on; i += 1)
{
    var mxp = SX + cxb + o_x[i];
    var myp = SY + cyb + o_y[i];
    var col = make_color_rgb(170, 170, 170);
    if (point_distance(mx, my, mxp, myp) <= 10 && drag == 0)
    {
        // Hovered: this is what a click would grab.
        col = c_white;
    }
    if (i == sel)
    {
        col = c_yellow;
    }
    draw_set_color(col);
    if (o_aim[i] == 0)
    {
        var ex = mxp + lengthdir_x(30, o_ang[i]);
        var ey = myp + lengthdir_y(30, o_ang[i]);
        draw_line_width(mxp, myp, ex, ey, 2);
        if (i == sel)
        {
            draw_rectangle(ex - 5, ey - 5, ex + 5, ey + 5, false);
        }
    }
    draw_triangle(mxp - 8, myp, mxp, myp - 8, mxp + 8, myp, false);
    draw_triangle(mxp - 8, myp, mxp, myp + 8, mxp + 8, myp, false);
    draw_set_color(c_black);
    draw_text(mxp - 3, myp - 7, string(i + 1));
}
if (armed != "")
{
    draw_set_color(c_yellow);
    draw_text(SX + 6, SY + 460, "Click in the stage to place: " + string_copy(armed, 5, string_length(armed) - 4));
}

// =====================================================================  TOP BAR
var tl_n = 0;
var tl_pos = 0;
for (k = 1; k <= 8; k += 1)
{
    if (ube_ed_get("Attack" + string(k) + "|Pattern") == "timeline")
    {
        tl_n += 1;
        if (k <= lidx)
        {
            tl_pos = tl_n;
        }
    }
}
var free_slot = 0;
for (k = 1; k <= 8; k += 1)
{
    if (ube_ed_get("Attack" + string(k) + "|Pattern") == "")
    {
        free_slot = 1;
    }
}
if (ube_ui_btn(10, 8, 54, 44, "<", 2 * (tl_pos <= 1)))
{
    act = "prev";
}
draw_set_color(c_white);
var ttl = ube_ed_get("Boss|Name") + "  -  ATTACK " + string(lidx);
draw_text_transformed(330 - string_width(ttl), 12, ttl, 2, 2, 0);
if (ube_ui_btn(606, 8, 650, 44, ">", 2 * (tl_pos >= tl_n)))
{
    act = "next";
}
if (ube_ui_btn(660, 8, 880, 44, "+ ATTACK", 1 + (1 - free_slot)))
{
    act = "new";
}
var d;
d = ube_ui_step(10, 52, 290, "BOX WIDTH", string(boxw));
if (d != 0)
{
    if (t - step_push_t > 20)
    {
        ube_live_push();
    }
    step_push_t = t;
    boxw = clamp(boxw + (d * 10), 60, 570);
}
d = ube_ui_step(300, 52, 580, "BOX HEIGHT", string(boxh));
if (d != 0)
{
    if (t - step_push_t > 20)
    {
        ube_live_push();
    }
    step_push_t = t;
    boxh = clamp(boxh + (d * 5), 40, 300);
}
d = ube_ui_step(590, 52, 880, "HOW LONG", string_format(dur / 30, 0, 1) + "s");
if (d != 0)
{
    if (t - step_push_t > 20)
    {
        ube_live_push();
    }
    step_push_t = t;
    dur = clamp(dur + (d * 15), 30, 900);
}

// =====================================================================  RIGHT PANEL
draw_set_color(c_white);
draw_rectangle(PX - 12, 0, PX - 10, 960, false);
draw_set_color(c_yellow);
draw_text_transformed(PX, 12, "LIVE BUILD", 2, 2, 0);
if (ube_ui_btn(PR - 120, 6, PR, 50, "DONE", 1))
{
    act = "done";
}
if (ube_ui_btn(PX, 60, PX + 120, 100, "+ ADD", 3 * (tab == 0)))
{
    tab = 0;
}
if (ube_ui_btn(PX + 124, 60, PX + 246, 100, "OBJECTS " + string(on), 3 * (tab == 1)))
{
    tab = 1;
}
if (ube_ui_btn(PX + 250, 60, PR, 100, "EDIT", 3 * (tab == 2)))
{
    tab = 2;
}

if (tab == 0)
{
    // Palette: the game's own bullet sprites, 16 per page.
    var total = ube_list_n(2);
    var pages = ceil(total / 16);
    if (ube_ui_btn(PX, 112, PX + 40, 150, "<", 0))
    {
        ppage = ((ppage - 1) + pages) mod pages;
    }
    if (ube_ui_btn(PR - 40, 112, PR, 150, ">", 0))
    {
        ppage = (ppage + 1) mod pages;
    }
    draw_set_color(c_gray);
    var pt = "BULLETS  page " + string(ppage + 1) + " / " + string(pages);
    draw_text(((PX + PR) / 2) - (string_width(pt) / 2), 124, pt);
    for (k = 0; k < 16; k += 1)
    {
        var li = (ppage * 16) + k;
        if (li < total)
        {
            var nm = ube_list_get(2, li);
            var bx1 = PX + ((k mod 2) * 188);
            var by1 = 160 + ((k div 2) * 56);
            var st = 0;
            if (armed == nm)
            {
                st = 3;
            }
            if (ube_ui_btn(bx1, by1, bx1 + 182, by1 + 50, "", st))
            {
                if (armed == nm)
                {
                    armed = "";
                }
                else
                {
                    armed = nm;
                }
            }
            // Thumbnail and name.
            var ps = asset_get_index(nm);
            if (ps >= 0)
            {
                var pw = sprite_get_width(ps);
                var ph = sprite_get_height(ps);
                var psc = min(1, 34 / max(pw, ph));
                draw_sprite_ext(ps, 0, ((bx1 + 26) - ((pw * psc) / 2)) + (sprite_get_xoffset(ps) * psc), ((by1 + 25) - ((ph * psc) / 2)) + (sprite_get_yoffset(ps) * psc), psc, psc, 0, c_white, 1);
            }
            draw_set_color(c_white);
            if (st == 3)
            {
                draw_set_color(c_yellow);
            }
            draw_text(bx1 + 50, by1 + 18, string_copy(nm, 5, 16));
        }
    }
    draw_set_color(c_gray);
    draw_text(PX, 614, "Pick one, then click in the stage.");
    draw_text(PX, 632, string(on) + " / 40 objects");
}
if (tab == 1)
{
    if (on == 0)
    {
        draw_set_color(c_gray);
        draw_text(PX, 120, "Nothing placed yet.");
    }
    for (i = 0; i < on && i < 17; i += 1)
    {
        var os = 0;
        if (i == sel)
        {
            os = 3;
        }
        if (ube_ui_btn(PX, 112 + (i * 30), PR, 112 + (i * 30) + 28, string(i + 1) + ".  " + string_copy(o_spr[i], 5, 14) + "   at " + string_format(o_time[i] / 30, 0, 1) + "s   x" + string(o_cnt[i]), os))
        {
            sel = i;
            tab = 2;
        }
    }
}
if (tab == 2)
{
    if (sel < 0)
    {
        draw_set_color(c_gray);
        draw_text(PX, 120, "Click an object in the stage or the timeline.");
    }
    else
    {
        draw_set_color(c_yellow);
        draw_text(PX, 124, string_copy(o_spr[sel], 5, 16) + "  (object " + string(sel + 1) + ")");
        if (ube_ui_btn(PX + 190, 112, PX + 275, 150, "COPY", 2 * (on >= 40)))
        {
            act = "copy";
        }
        if (ube_ui_btn(PX + 280, 112, PR, 150, "DELETE", 0))
        {
            act = "delete";
        }
        var onoff;
        var changed = 0;
        var before = ube_live_line(sel);
        d = ube_ui_step(PX, 160, PR, "START", string_format(o_time[sel] / 30, 0, 1) + "s");
        o_time[sel] = clamp(o_time[sel] + (d * 3), 0, dur - 1);
        d = ube_ui_step(PX, 198, PR, "X", string(o_x[sel]));
        o_x[sel] = clamp(o_x[sel] + d, -320, 320);
        d = ube_ui_step(PX, 236, PR, "Y", string(o_y[sel]));
        o_y[sel] = clamp(o_y[sel] + d, -330, 150);
        d = ube_ui_step(PX, 274, PR, "ANGLE", string(o_ang[sel]));
        o_ang[sel] = ((o_ang[sel] + (d * 5)) + 360) mod 360;
        onoff = "NO";
        if (o_aim[sel] == 1)
        {
            onoff = "YES";
        }
        d = ube_ui_step(PX, 312, PR, "AIM AT YOU", onoff);
        if (d != 0 && mhold <= 1)
        {
            o_aim[sel] = 1 - o_aim[sel];
        }
        d = ube_ui_step(PX, 350, PR, "SPEED", string(o_spd[sel]));
        o_spd[sel] = clamp(o_spd[sel] + (d * 0.5), 0, 20);
        d = ube_ui_step(PX, 388, PR, "REPEAT", string(o_cnt[sel]) + " times");
        o_cnt[sel] = clamp(o_cnt[sel] + d, 1, 60);
        d = ube_ui_step(PX, 426, PR, "EVERY", string_format(o_every[sel] / 30, 0, 1) + "s");
        o_every[sel] = clamp(o_every[sel] + (d * 3), 3, 600);
        d = ube_ui_step(PX, 464, PR, "DAMAGE", string(o_dmg[sel]));
        o_dmg[sel] = clamp(o_dmg[sel] + d, 1, 99);
        d = ube_ui_step(PX, 502, PR, "SIZE", string(o_size[sel]));
        o_size[sel] = clamp(o_size[sel] + (d * 0.25), 0.25, 8);
        d = ube_ui_step(PX, 540, PR, "SPIN", string(o_spin[sel]));
        o_spin[sel] = clamp(o_spin[sel] + d, -30, 30);
        onoff = "NO";
        if (o_face[sel] == 1)
        {
            onoff = "YES";
        }
        d = ube_ui_step(PX, 578, PR, "FACE ITS PATH", onoff);
        if (d != 0 && mhold <= 1)
        {
            o_face[sel] = 1 - o_face[sel];
        }
        if (ube_live_line(sel) != before)
        {
            // Something changed: remember the earlier state for UNDO (one step per burst).
            if (t - step_push_t > 20)
            {
                var after = ube_live_line(sel);
                ube_live_parse(sel, before);
                ube_live_push();
                ube_live_parse(sel, after);
            }
            step_push_t = t;
        }
    }
}
// Preview controls at the bottom of the panel.
if (ube_ui_btn(PX, 660, PX + 120, 700, "HITBOXES", 3 * hitb))
{
    hitb = 1 - hitb;
}
var ptxt = "PAUSE";
if (playing == 0)
{
    ptxt = "PLAY";
}
if (ube_ui_btn(PX + 124, 660, PX + 246, 700, ptxt, 0))
{
    playing = 1 - playing;
}
if (ube_ui_btn(PX + 250, 660, PR, 700, "SLOW", 3 * slow))
{
    slow = 1 - slow;
}
draw_set_color(c_gray);
draw_text(PX, 716, "This preview shows where bullets go.");
draw_text(PX, 734, "TEST IT plays the attack in a real fight.");
draw_text(PX, 770, "[SPACE] Play / pause");
draw_text(PX, 788, "[ARROWS] Nudge selected (SHIFT = 10)");
draw_text(PX, 806, "[DELETE] Remove selected");
draw_text(PX, 824, "Drag the diamond to move an object,");
draw_text(PX, 842, "drag its square handle to turn it.");

// =====================================================================  TIMELINE
draw_set_color(c_white);
draw_rectangle(0, 590, PX - 12, 592, false);
var secs = dur / 30;
draw_set_color(c_gray);
for (k = 0; k <= floor(secs * 2); k += 1)
{
    var rx = TLX + (((k * 15) / dur) * TLW);
    if ((k mod 2) == 0)
    {
        draw_line(rx, TLY - 14, rx, TLY - 2);
        draw_text(rx - 3, TLY - 30, string(k / 2));
    }
    else
    {
        draw_line(rx, TLY - 8, rx, TLY - 2);
    }
}
draw_set_color(c_red);
draw_line_width(TLX + TLW, TLY - 30, TLX + TLW, TLY + 186, 2);
draw_text(TLX + TLW - 30, TLY - 30, "END");
for (i = tscroll; i < on && i < tscroll + 7; i += 1)
{
    var ty = TLY + ((i - tscroll) * 26);
    draw_set_color(make_color_rgb(22, 22, 30));
    draw_rectangle(TLX, ty, TLX + TLW, ty + 22, false);
    draw_set_color(c_white);
    if (i == sel)
    {
        draw_set_color(c_yellow);
    }
    draw_text(8, ty + 4, string(i + 1) + ". " + string_copy(o_spr[i], 5, 13));
    // Line from the first to the last firing, a tick for each, a box on the first.
    var fx = TLX + ((o_time[i] / dur) * TLW);
    var lxx = TLX + (min(dur, o_time[i] + ((o_cnt[i] - 1) * o_every[i])) / dur) * TLW;
    draw_line_width(fx, ty + 11, lxx, ty + 11, 2);
    var rr;
    for (rr = 0; rr < o_cnt[i]; rr += 1)
    {
        var tx = TLX + (((o_time[i] + (rr * o_every[i])) / dur) * TLW);
        if (tx <= TLX + TLW)
        {
            draw_line(tx, ty + 4, tx, ty + 18);
        }
    }
    draw_rectangle(fx - 6, ty + 3, fx + 6, ty + 19, false);
    if (drag == 0 && my >= ty && my < ty + 26 && mx >= fx - 9 && mx <= max(lxx, fx) + 9)
    {
        // Hovered bar: show that it can be dragged.
        draw_set_color(c_white);
        draw_rectangle(fx - 8, ty + 1, max(lxx, fx) + 8, ty + 21, true);
    }
    if (o_cnt[i] > 1 && lxx <= TLX + TLW)
    {
        // Handle on the last firing: drag it to change the gap between repeats.
        draw_rectangle(lxx - 3, ty + 5, lxx + 3, ty + 17, false);
    }
    draw_set_color(c_black);
    draw_text(fx - 3, ty + 4, string(i + 1));
}
if (on > tscroll + 7)
{
    draw_set_color(c_gray);
    draw_text(8, TLY + 186, "(more below)");
}
// Playhead.
var phx = TLX + ((T / dur) * TLW);
draw_set_color(c_yellow);
draw_line_width(phx, TLY - 22, phx, TLY + 186, 2);
draw_rectangle(phx - 6, TLY - 28, phx + 6, TLY - 20, false);

// =====================================================================  BOTTOM BAR
if (ube_ui_btn(10, 850, 190, 896, "FROM START", 0))
{
    T = 0;
    playing = 1;
}
if (ube_ui_btn(200, 850, 320, 896, "UNDO", 2 * (un == 0)))
{
    act = "undo";
}
if (ube_ui_btn(330, 850, 450, 896, "REDO", 2 * (rn == 0)))
{
    act = "redo";
}
draw_set_color(c_white);
draw_text(470, 866, string_format(T / 30, 0, 1) + "s / " + string_format(secs, 0, 1) + "s");
if (ube_ui_btn(680, 850, 880, 896, "TEST IT", 1))
{
    act = "test";
}
draw_set_color(c_gray);
draw_text(10, 916, "Timeline: drag an object's bar to change when it starts, drag its end handle to change the gap, drag elsewhere to move the playhead.");
draw_text(10, 934, "Stage: pick a bullet on the right and click to place it. Drag a diamond to move it, drag its square handle to turn it.");
draw_set_color(c_white);
