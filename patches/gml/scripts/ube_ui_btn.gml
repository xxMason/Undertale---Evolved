// ube_ui_btn(x1, y1, x2, y2, text, style): draw a button and return 1 if it was clicked
// this frame. Called from obj_ube_editui's Draw event (uses its mx, my, mclick).
// style 0 = normal, 1 = yellow, 2 = disabled, 3 = active (yellow on olive).
var over = (mx >= argument0 && mx < argument2 && my >= argument1 && my < argument3);
var col = c_white;
if (argument5 == 1 || argument5 == 3)
{
    col = c_yellow;
}
if (argument5 == 2)
{
    col = c_gray;
}
draw_set_color(col);
draw_rectangle(argument0, argument1, argument2 - 1, argument3 - 1, false);
draw_set_color(c_black);
if (argument5 == 3)
{
    draw_set_color(make_color_rgb(70, 62, 0));
}
else if (over && argument5 != 2)
{
    draw_set_color(make_color_rgb(44, 44, 44));
}
draw_rectangle(argument0 + 3, argument1 + 3, argument2 - 4, argument3 - 4, false);
draw_set_color(col);
var sc = 1;
if ((argument3 - argument1) >= 44 && (string_width(argument4) * 2) < ((argument2 - argument0) - 12))
{
    sc = 2;
}
draw_text_transformed(round(((argument0 + argument2) / 2) - ((string_width(argument4) * sc) / 2)), round(((argument1 + argument3) / 2) - (7 * sc)), argument4, sc, sc, 0);
if (over && mclick == 1 && argument5 != 2)
{
    mclick = 0;
    return 1;
}
return 0;
