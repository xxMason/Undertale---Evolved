// Presses keys through the same simulated-key mechanism the original game uses for
// joypads, so the battle itself runs completely unmodified.
if (room != last_room)
{
    if (room == room_battle)
    {
        battles += 1;
    }
    mt = 0;
    seq_i = 0;
    last_room = room;
}
if (room == room_battle || room == room_gameover)
{
    t += 1;
    if (room == room_battle && t == 90 && shot == 0)
    {
        shot = 1;
        screen_save("ube_shot_battle.png");
    }
    if ((t mod 8) == 0)
    {
        keyboard_key_press(ord("Z"));
    }
    if ((t mod 8) == 4)
    {
        keyboard_key_release(ord("Z"));
    }
}
else
{
    if (t > 0)
    {
        keyboard_key_release(ord("Z"));
    }
    t = 0;
}
// Scenario "ui": walk the real menus with key presses.
// 37 left, 38 up, 39 right, 40 down, 90 Z, 88 X.
if (global.ube_test == "ui" && room == room_ube_menu)
{
    var seq;
    var n;
    if (battles == 0)
    {
        // PLAYER SETUP: LOVE 1 -> 5, starting HP 36 -> 33, back, FIGHT SELECT, Froggit.
        seq[0] = 40;
        seq[1] = 90;
        seq[2] = 39;
        seq[3] = 39;
        seq[4] = 39;
        seq[5] = 39;
        seq[6] = 40;
        seq[7] = 37;
        seq[8] = 37;
        seq[9] = 37;
        seq[10] = 88;
        seq[11] = 38;
        seq[12] = 90;
        seq[13] = 90;
        n = 14;
    }
    else
    {
        // Results: MAIN MENU, then EXIT.
        seq[0] = 40;
        seq[1] = 40;
        seq[2] = 90;
        seq[3] = 38;
        seq[4] = 90;
        n = 5;
    }
    // The runner ignores simulated keys for the first few seconds after start-up, so
    // probe with an unused key (Q) until one registers before starting the sequence.
    if (ready == 0)
    {
        probe += 1;
        if ((probe mod 10) == 1)
        {
            keyboard_key_press(81);
        }
        if ((probe mod 10) == 4)
        {
            if (keyboard_check(81))
            {
                ready = 1;
            }
            keyboard_key_release(81);
        }
    }
    else
    {
        mt += 1;
    }
    if (mt >= 30 && seq_i < n)
    {
        var ph = (mt - 30) mod 10;
        if (ph == 0)
        {
            if (seq_i == 2 && battles == 0)
            {
                screen_save("ube_shot_setup.png");
            }
            keyboard_key_press(seq[seq_i]);
        }
        if (ph == 4)
        {
            keyboard_key_release(seq[seq_i]);
            seq_i += 1;
        }
    }
}
total += 1;
if (total > 5400)
{
    screen_save("ube_shot_timeout.png");
    ube_log("TEST TIMEOUT room=" + string(room));
    game_end();
}
