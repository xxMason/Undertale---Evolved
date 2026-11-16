// Hurt shudder (obj_fakefroggit's Alarm 3 without the body-part sprites).
if (hurt_started == 0)
{
    dmgwriter = instance_create((x + (sprite_width / 2)) - 48, y - 24, obj_dmgwriter);
    global.damage = takedamage;
    with (dmgwriter)
    {
        dmg = global.damage;
    }
    hurt_started = 1;
    snd_play(snd_damage);
    alarm[8] = 11;
}
x += shudder;
if (shudder < 0)
{
    shudder = -(shudder + 2);
}
else
{
    shudder = -shudder;
}
if (shudder == 0)
{
    hurt_started = 0;
    global.hurtanim[myself] = 2;
    exit;
}
alarm[3] = 2;
