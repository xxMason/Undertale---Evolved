// ube_ui_step(x1, y1, x2, label, value): a "< label  value >" stepper, 32 px tall.
// Returns -1, 0 or 1. Holding the mouse on an arrow repeats.
var r = 0;
if (ube_ui_btn(argument0, argument1, argument0 + 32, argument1 + 32, "<", 0))
{
    r = -1;
}
if (ube_ui_btn(argument2 - 32, argument1, argument2, argument1 + 32, ">", 0))
{
    r = 1;
}
if (mdown == 1 && mhold > 24 && (mhold mod 3) == 0 && my >= argument1 && my < argument1 + 32)
{
    if (mx >= argument0 && mx < argument0 + 32)
    {
        r = -1;
    }
    if (mx >= argument2 - 32 && mx < argument2)
    {
        r = 1;
    }
}
draw_set_color(make_color_rgb(24, 24, 24));
draw_rectangle(argument0 + 34, argument1, argument2 - 35, argument1 + 31, false);
draw_set_color(c_gray);
draw_text(argument0 + 42, argument1 + 9, argument3);
draw_set_color(c_white);
draw_text((argument2 - 42) - string_width(argument4), argument1 + 9, argument4);
return r;
