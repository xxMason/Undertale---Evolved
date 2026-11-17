// ube_row(label, kind, key, a, b, step): add one editor row (called by obj_ube_editor).
// kind 0 = action (key is the action name, a its number), 1 = whole number,
// 2 = text, 3 = pick from list number a, 4 = decimal number.
r_label[n] = argument0;
r_kind[n] = argument1;
r_key[n] = argument2;
r_min[n] = argument3;
r_max[n] = argument4;
r_step[n] = argument5;
n += 1;
