// ube_list_n(list): number of entries. 0 = attack patterns, 1 = music, 2 = bullet
// sprites, 3 = boss sprites (lists 1-3 are generated from the game data at build time).
if (argument0 == 0)
{
    return 4;
}
if (argument0 == 1)
{
    return global.ube_lmus_n;
}
if (argument0 == 2)
{
    return global.ube_lbul_n;
}
return global.ube_lspr_n;
