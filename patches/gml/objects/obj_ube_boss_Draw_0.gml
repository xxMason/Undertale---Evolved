draw_self();
// Attack lab read-out.
if (global.ube_lab >= 0 && global.ube_cb_atk_n > 0)
{
    var lk = min(global.ube_lab, global.ube_cb_atk_n - 1);
    var bl = global.ube_cb_at_sprite[lk];
    if (string_copy(bl, 1, 4) == "spr_")
    {
        bl = string_copy(bl, 5, string_length(bl) - 4);
    }
    draw_set_alpha(1);
    scr_setfont(fnt_maintext);
    draw_set_color(c_yellow);
    draw_text(8, 6, "ATTACK LAB - attack " + string(lk + 1));
    if (global.ube_cb_at_pat[lk] == "timeline")
    {
        // Built on the live-build screen: nothing to tune here, just play it.
        draw_set_color(c_white);
        draw_text(8, 24, string(global.ube_cb_at_objn[lk]) + " objects, looping");
        draw_set_color(c_gray);
        draw_text(8, 46, "Hits taken: " + string(lab_hits));
        draw_text(8, 62, "You cannot die here.");
        draw_set_color(c_yellow);
        draw_text(8, 84, "[BACKSPACE] Back to the builder");
        draw_set_color(c_white);
        exit;
    }
    draw_set_color(c_white);
    draw_text(8, 24, "[1]     Pattern   " + global.ube_cb_at_pat[lk]);
    draw_text(8, 40, "[2] [3] Count     " + string(global.ube_cb_at_count[lk]));
    draw_text(8, 56, "[4] [5] Speed     " + string(global.ube_cb_at_speed[lk]));
    draw_text(8, 72, "[6] [7] Interval  " + string(global.ube_cb_at_interval[lk]));
    draw_text(8, 88, "[8] [9] Damage    " + string(global.ube_cb_at_dmg[lk]));
    draw_text(8, 104, "[0]     Bullet    " + bl);
    draw_set_color(c_gray);
    draw_text(8, 126, "Hits taken: " + string(lab_hits));
    draw_text(8, 142, "You cannot die here.");
    draw_set_color(c_yellow);
    draw_text(8, 164, "[BACKSPACE] Keep and return");
    draw_set_color(c_white);
}
