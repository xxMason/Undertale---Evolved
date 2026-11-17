draw_set_alpha(1);
draw_set_color(c_black);
draw_rectangle(0, 0, 640, 480, false);
if (n == 0)
{
    exit;
}
scr_setfont(fnt_maintext);

var title = "BOSS EDITOR";
if (epage == 1)
{
    title = "DIALOGUE";
}
if (epage == 2)
{
    title = "ACTS";
}
if (epage == 3)
{
    title = "ACT " + string(eidx);
}
if (epage == 4)
{
    title = "ATTACKS";
}
if (epage == 5)
{
    title = "ATTACK " + string(eidx);
}
draw_set_color(c_white);
draw_text_transformed(320 - (string_width(title) * 1.5), 22, title, 3, 3, 0);

var row_x = 70;
var val_x = 320;
var row_y0 = 92;
var row_h = 34;
var nvis = min(n, vis);
var bx1 = 24;
var bx2 = 616;
var by1 = row_y0 - 14;
var by2 = row_y0 + (nvis * row_h) + 4;
draw_set_color(c_white);
draw_rectangle(bx1, by1, bx2, by2, false);
draw_set_color(c_black);
draw_rectangle(bx1 + 5, by1 + 5, bx2 - 5, by2 - 5, false);

var i;
var label;
var val;
var ry;
var sc;
var w;
var maxw;
for (i = escroll; i < n && i < escroll + vis; i += 1)
{
    label = r_label[i];
    val = "";
    if (r_kind[i] == 1 || r_kind[i] == 4)
    {
        val = "< " + string(ube_ed_get(r_key[i])) + " >";
    }
    if (r_kind[i] == 2)
    {
        val = ube_ed_get(r_key[i]);
        if (typing == 1 && tkey == r_key[i])
        {
            val = tval;
        }
        if (string_length(val) > 20)
        {
            val = string_copy(val, 1, 19) + "...";
        }
        if (val == "")
        {
            val = "(empty)";
        }
    }
    if (r_kind[i] == 3)
    {
        val = ube_ed_get(r_key[i]);
        if (string_copy(val, 1, 4) == "spr_")
        {
            val = string_copy(val, 5, string_length(val) - 4);
        }
        if (r_key[i] == "Boss|Sprite" && ube_ed_get("Boss|SpriteFile") != "")
        {
            val = "PNG " + ube_ed_get("Boss|SpriteFile");
        }
        val = "< " + val + " >";
    }
    ry = row_y0 + ((i - escroll) * row_h);
    draw_set_color(c_white);
    if (esel == i)
    {
        draw_set_color(c_yellow);
        draw_sprite(spr_heart, 0, row_x - 34, ry + 6);
    }
    sc = 2;
    w = string_width(label) * 2;
    maxw = (bx2 - row_x) - 20;
    if (val != "")
    {
        maxw = (val_x - row_x) - 10;
    }
    if (w > maxw)
    {
        sc = (2 * maxw) / w;
    }
    draw_text_transformed(row_x, ry + ((2 - sc) * 6), label, sc, sc, 0);
    if (val != "")
    {
        if (r_kind[i] == 2 && esel != i)
        {
            draw_set_color(c_silver);
        }
        sc = 2;
        w = string_width(val) * 2;
        maxw = (bx2 - val_x) - 16;
        if (w > maxw)
        {
            sc = (2 * maxw) / w;
        }
        draw_text_transformed(val_x, ry + ((2 - sc) * 6), val, sc, sc, 0);
    }
}
draw_set_color(c_gray);
if (escroll > 0)
{
    draw_text(bx2 - 104, by1 + 8, "(more above)");
}
if (n > escroll + vis)
{
    draw_text(bx2 - 104, by2 - 22, "(more below)");
}

// ---- Bottom lines: the text being typed, or key hints
var hint = "[UP/DOWN] Move    [LEFT/RIGHT] Change    [Z] Select or type    [X] Back";
if (typing == 1)
{
    var shown = tval;
    if (string_length(shown) > 84)
    {
        shown = "..." + string_copy(shown, string_length(shown) - 80, 81);
    }
    draw_set_color(c_white);
    draw_text(28, by2 + 10, "> " + shown + "_");
    hint = "Type your text.    & = new line    [BACKSPACE] Erase    [ENTER] Done";
}
else
{
    draw_set_color(c_gray);
    if (epage == 0)
    {
        draw_text(28, by2 + 10, "SPARE AFTER = mercy points needed to spare (0 = cannot be talked down).");
    }
    if (epage == 5)
    {
        draw_text(28, by2 + 10, "TEST LIVE drops you in the box with this attack looping; change it with the number keys.");
    }
    if (epage == 3)
    {
        draw_text(28, by2 + 10, "MERCY POINTS count towards the boss's SPARE AFTER number.");
    }
}
draw_set_color(c_gray);
draw_text(320 - (string_width(hint) / 2), 458, hint);
draw_set_color(c_white);
