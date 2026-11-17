// ube_live_unpack(text): restore the attack from ube_live_pack's string.
var s = argument0;
var p = string_pos("|", s);
var head = s;
if (p > 0)
{
    head = string_copy(s, 1, p - 1);
    s = string_delete(s, 1, p);
}
else
{
    s = "";
}
boxw = ube_csvr(head, 0);
boxh = ube_csvr(head, 1);
dur = ube_csvr(head, 2);
on = 0;
while (s != "")
{
    p = string_pos("|", s);
    var line = s;
    if (p > 0)
    {
        line = string_copy(s, 1, p - 1);
        s = string_delete(s, 1, p);
    }
    else
    {
        s = "";
    }
    ube_live_parse(on, line);
    on += 1;
}
if (sel >= on)
{
    sel = -1;
}
