// Speech bubble, then shrink the box and centre the SOUL for the attack.
if (global.ube_cb_speech_n > 0)
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
global.border = global.ube_cb_box;
obj_heart.x = round((global.idealborder[0] + global.idealborder[1]) / 2) - 8;
obj_heart.y = round((global.idealborder[2] + global.idealborder[3]) / 2) - 8;
