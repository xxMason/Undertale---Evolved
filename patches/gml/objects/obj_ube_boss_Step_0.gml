// ---- Turn bookkeeping (same shape as obj_froggit's Step)
if (global.mnfight == 3)
{
    attacked = 0;
}
if (global.mnfight == 1)
{
    if (talked == 0)
    {
        alarm[5] = 60;
        if (global.ube_cb_speech_n == 0)
        {
            alarm[5] = 20;
        }
        alarm[6] = 1;
        talked = 1;
        global.heard = 0;
    }
}
if (control_check_pressed(0))
{
    if (alarm[5] > 5 && obj_lborder.x == global.idealborder[0] && alarm[6] < 0)
    {
        alarm[5] = 2;
    }
}

// ---- Being attacked
if (global.hurtanim[myself] == 1)
{
    shudder = 16;
    alarm[3] = global.damagetimer;
    global.hurtanim[myself] = 3;
}
if (global.hurtanim[myself] == 2)
{
    global.monsterhp[myself] -= takedamage;
    with (dmgwriter)
    {
        alarm[2] = 15;
    }
    if (global.monsterhp[myself] >= 1)
    {
        global.hurtanim[myself] = 0;
        global.myfight = 0;
        global.mnfight = 1;
    }
    else
    {
        global.myfight = 0;
        global.mnfight = 1;
        killed = 1;
        instance_destroy();
        exit;
    }
}
if (global.hurtanim[myself] == 5)
{
    global.damage = 0;
    instance_create((x + (sprite_width / 2)) - 48, y - 24, obj_dmgwriter);
    with (obj_dmgwriter)
    {
        alarm[2] = 30;
    }
    global.myfight = 0;
    global.mnfight = 1;
    global.hurtanim[myself] = 0;
}

// ---- ACT menu text. The original fills this in from SCR_TEXT using the monster type;
// our type has no entry there, so the text is supplied while the target list is showing
// (the box's own text was already stashed by the battle controller at that point).
if (global.bmenuno == 2 && global.myfight == 0 && global.mnfight == 0)
{
    global.msg[0] = menu_str;
    var c;
    for (c = 0; c < 6; c += 1)
    {
        global.choices[c] = ch[c];
    }
}

