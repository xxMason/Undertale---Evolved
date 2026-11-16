// End Step. The original applies hits in collision events (HP is clamped at 0) and
// obj_battlecontroller checks for death in its next Step, so restoring HP here is enough
// to survive without changing any combat code.
if (room == room_battle)
{
    t += 1;
    room_speed = (30 * global.ube_t_speed) / 100;
    if (hp_prev < 0)
    {
        // Wait for obj_battlecontroller's Create to settle max HP and starting HP.
        if (t >= 2)
        {
            hp_prev = global.hp;
            ref_hp = global.hp;
        }
    }
    else
    {
        if (global.hp < hp_prev)
        {
            hits += 1;
            dmg += hp_prev - global.hp;
            if (global.hp <= 0)
            {
                lethal += 1;
            }
        }
        if (global.ube_t_infhp == 1 && global.hp < ref_hp)
        {
            global.hp = ref_hp;
        }
        hp_prev = global.hp;
    }
    global.ube_t_hits = hits;
    global.ube_t_dmg = dmg;
    global.ube_t_lethal = lethal;
}
if (global.ube_t_retry == 1 && (room == room_battle || room == room_gameover))
{
    if (keyboard_check_pressed(ord("R")))
    {
        ube_log("TRAIN retry");
        with (obj_gameover)
        {
            instance_destroy();
        }
        ube_start_encounter(global.ube_last);
    }
}
