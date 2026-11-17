// ube_coll_probe(): collision rounding probe. The real game runs it in the trace scenario and
// logs the result; the Godot engine runs this same file (engine.gd --collprobe) and the two
// lines must be identical. A carrot bullet (precise mask, cols 10-13, rows 12-22) is moved
// past the heart (precise, 16x16 at 100,100) in 1/8 px steps from all four sides, at scale 1
// and 2, and a few fractional bounding boxes are recorded.
var pa = instance_create(0, 0, obj_npc_marker);
var pb = instance_create(0, 0, obj_npc_marker);
pa.sprite_index = spr_carrotbullet;
pa.mask_index = spr_carrotbullet;
pa.image_speed = 0;
pa.image_index = 0;
pb.sprite_index = spr_heart;
pb.mask_index = spr_heart;
pb.image_speed = 0;
pb.image_index = 0;
pb.x = 100;
pb.y = 100;
var s = "COLL";
var q, d, hit, mode, sc;
for (q = 0; q < 8; q += 1)
{
    d = q * 0.25;
    pa.x = 50 + d;
    pa.y = 50 + d;
    s += " b" + string(pa.bbox_left) + "," + string(pa.bbox_right) + "," + string(pa.bbox_top) + "," + string(pa.bbox_bottom);
}
for (sc = 1; sc <= 2; sc += 1)
{
    pa.image_xscale = sc;
    pa.image_yscale = sc;
    for (mode = 0; mode < 4; mode += 1)
    {
        s += " s" + string(sc) + "m" + string(mode) + ":";
        for (q = 0; q < 32; q += 1)
        {
            d = q * 0.125;
            if (mode == 0)
            {
                // above, moving down: bottom edge (row 23 * scale) crosses y = 100
                pa.x = 92;
                pa.y = 98 - (23 * sc) + d;
            }
            if (mode == 1)
            {
                // below, moving up: top edge (row 12 * scale) crosses y = 116, under the tip
                pa.x = 108 - (12 * sc);
                pa.y = 117 - (12 * sc) - d;
            }
            if (mode == 2)
            {
                // left, moving right: right edge (col 14 * scale) crosses x = 100
                pa.x = 98 - (14 * sc) + d;
                pa.y = 108 - (17 * sc);
            }
            if (mode == 3)
            {
                // right, moving left: left edge (col 10 * scale) crosses x = 116
                pa.x = 118 - (10 * sc) - d;
                pa.y = 108 - (17 * sc);
            }
            with (pa)
            {
                hit = place_meeting(x, y, pb);
            }
            s += string(hit);
        }
    }
}
// Diagonal sweeps through the heart for scaled, mirrored and rotated carrots.
var cf;
for (cf = 0; cf < 7; cf += 1)
{
    pa.image_xscale = 1;
    pa.image_yscale = 1;
    pa.image_angle = 0;
    if (cf == 0) { pa.image_xscale = 1.5; pa.image_yscale = 1.5; }
    if (cf == 1) { pa.image_xscale = -1; }
    if (cf == 2) { pa.image_yscale = -1; }
    if (cf == 3) { pa.image_angle = 90; }
    if (cf == 4) { pa.image_angle = 45; }
    if (cf == 5) { pa.image_xscale = 2; pa.image_angle = 30; }
    if (cf == 6) { pa.image_xscale = -2; pa.image_yscale = 1.25; pa.image_angle = 200; }
    pa.x = 101.3;
    pa.y = 100.6;
    s += " c" + string(cf) + "b" + string(pa.bbox_left) + "," + string(pa.bbox_right) + "," + string(pa.bbox_top) + "," + string(pa.bbox_bottom) + ":";
    // pass the box centre through the heart centre (108, 108)
    var ox = floor((pa.bbox_left + pa.bbox_right) / 2 - 101);
    var oy = floor((pa.bbox_top + pa.bbox_bottom) / 2 - 100);
    for (q = 0; q < 96; q += 1)
    {
        pa.x = 90 - ox + (q * 0.375);
        pa.y = 89.7 - oy + (q * 0.375);
        with (pa)
        {
            hit = place_meeting(x, y, pb);
        }
        s += string(hit);
    }
}
// A one-pixel mask at an odd offset (spr_bulletsm: column 3, row 3) at quarter positions:
// bounding box, then sweeps across the heart's left and top edges.
pa.sprite_index = spr_bulletsm;
pa.mask_index = spr_bulletsm;
pa.image_xscale = 1;
pa.image_yscale = 1;
pa.image_angle = 0;
s += " p";
for (q = 0; q < 8; q += 1)
{
    pa.x = 50 + (q * 0.25);
    pa.y = 50 + (q * 0.25);
    s += string(pa.bbox_left) + "," + string(pa.bbox_right) + "," + string(pa.bbox_top) + "," + string(pa.bbox_bottom) + "/";
}
s += " px:";
for (q = 0; q < 32; q += 1)
{
    pa.x = 95 + (q * 0.125);
    pa.y = 102;
    with (pa)
    {
        hit = place_meeting(x, y, pb);
    }
    s += string(hit);
}
s += " py:";
for (q = 0; q < 32; q += 1)
{
    pa.x = 100;
    pa.y = 94 + (q * 0.125);
    with (pa)
    {
        hit = place_meeting(x, y, pb);
    }
    s += string(hit);
}
s += " pr:";
for (q = 0; q < 32; q += 1)
{
    pa.x = 114 - (q * 0.125);
    pa.y = 102;
    with (pa)
    {
        hit = place_meeting(x, y, pb);
    }
    s += string(hit);
}
s += " pb:";
for (q = 0; q < 32; q += 1)
{
    pa.x = 104;
    pa.y = 114 - (q * 0.125);
    with (pa)
    {
        hit = place_meeting(x, y, pb);
    }
    s += string(hit);
}
// Rotated rectangle masks (spr_crosszap: rectangle mask, cols 9-10, rows 4-15, origin 10,5):
// bounding box, then sweeps up into a box border (rectangle mask, 5x5 scaled to 310x5 at
// 162,220) and sideways into the heart, at angles where the mask's rotation direction shows.
pa.sprite_index = spr_crosszap;
pa.mask_index = spr_crosszap;
pb.sprite_index = spr_border;
pb.mask_index = spr_border;
pb.x = 162;
pb.y = 220;
pb.image_xscale = 62;
var ra;
for (cf = 0; cf < 6; cf += 1)
{
    ra = 81.2;
    if (cf == 1) { ra = 30; }
    if (cf == 2) { ra = 135; }
    if (cf == 3) { ra = 200; }
    if (cf == 4) { ra = 300; }
    if (cf == 5) { ra = 260; }
    pa.image_angle = ra;
    pa.x = 300.3;
    pa.y = 240.6;
    s += " r" + string(cf) + "b" + string(pa.bbox_left) + "," + string(pa.bbox_right) + "," + string(pa.bbox_top) + "," + string(pa.bbox_bottom) + ":";
    for (q = 0; q < 64; q += 1)
    {
        pa.y = 238.3 - (q * 0.25);
        with (pa)
        {
            hit = place_meeting(x, y, pb);
        }
        s += string(hit);
    }
}
pb.sprite_index = spr_heart;
pb.mask_index = spr_heart;
pb.x = 100;
pb.y = 100;
pb.image_xscale = 1;
for (cf = 0; cf < 6; cf += 1)
{
    ra = 81.2;
    if (cf == 1) { ra = 30; }
    if (cf == 2) { ra = 135; }
    if (cf == 3) { ra = 200; }
    if (cf == 4) { ra = 300; }
    if (cf == 5) { ra = 260; }
    pa.image_angle = ra;
    s += " h" + string(cf) + ":";
    for (q = 0; q < 64; q += 1)
    {
        pa.x = 80.1 + (q * 0.25);
        pa.y = 104.4;
        with (pa)
        {
            hit = place_meeting(x, y, pb);
        }
        s += string(hit);
    }
}
// Scaled rectangle masks (spr_sunbullet: rectangle mask, cols 5-6, rows 5-6, origin 0,0)
// against the heart: bounding box, then sweeps down onto its top edge and right onto its
// left edge, at scales 0.75, 1.6 and 2.5 (Knight Knight's growing sun bullets).
pa.sprite_index = spr_sunbullet;
pa.mask_index = spr_sunbullet;
pa.image_angle = 0;
for (cf = 0; cf < 3; cf += 1)
{
    sc = 0.75;
    if (cf == 1) { sc = 1.6; }
    if (cf == 2) { sc = 2.5; }
    pa.image_xscale = sc;
    pa.image_yscale = sc;
    pa.x = 107.218;
    pa.y = 95.031;
    s += " u" + string(cf) + "b" + string(pa.bbox_left) + "," + string(pa.bbox_right) + "," + string(pa.bbox_top) + "," + string(pa.bbox_bottom) + ":";
    for (q = 0; q < 48; q += 1)
    {
        pa.x = 107.218;
        pa.y = 100 - (8 * sc) + (q * 0.125);
        with (pa)
        {
            hit = place_meeting(x, y, pb);
        }
        s += string(hit);
    }
    s += "/";
    for (q = 0; q < 48; q += 1)
    {
        pa.x = 100 - (8 * sc) + (q * 0.125);
        pa.y = 104.031;
        with (pa)
        {
            hit = place_meeting(x, y, pb);
        }
        s += string(hit);
    }
}
// Which pixels a rectangle-mask sun bullet occupies (collision_point, precise) at 1/8 px
// steps, at scales 0.75, -0.75, 1.6, -2 and 2.5: bounding box rows, then rows top-2 to
// bottom+2 of the box's middle column, as 0/1.
pb.x = -500;
var py, px, ys;
for (cf = 0; cf < 5; cf += 1)
{
    ys = 0.75;
    if (cf == 1) { ys = -0.75; }
    if (cf == 2) { ys = 1.6; }
    if (cf == 3) { ys = -2; }
    if (cf == 4) { ys = 2.5; }
    pa.image_xscale = 1;
    pa.image_yscale = ys;
    s += " v" + string(cf) + ":";
    for (q = 0; q < 16; q += 1)
    {
        pa.x = 107.218;
        pa.y = 97 + (q * 0.125);
        px = pa.bbox_left;
        s += string(pa.bbox_top) + "-" + string(pa.bbox_bottom) + "=";
        for (py = pa.bbox_top - 2; py <= pa.bbox_bottom + 2; py += 1)
        {
            s += string(collision_point(px, py, pa, true, false) != noone);
        }
        s += "/";
    }
}
with (pa)
{
    instance_destroy();
}
with (pb)
{
    instance_destroy();
}
return s;
