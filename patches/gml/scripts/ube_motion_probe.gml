// ube_motion_probe(): how the real runner turns direction + speed into hspeed/vspeed and
// back. For each test direction the calling instance's direction is set, then speed = 7,
// and the resulting hspeed, vspeed, direction and speed are logged with 9 decimals
// ("MOTION d=h,v,dir,spd/"). Then hspeed/vspeed are set directly and direction/speed read
// back ("MOTION2"). The instance's motion is cleared afterwards. Read offline to fit the
// Godot engine (the trace scenario logs it once).
var dirs;
dirs[0] = 270.24552;
dirs[1] = 277.1308;
dirs[2] = 180.2635;
dirs[3] = 3.6785;
dirs[4] = 90.3;
dirs[5] = 45;
dirs[6] = 270;
dirs[7] = 269.9;
dirs[8] = 270.01;
dirs[9] = 0.001;
dirs[10] = 359.99;
dirs[11] = 123.456789;
var s = "MOTION";
var k;
for (k = 0; k < 12; k += 1)
{
    speed = 0;
    direction = dirs[k];
    speed = 7;
    s += " " + string_format(dirs[k], 0, 6) + "=" + string_format(hspeed, 0, 9) + "," + string_format(vspeed, 0, 9) + "," + string_format(direction, 0, 9) + "," + string_format(speed, 0, 9);
}
s += " | MOTION2";
for (k = 0; k < 6; k += 1)
{
    speed = 0;
    hspeed = 0.03003 + k * 1.37;
    vspeed = 7 - k * 2.11;
    s += " " + string(k) + "=" + string_format(direction, 0, 9) + "," + string_format(speed, 0, 9);
}
// Gravity-like accumulation done by hand: hspeed += 0.2 * cos(270 degrees) as GML computes it.
s += " | DEG " + string_format(degtorad(270), 0, 12) + "," + string_format(cos(degtorad(270)) * 1000000000, 0, 6) + "," + string_format(lengthdir_x(1, 270) * 1000000000, 0, 6);
speed = 0;
hspeed = 0;
vspeed = 0;
direction = 0;
return s;
