// ube_live_parse(i, line): fill object i from one line of the boss file.
var i = argument0;
var l = argument1;
o_spr[i] = ube_csv(l, 0);
o_time[i] = max(0, floor(ube_csvr(l, 1)));
o_x[i] = ube_csvr(l, 2);
o_y[i] = ube_csvr(l, 3);
o_ang[i] = ube_csvr(l, 4);
o_spd[i] = clamp(ube_csvr(l, 5), 0, 20);
o_aim[i] = ube_csvr(l, 6);
o_cnt[i] = clamp(floor(ube_csvr(l, 7)), 1, 60);
o_every[i] = clamp(floor(ube_csvr(l, 8)), 1, 600);
o_dmg[i] = max(1, floor(ube_csvr(l, 9)));
o_size[i] = clamp(ube_csvr(l, 10), 0.25, 8);
o_spin[i] = ube_csvr(l, 11);
o_face[i] = ube_csvr(l, 12);
