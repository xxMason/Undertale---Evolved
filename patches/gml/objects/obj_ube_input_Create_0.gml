// Movement option. In WASD mode this object presses the arrow keys on the player's
// behalf, so menus and the original battle code read their usual keys unchanged.
// (Verified: simulated arrows reach keyboard_check_direct and obj_time.up/down/left/right.)
wkey[0] = ord("W");
wkey[1] = ord("A");
wkey[2] = ord("S");
wkey[3] = ord("D");
akey[0] = vk_up;
akey[1] = vk_left;
akey[2] = vk_down;
akey[3] = vk_right;
held[0] = 0;
held[1] = 0;
held[2] = 0;
held[3] = 0;
