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
