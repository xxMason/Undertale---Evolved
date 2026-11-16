// Room Start. For a custom boss there is no case in scr_battlegroup, so the monster and
// its music are created here, right after obj_battlecontroller has set the battle up.
if (room == room_battle && global.ube_custom == 1)
{
    global.monsterinstance[0] = instance_create(0, 0, obj_ube_boss);
    var mus = asset_get_index("mus_" + global.ube_cb_music);
    if (mus >= 0)
    {
        if (asset_get_type("mus_" + global.ube_cb_music) != asset_sound)
        {
            mus = -1;
        }
    }
    if (mus < 0)
    {
        mus = mus_battle1;
    }
    global.batmusic = mus;
    caster_loop(global.batmusic, global.ube_cb_musvol, global.ube_cb_muspitch);
}
