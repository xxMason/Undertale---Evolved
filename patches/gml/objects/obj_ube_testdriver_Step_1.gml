// Begin Step. Scenario "trace": the keys the game sees this frame (obj_time reads them in
// its own Begin Step; the driver only changes keys in its Step, so this is the frame's
// state). Bits: 1 left, 2 right, 4 up, 8 down, 16 Z, 32 X, 64 C.
if (global.ube_test == "trace")
{
    tr_seen = 0;
    if (keyboard_check(vk_left))
    {
        tr_seen += 1;
    }
    if (keyboard_check(vk_right))
    {
        tr_seen += 2;
    }
    if (keyboard_check(vk_up))
    {
        tr_seen += 4;
    }
    if (keyboard_check(vk_down))
    {
        tr_seen += 8;
    }
    if (keyboard_check(ord("Z")))
    {
        tr_seen += 16;
    }
    if (keyboard_check(ord("X")))
    {
        tr_seen += 32;
    }
    if (keyboard_check(ord("C")))
    {
        tr_seen += 64;
    }
}