// ---- Attack turn
if (global.mnfight == 2)
{
    if (attacked == 0)
    {
        cur = -1;
        global.turntimer = 60;
        if (global.ube_cb_atk_n > 0)
        {
            if (global.ube_cb_order == 1)
            {
                cur = turn_n mod global.ube_cb_atk_n;
            }
            else
            {
                cur = floor(random(global.ube_cb_atk_n));
            }
            global.turntimer = global.ube_cb_at_dur[cur];
        }
        atk_t = 0;
        turn_n += 1;
        // Text for the start of the player's next turn.
        if (global.ube_cb_flavor_n > 0)
        {
            global.msg[0] = global.ube_cb_flavor[floor(random(global.ube_cb_flavor_n))];
        }
        else
        {
            global.msg[0] = "* " + global.ube_cb_name + " is waiting.";
        }
        attacked = 1;
    }
    else if (global.turntimer < 1)
    {
        // The original's bullet generators end the turn (obj_bulletgenparent End Step);
        // this boss spawns its own bullets, so it does the same hand-over itself.
        global.turntimer = -1;
        global.mnfight = 3;
    }
    else if (cur >= 0 && instance_exists(obj_heart))
    {
        atk_t += 1;
        if ((atk_t mod global.ube_cb_at_interval[cur]) == 1)
        {
            var L = global.idealborder[0];
            var R = global.idealborder[1];
            var T = global.idealborder[2];
            var B = global.idealborder[3];
            var cx = (L + R) / 2;
            var cy = (T + B) / 2;
            var pat = global.ube_cb_at_pat[cur];
            var cnt = global.ube_cb_at_count[cur];
            var spd = global.ube_cb_at_speed[cur];
            var dm = global.ube_cb_at_dmg[cur];
            var bs = asset_get_index(global.ube_cb_at_sprite[cur]);
            if (bs >= 0)
            {
                if (asset_get_type(global.ube_cb_at_sprite[cur]) != asset_sprite)
                {
                    bs = -1;
                }
            }
            if (bs < 0)
            {
                bs = spr_bulletmd;
            }
            var b;
            var i;
            var px;
            var py;
            if (pat == "aimed")
            {
                // Shots from outside the box, aimed at where the SOUL is right now.
                for (i = 0; i < cnt; i += 1)
                {
                    var side = floor(random(3));
                    px = L + random(R - L);
                    py = T - 24;
                    if (side == 1)
                    {
                        px = L - 24;
                        py = T + random(B - T);
                    }
                    if (side == 2)
                    {
                        px = R + 24;
                        py = T + random(B - T);
                    }
                    b = instance_create(px, py, obj_ube_bullet);
                    b.sprite_index = bs;
                    b.dmg = dm;
                    b.speed = spd;
                    b.direction = point_direction(px, py, obj_heart.x + 8, obj_heart.y + 8);
                }
            }
            else if (pat == "rain")
            {
                // Bullets falling from above the box.
                for (i = 0; i < cnt; i += 1)
                {
                    px = (L + 6) + random((R - L) - 24);
                    b = instance_create(px, T - 20, obj_ube_bullet);
                    b.sprite_index = bs;
                    b.dmg = dm;
                    b.speed = spd;
                    b.direction = 270;
                }
            }
            else if (pat == "ring")
            {
                // A ring that closes in on the middle of the box.
                var off = random(360);
                for (i = 0; i < cnt; i += 1)
                {
                    var ang = off + ((360 / cnt) * i);
                    px = cx + lengthdir_x(120, ang);
                    py = cy + lengthdir_y(120, ang);
                    b = instance_create(px, py, obj_ube_bullet);
                    b.sprite_index = bs;
                    b.dmg = dm;
                    b.speed = spd;
                    b.direction = point_direction(px, py, cx, cy);
                }
            }
            else if (pat == "wall")
            {
                // A wall crossing the box with a gap to slip through. Count = gap size
                // in bullets; walls alternate sides.
                var rows = floor(((B - T) - 12) / 16);
                var gap = floor(random(max(1, (rows - cnt) + 1)));
                for (i = 0; i < rows; i += 1)
                {
                    if (i < gap || i >= gap + cnt)
                    {
                        px = L - 16;
                        if (wall_side == 1)
                        {
                            px = R + 4;
                        }
                        b = instance_create(px, (T + 6) + (i * 16), obj_ube_bullet);
                        b.sprite_index = bs;
                        b.dmg = dm;
                        b.speed = spd;
                        b.direction = wall_side * 180;
                    }
                }
                wall_side = 1 - wall_side;
            }
        }
    }
}

// ---- ACT responses
if (global.myfight == 2)
{
    if (whatiheard != -1)
    {
        if (global.heard == 0)
        {
            var txt = "";
            if (whatiheard == 0)
            {
                txt = global.ube_cb_check;
            }
            else if (whatiheard >= 0 && whatiheard <= 5)
            {
                var a = slot_act[whatiheard];
                if (a >= 0)
                {
                    txt = global.ube_cb_act_resp[a];
                    spare_points += global.ube_cb_act_mercy[a];
                    if (global.ube_cb_spare_need > 0 && spare_points >= global.ube_cb_spare_need)
                    {
                        mercymod = 99999;
                    }
                    ube_log("CUSTOM act=" + global.ube_cb_act_name[a] + " points=" + string(spare_points) + "/" + string(global.ube_cb_spare_need));
                }
            }
            if (txt != "")
            {
                // "/^" = wait for a key press, then close (the original's own markers).
                if (string_pos("/", txt) == 0)
                {
                    txt += "/^";
                }
                global.msc = 0;
                global.msg[0] = txt;
                OBJ_WRITER.halt = 3;
                iii = instance_create(global.idealborder[0], global.idealborder[2], OBJ_WRITER);
                with (iii)
                {
                    halt = 0;
                }
            }
            global.heard = 1;
        }
    }
}

// ---- Sparing
if (global.myfight == 4)
{
    if (global.mercyuse == 0)
    {
        script_execute(scr_mercystandard);
        if (mercy < 0)
        {
            ube_log("CUSTOM spared");
            instance_destroy();
        }
    }
}
