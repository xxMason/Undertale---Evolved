// ube_live_pack(): the whole attack on the live-build screen as one string (for undo).
var s = string(boxw) + "," + string(boxh) + "," + string(dur);
var i;
for (i = 0; i < on; i += 1)
{
    s += "|" + ube_live_line(i);
}
return s;
