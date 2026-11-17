// Speech bubble, then size the box for the coming attack and centre the SOUL.
if (global.ube_cb_speech_n > 0 && global.ube_lab < 0)
{
    var bx = x + sprite_width;
    if (bx > 470)
    {
        bx = 470;
    }
    blcon = instance_create(bx, max(8, y), obj_blconsm);
    global.msg[0] = global.ube_cb_speech[floor(random(global.ube_cb_speech_n))];
    global.msg[1] = "%%%";
    global.typer = 2;
    blconwd = instance_create(blcon.x + 15, blcon.y + 10, OBJ_NOMSCWRITER);
}

// The attack is chosen here, before the box is shaped, because a timeline attack can
// have its own box size.
next_cur = -1;
if (global.ube_cb_atk_n > 0)
{
    if (global.ube_lab >= 0)
    {
        next_cur = min(global.ube_lab, global.ube_cb_atk_n - 1);
    }
    else if (global.ube_cb_order == 1)
    {
        next_cur = turn_n mod global.ube_cb_atk_n;
    }
    else
    {
        next_cur = floor(random(global.ube_cb_atk_n));
    }
}
global.border = global.ube_cb_box;
SCR_BORDERSETUP(0, 0, 0, 0, 0);
if (next_cur >= 0)
{
    if (global.ube_cb_at_boxw[next_cur] > 0 && global.ube_cb_at_boxh[next_cur] > 0)
    {
        // Border number 9777 has no preset in SCR_BORDERSETUP, so the values set here
        // are left alone when the battle controller calls it each step.
        global.border = 9777;
        global.idealborder[0] = 320 - round(global.ube_cb_at_boxw[next_cur] / 2);
        global.idealborder[1] = 320 + round(global.ube_cb_at_boxw[next_cur] / 2);
        global.idealborder[3] = 385;
        global.idealborder[2] = 385 - global.ube_cb_at_boxh[next_cur];
    }
}
obj_heart.x = round((global.idealborder[0] + global.idealborder[1]) / 2) - 8;
obj_heart.y = round((global.idealborder[2] + global.idealborder[3]) / 2) - 8;
