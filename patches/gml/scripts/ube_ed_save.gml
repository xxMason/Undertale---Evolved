// ube_ed_save(file): write the editor's working copy to custom/<file>. Removed ACTs and
// attacks are written with an empty Name / Pattern, which the boss loader skips.
var i;
var p;
var sec;
var key;
ini_open("custom/" + argument0);
for (i = 0; i < global.ube_edk_n; i += 1)
{
    p = string_pos("|", global.ube_edk[i]);
    sec = string_copy(global.ube_edk[i], 1, p - 1);
    key = string_copy(global.ube_edk[i], p + 1, string_length(global.ube_edk[i]) - p);
    if (global.ube_edk_s[i] == 1)
    {
        ini_write_string(sec, key, ube_ed_get(global.ube_edk[i]));
    }
    else
    {
        ini_write_real(sec, key, ube_ed_get(global.ube_edk[i]));
    }
}
ini_close();
ube_log("EDITOR save file=" + argument0 + " hp=" + string(ube_ed_get("Boss|HP")) + " a1=" + ube_ed_get("Attack1|Pattern") + " count=" + string(ube_ed_get("Attack1|Count")));
