// ube_live_store(): write the attack on the live-build screen into the editor's working
// copy of the boss (global.ube_ed) and save the boss file.
var pre = "Attack" + string(lidx) + "|";
var i;
ube_ed_set(pre + "Pattern", "timeline");
ube_ed_set(pre + "Duration", dur);
ube_ed_set(pre + "BoxW", boxw);
ube_ed_set(pre + "BoxH", boxh);
ube_ed_set(pre + "Objects", on);
for (i = 0; i < 40; i += 1)
{
    if (i < on)
    {
        ube_ed_set(pre + "O" + string(i + 1), ube_live_line(i));
    }
    else
    {
        ube_ed_set(pre + "O" + string(i + 1), "");
    }
}
ube_log("LIVE store objects=" + string(on) + " box=" + string(boxw) + "x" + string(boxh) + " dur=" + string(dur));
ube_ed_save(global.ube_ed_file);
