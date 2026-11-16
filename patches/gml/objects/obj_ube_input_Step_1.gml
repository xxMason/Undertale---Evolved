var i;
var now;
for (i = 0; i < 4; i += 1)
{
    now = 0;
    if (global.ube_wasd == 1)
    {
        now = keyboard_check(wkey[i]);
    }
    if (now && held[i] == 0)
    {
        keyboard_key_press(akey[i]);
    }
    if (!now && held[i] == 1)
    {
        keyboard_key_release(akey[i]);
    }
    held[i] = now;
}

// Story guard. While a battle is in progress the only rooms that belong to it are the
// battle room, the game-over room and our menu. If the original code moves anywhere else
// (a boss's post-battle cutscene, an ending, the overworld) the fight is over and the
// story would continue, so return to the menu instead of letting it run.
if (global.ube_state != 3)
{
    battle_t = 0;
}
else if (room == room_battle)
{
    battle_t += 1;
}
if (global.ube_state == 3 && room != room_battle && room != room_gameover && room != room_ube_menu)
{
    guard_t += 1;
    if (guard_t > 2)
    {
        guard_t = 0;
        ube_log("GUARD left battle for " + room_get_name(room) + " after " + string(battle_t) + " frames");
        global.ube_result = 4;
        caster_free(all);
        global.ube_mus_on = 0;
        with (obj_gameover)
        {
            instance_destroy();
        }
        room_goto(room_ube_menu);
    }
}
else
{
    guard_t = 0;
}
