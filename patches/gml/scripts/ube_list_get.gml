// ube_list_get(list, index)
if (argument0 == 0)
{
    if (argument1 == 0)
    {
        return "rain";
    }
    if (argument1 == 1)
    {
        return "aimed";
    }
    if (argument1 == 2)
    {
        return "ring";
    }
    return "wall";
}
if (argument0 == 1)
{
    return global.ube_lmus[argument1];
}
if (argument0 == 2)
{
    return global.ube_lbul[argument1];
}
return global.ube_lspr[argument1];
