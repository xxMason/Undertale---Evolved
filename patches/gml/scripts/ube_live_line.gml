// ube_live_line(i): object i of the live-build screen as one line of the boss file.
// Order: sprite, start frame, x, y, angle, speed, aim, repeat, every, damage, size, spin, face.
var i = argument0;
return o_spr[i] + "," + string(o_time[i]) + "," + string(o_x[i]) + "," + string(o_y[i]) + "," + string(o_ang[i]) + "," + string(o_spd[i]) + "," + string(o_aim[i]) + "," + string(o_cnt[i]) + "," + string(o_every[i]) + "," + string(o_dmg[i]) + "," + string(o_size[i]) + "," + string(o_spin[i]) + "," + string(o_face[i]);
