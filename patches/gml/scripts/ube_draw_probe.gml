// ube_draw_probe(): how the real runner fills draw_line_width quads. Each test line is drawn
// in white on a cleared 48x48 surface and every row's covered pixels are logged as
// "y:first-last" (the quads are convex, so one run per row). Read offline to fit the
// Godot engine's line drawing; the trace scenario logs it once (DRAW ...).
var lines;
lines[0] = "4,40,40,4,6";
lines[1] = "3.3,5.7,44.2,30.9,7.5";
lines[2] = "10,2,10.6,45,4";
lines[3] = "2.5,20.5,45.5,20.5,3";
lines[4] = "40.25,3.75,6.75,44.25,9";
lines[5] = "6,6,42,42,5";
var sf = surface_create(48, 48);
var s = "DRAW";
var k, p, v, x1, y1, x2, y2, w, yy, xx, first, last, c;
for (k = 0; k < 6; k += 1)
{
    // parse "x1,y1,x2,y2,w"
    var str = lines[k] + ",";
    var vals;
    var n = 0;
    while (string_pos(",", str) > 0)
    {
        p = string_pos(",", str);
        vals[n] = real(string_copy(str, 1, p - 1));
        str = string_delete(str, 1, p);
        n += 1;
    }
    surface_set_target(sf);
    draw_clear(c_black);
    draw_set_color(c_white);
    draw_set_alpha(1);
    draw_line_width(vals[0], vals[1], vals[2], vals[3], vals[4]);
    surface_reset_target();
    s += " L" + string(k) + ":";
    for (yy = 0; yy < 48; yy += 1)
    {
        first = -1;
        last = -1;
        for (xx = 0; xx < 48; xx += 1)
        {
            c = surface_getpixel(sf, xx, yy);
            if (colour_get_red(c) > 127)
            {
                if (first < 0)
                {
                    first = xx;
                }
                last = xx;
            }
        }
        if (first >= 0)
        {
            s += string(yy) + "=" + string(first) + "-" + string(last) + "/";
        }
    }
}
// Other primitives at fractional and whole coordinates; every covered run per row
// ("y=a-b,c-d/") since outlines have two runs on most rows.
var sh;
for (k = 0; k < 12; k += 1)
{
    surface_set_target(sf);
    draw_clear(c_black);
    draw_set_color(c_white);
    draw_set_alpha(1);
    switch (k)
    {
        case 0: draw_line(4.3, 10.6, 40.2, 30.4); break;
        case 1: draw_rectangle(20, 16.33, 40, 30.7, true); break;
        case 2: draw_rectangle(5.4, 5.6, 20.5, 12.2, false); break;
        case 3: draw_rectangle(3, 3, 9, 9, false); break;
        case 4: draw_rectangle(2, 2, 12, 12, true); break;
        case 5: draw_line(3, 40, 30, 40); break;
        case 6: draw_line(10, 2, 10, 20); break;
        case 7: draw_line(2.2, 3.7, 45.1, 12.9); break;
        case 8: draw_line(1.5, 44.2, 46.3, 20.8); break;
        case 9: draw_line(40.6, 5.2, 7.1, 40.9); break;
        case 10: draw_line(30.3, 45.4, 5.8, 1.6); break;
        case 11: draw_line(45, 30, 2, 30); break;
    }
    surface_reset_target();
    s += " P" + string(k) + ":";
    for (yy = 0; yy < 48; yy += 1)
    {
        sh = "";
        var inrun = false;
        for (xx = 0; xx <= 48; xx += 1)
        {
            var on = false;
            if (xx < 48)
            {
                on = colour_get_red(surface_getpixel(sf, xx, yy)) > 127;
            }
            if (on && !inrun)
            {
                sh += string(xx) + "-";
                inrun = true;
            }
            if (!on && inrun)
            {
                sh += string(xx - 1) + ",";
                inrun = false;
            }
        }
        if (sh != "")
        {
            s += string(yy) + "=" + sh + "/";
        }
    }
}
// Alpha blending onto black: a white, a mid-green (128) and a 200-grey rectangle at each
// alpha; logged as "a=r255,g128,r200".
s += " ALPHA";
var al;
al[0] = 0.1; al[1] = 0.25; al[2] = 0.333; al[3] = 0.48; al[4] = 0.484; al[5] = 0.5;
al[6] = 0.6; al[7] = 0.75; al[8] = 0.9; al[9] = 0.02; al[10] = 0.47; al[11] = 0.49;
for (k = 0; k < 12; k += 1)
{
    surface_set_target(sf);
    draw_clear(c_black);
    draw_set_alpha(al[k]);
    draw_set_color(c_white);
    draw_rectangle(0, 0, 9, 9, false);
    draw_set_color(make_color_rgb(0, 128, 0));
    draw_rectangle(10, 0, 19, 9, false);
    draw_set_color(make_color_rgb(200, 200, 200));
    draw_rectangle(20, 0, 29, 9, false);
    draw_set_alpha(1);
    surface_reset_target();
    s += " " + string(al[k]) + "=" + string(colour_get_red(surface_getpixel(sf, 4, 4))) + "," + string(colour_get_green(surface_getpixel(sf, 14, 4))) + "," + string(colour_get_red(surface_getpixel(sf, 24, 4)));
}
surface_free(sf);
return s;
