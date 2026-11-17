// Battle Creator editor. Works on the copy of the boss held in global.ube_ed (see
// ube_ed_load / ube_ed_save); obj_ube_controller creates this object and steps aside
// (its page 9) while it exists.
// Pages: 0 boss, 1 dialogue, 2 ACT list, 3 one ACT, 4 attack list, 5 one attack.
epage = 0;
esel = 0;
escroll = 0;
eidx = 1;
n = 0;
vis = 9;
ptimer = 0;
hold = 0;
typing = 0;
tkey = "";
tval = "";
del_confirm = 0;
r_label[0] = "";
r_kind[0] = 0;
r_key[0] = "";
r_min[0] = 0;
r_max[0] = 0;
r_step[0] = 0;
