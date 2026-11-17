// ube_ed_set(key, value)
if (ds_map_exists(global.ube_ed, argument0))
{
    ds_map_replace(global.ube_ed, argument0, argument1);
}
else
{
    ds_map_add(global.ube_ed, argument0, argument1);
}
