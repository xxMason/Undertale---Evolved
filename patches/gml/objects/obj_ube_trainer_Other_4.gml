// Room Start: a new battle (or a retry) resets the counters.
if (room == room_battle)
{
    hits = 0;
    dmg = 0;
    lethal = 0;
    hp_prev = -1;
    ref_hp = -1;
    t = 0;
    global.ube_t_hits = 0;
    global.ube_t_dmg = 0;
    global.ube_t_lethal = 0;
}
