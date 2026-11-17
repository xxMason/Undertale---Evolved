// ube_ed_load(file): fill the editor's working copy from custom/<file>, or with the
// defaults when file is "".
var i;
var p;
var sec;
var key;
ds_map_clear(global.ube_ed);
if (argument0 != "")
{
    ini_open("custom/" + argument0);
}
for (i = 0; i < global.ube_edk_n; i += 1)
{
    var v = global.ube_edk_d[i];
    if (argument0 != "")
    {
        p = string_pos("|", global.ube_edk[i]);
        sec = string_copy(global.ube_edk[i], 1, p - 1);
        key = string_copy(global.ube_edk[i], p + 1, string_length(global.ube_edk[i]) - p);
        if (global.ube_edk_s[i] == 1)
        {
            v = ini_read_string(sec, key, v);
        }
        else
        {
            v = ini_read_real(sec, key, v);
        }
    }
    ds_map_add(global.ube_ed, global.ube_edk[i], v);
}
if (argument0 != "")
{
    ini_close();
}
