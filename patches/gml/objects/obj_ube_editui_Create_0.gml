// LIVE BUILD: the timeline attack builder (room_ube_editor, 1280x960). The window is
// enlarged while this room is open; ube_live_leave() puts it back.
//
// Screen layout (all in room pixels):
//   stage      the battle screen at 1:1, top-left corner at (SX, SY)
//   top bar    attack picker and box / length steppers
//   right      LIVE BUILD panel: ADD (palette), OBJECTS (list), EDIT (settings)
//   timeline   one row per object under the stage, with the playhead
window_set_size(1280, 960);
surface_resize(application_surface, 1280, 960);
t = 0;
SX = 120;
SY = 96;
PX = 900;
PR = 1270;
TLX = 150;
TLW = 710;
TLY = 632;

lidx = global.ube_live_idx;
on = 0;
o_spr[0] = "";
o_time[0] = 0;
o_x[0] = 0;
o_y[0] = 0;
o_ang[0] = 0;
o_spd[0] = 0;
o_aim[0] = 0;
o_cnt[0] = 1;
o_every[0] = 1;
o_dmg[0] = 1;
o_size[0] = 1;
o_spin[0] = 0;
o_face[0] = 0;
undo[0] = "";
redo[0] = "";
un = 0;
rn = 0;
sel = -1;
dur = 240;
boxw = 160;
boxh = 135;
T = 0;
ube_live_load();

armed = "";
tab = 0;
ppage = 0;
playing = 1;
slow = 0;
hitb = 0;
drag = 0;
mx = 0;
my = 0;
mclick = 0;
mdown = 0;
mhold = 0;
tscroll = 0;
act = "";
step_push_t = -100;
global.ube_live_visits += 1;

// Boss picture, resolved the same way obj_ube_boss does.
bspr = -1;
bscale = clamp(ube_ed_get("Boss|Scale"), 0.25, 8);
var bfile = ube_ed_get("Boss|SpriteFile");
if (bfile != "")
{
    if (file_exists("custom/" + bfile))
    {
        bspr = sprite_add("custom/" + bfile, 1, false, false, 0, 0);
    }
}
if (bspr < 0)
{
    bspr = asset_get_index(ube_ed_get("Boss|Sprite"));
    if (bspr >= 0)
    {
        if (asset_get_type(ube_ed_get("Boss|Sprite")) != asset_sprite)
        {
            bspr = -1;
        }
    }
}
if (bspr < 0)
{
    bspr = object_get_sprite(obj_dummymonster);
}
prev_sel = -1;
drag_off = 0;
