// ube_live_load(): read attack number lidx from the editor's working copy of the boss.
var pre = "Attack" + string(lidx) + "|";
var i;
dur = clamp(ube_ed_get(pre + "Duration"), 30, 900);
boxw = ube_ed_get(pre + "BoxW");
boxh = ube_ed_get(pre + "BoxH");
if (boxw <= 0 || boxh <= 0)
{
    // The game's usual small box.
    boxw = 160;
    boxh = 135;
}
on = 0;
var cnt = clamp(ube_ed_get(pre + "Objects"), 0, 40);
for (i = 1; i <= cnt; i += 1)
{
    var line = ube_ed_get(pre + "O" + string(i));
    if (line != "")
    {
        ube_live_parse(on, line);
        on += 1;
    }
}
sel = -1;
un = 0;
rn = 0;
T = 0;
