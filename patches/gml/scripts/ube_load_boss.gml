// ube_load_boss(file): read a custom boss definition (custom/<file>) into globals.
// The file format is documented in docs/BATTLE_CREATOR.md.
var k;
var sec;
ini_open("custom/" + argument0);
global.ube_cb_name = ini_read_string("Boss", "Name", "Custom Boss");
global.ube_cb_hp = max(1, floor(ini_read_real("Boss", "HP", 100)));
global.ube_cb_atk = max(0, floor(ini_read_real("Boss", "ATK", 5)));
global.ube_cb_def = floor(ini_read_real("Boss", "DEF", 0));
global.ube_cb_xp = max(0, floor(ini_read_real("Boss", "EXP", 0)));
global.ube_cb_gold = max(0, floor(ini_read_real("Boss", "Gold", 0)));
global.ube_cb_sprite = ini_read_string("Boss", "Sprite", "spr_dummybattle");
global.ube_cb_spritefile = ini_read_string("Boss", "SpriteFile", "");
global.ube_cb_scale = clamp(ini_read_real("Boss", "Scale", 1), 0.25, 8);
global.ube_cb_music = ini_read_string("Boss", "Music", "battle1");
global.ube_cb_musvol = clamp(ini_read_real("Boss", "MusicVolume", 0.6), 0, 1);
global.ube_cb_muspitch = clamp(ini_read_real("Boss", "MusicPitch", 1), 0.25, 3);
global.ube_cb_intro = ini_read_string("Boss", "Intro", "* " + global.ube_cb_name + " appears.");
global.ube_cb_check = ini_read_string("Boss", "Check", "* " + string_upper(global.ube_cb_name) + " - ATK " + string(global.ube_cb_atk) + " DEF " + string(global.ube_cb_def));
global.ube_cb_box = clamp(floor(ini_read_real("Boss", "Box", 3)), 0, 7);
global.ube_cb_order = clamp(floor(ini_read_real("Boss", "AttackOrder", 0)), 0, 1);
global.ube_cb_spare_need = max(0, floor(ini_read_real("Boss", "SpareAfterActs", 0)));
global.ube_cb_spare_lowhp = clamp(floor(ini_read_real("Boss", "SpareWhenWeak", 0)), 0, 1);

// Flavour lines (shown in the box at the start of your turn) and speech-bubble lines.
global.ube_cb_flavor_n = 0;
global.ube_cb_speech_n = 0;
for (k = 1; k <= 6; k += 1)
{
    var fl = ini_read_string("Boss", "Flavor" + string(k), "");
    if (fl != "")
    {
        global.ube_cb_flavor[global.ube_cb_flavor_n] = fl;
        global.ube_cb_flavor_n += 1;
    }
    var sp = ini_read_string("Boss", "Speech" + string(k), "");
    if (sp != "")
    {
        global.ube_cb_speech[global.ube_cb_speech_n] = sp;
        global.ube_cb_speech_n += 1;
    }
}

// Up to five ACT options besides Check.
global.ube_cb_act_n = 0;
for (k = 1; k <= 5; k += 1)
{
    sec = "Act" + string(k);
    var an = ini_read_string(sec, "Name", "");
    if (an != "")
    {
        global.ube_cb_act_name[global.ube_cb_act_n] = string_copy(an, 1, 12);
        global.ube_cb_act_resp[global.ube_cb_act_n] = ini_read_string(sec, "Response", "* You " + an + ".");
        global.ube_cb_act_mercy[global.ube_cb_act_n] = floor(ini_read_real(sec, "Mercy", 0));
        global.ube_cb_act_n += 1;
    }
}

// Up to eight attacks built from pattern blocks.
global.ube_cb_atk_n = 0;
for (k = 1; k <= 8; k += 1)
{
    sec = "Attack" + string(k);
    var pt = ini_read_string(sec, "Pattern", "");
    if (pt != "")
    {
        var n = global.ube_cb_atk_n;
        global.ube_cb_at_pat[n] = pt;
        global.ube_cb_at_count[n] = clamp(floor(ini_read_real(sec, "Count", 1)), 1, 40);
        global.ube_cb_at_speed[n] = clamp(ini_read_real(sec, "Speed", 3), 0.5, 12);
        global.ube_cb_at_interval[n] = clamp(floor(ini_read_real(sec, "Interval", 20)), 2, 300);
        global.ube_cb_at_dur[n] = clamp(floor(ini_read_real(sec, "Duration", 150)), 30, 900);
        global.ube_cb_at_dmg[n] = max(1, floor(ini_read_real(sec, "Damage", global.ube_cb_atk)));
        global.ube_cb_at_sprite[n] = ini_read_string(sec, "Bullet", "spr_bulletmd");
        // Timeline attacks (Pattern="timeline"): a custom box size and up to 40 placed
        // objects. Each object is one line of comma-separated values:
        //   sprite, start frame, x, y (from the box centre), angle, speed, aim at SOUL,
        //   repeat count, frames between repeats, damage, size, spin, face direction
        global.ube_cb_at_boxw[n] = clamp(floor(ini_read_real(sec, "BoxW", 0)), 0, 570);
        global.ube_cb_at_boxh[n] = clamp(floor(ini_read_real(sec, "BoxH", 0)), 0, 300);
        var on = 0;
        if (pt == "timeline")
        {
            var oc = clamp(floor(ini_read_real(sec, "Objects", 0)), 0, 40);
            var oi;
            for (oi = 1; oi <= oc; oi += 1)
            {
                var ol = ini_read_string(sec, "O" + string(oi), "");
                if (ol != "")
                {
                    var ok = (n * 40) + on;
                    global.ube_cb_o_spr[ok] = ube_csv(ol, 0);
                    global.ube_cb_o_time[ok] = max(0, floor(ube_csvr(ol, 1)));
                    global.ube_cb_o_x[ok] = ube_csvr(ol, 2);
                    global.ube_cb_o_y[ok] = ube_csvr(ol, 3);
                    global.ube_cb_o_ang[ok] = ube_csvr(ol, 4);
                    global.ube_cb_o_spd[ok] = clamp(ube_csvr(ol, 5), 0, 20);
                    global.ube_cb_o_aim[ok] = ube_csvr(ol, 6);
                    global.ube_cb_o_cnt[ok] = clamp(floor(ube_csvr(ol, 7)), 1, 60);
                    global.ube_cb_o_every[ok] = clamp(floor(ube_csvr(ol, 8)), 1, 600);
                    global.ube_cb_o_dmg[ok] = max(1, floor(ube_csvr(ol, 9)));
                    global.ube_cb_o_size[ok] = clamp(ube_csvr(ol, 10), 0.25, 8);
                    global.ube_cb_o_spin[ok] = ube_csvr(ol, 11);
                    global.ube_cb_o_face[ok] = ube_csvr(ol, 12);
                    on += 1;
                }
            }
        }
        global.ube_cb_at_objn[n] = on;
        global.ube_cb_atk_n += 1;
    }
}
ini_close();
