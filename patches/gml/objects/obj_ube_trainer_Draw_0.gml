if (room != room_battle)
{
    exit;
}
draw_set_alpha(1);
if (global.ube_t_hitbox == 1)
{
    // Bounding boxes of everything that has a collision event with the SOUL (generated
    // list), and of the SOUL itself. Bounding boxes, not pixel-precise masks.
    draw_set_color(c_red);
    ube_draw_hitboxes();
    draw_set_color(c_lime);
    with (obj_heart)
    {
        draw_rectangle(bbox_left, bbox_top, bbox_right, bbox_bottom, true);
    }
}
scr_setfont(fnt_maintext);
draw_set_color(c_gray);
var s = "TRAINING   SPEED " + string(global.ube_t_speed) + "%   HITS " + string(hits) + "   HP LOST " + string(dmg);
if (global.ube_t_infhp == 1)
{
    s += "   INF HP";
}
if (global.ube_t_retry == 1)
{
    s += "   [R] RETRY";
}
draw_text(6, 2, s);
draw_set_color(c_white);
