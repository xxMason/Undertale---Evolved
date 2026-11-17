// Scenario "trace": one line per battle frame, written after every other Draw event
// (depth -100000), so damage dealt in Draw events is included. Read by
// godot/tools/trace_compare.ps1 against the same fight in the Godot engine.
//   S lv;maxhp;hp;at;df;wstrength;adef;weapon;armor;inv;battlegroup
//   T f;keys;hp;km;invc;heart_x;heart_y;mnfight;myfight;turn;bmenuno;n;sum_x;sum_y;room
// n/sum_x/sum_y cover every non-persistent instance (the battle's own objects).
if (global.ube_test == "trace" && tr_done == 0 && (room == room_battle || room == room_gameover))
{
    tr_f += 1;
    var fh;
    if (tr_f == 1)
    {
        fh = file_text_open_write("ube_trace.txt");
        file_text_write_string(fh, "S " + string(global.lv) + ";" + string(global.maxhp) + ";" + string(global.hp) + ";" + string(global.at) + ";" + string(global.df) + ";" + string(global.wstrength) + ";" + string(global.adef) + ";" + string(global.weapon) + ";" + string(global.armor) + ";" + string(global.inv) + ";" + string(global.battlegroup));
        file_text_writeln(fh);
        file_text_close(fh);
    }
    var n = 0;
    var sx = 0;
    var sy = 0;
    with (all)
    {
        if (persistent == 0)
        {
            n += 1;
            sx += x;
            sy += y;
        }
    }
    var hx = -1;
    var hy = -1;
    if (instance_exists(obj_heart))
    {
        hx = obj_heart.x;
        hy = obj_heart.y;
    }
    var km = 0;
    if (variable_global_exists("km"))
    {
        km = global.km;
    }
    var rn = 0;
    if (room == room_gameover)
    {
        rn = 1;
    }
    // Optional watched object (5th field of the trace spec): every instance of it.
    var wl = "";
    if (global.ube_trace_watch == "*")
    {
        with (all)
        {
            if (persistent == 0)
            {
                wl += object_get_name(object_index) + "," + string_format(x, 0, 4) + "," + string_format(y, 0, 4) + "," + string_format(image_index, 0, 6) + "|";
            }
        }
    }
    else if (global.ube_trace_watch != "")
    {
        var wo = asset_get_index(global.ube_trace_watch);
        if (wo >= 0)
        {
            with (wo)
            {
                wl += string_format(x, 0, 9) + "," + string_format(y, 0, 9) + "," + string_format(image_index, 0, 6) + "," + string_format(image_speed, 0, 6) + "," + string_format(image_alpha, 0, 9) + "," + string_format(speed, 0, 9) + "," + string_format(hspeed, 0, 9) + "," + string_format(vspeed, 0, 9) + "," + string_format(direction, 0, 9) + "|";
            }
        }
    }
    fh = file_text_open_append("ube_trace.txt");
    if (wl != "")
    {
        file_text_write_string(fh, "W " + string(tr_f) + ";" + wl);
        file_text_writeln(fh);
    }
    file_text_write_string(fh, "T " + string(tr_f) + ";" + string(tr_seen) + ";" + string_format(global.hp, 0, 4) + ";" + string_format(km, 0, 4) + ";" + string_format(global.invc, 0, 4) + ";" + string_format(hx, 0, 4) + ";" + string_format(hy, 0, 4) + ";" + string(global.mnfight) + ";" + string(global.myfight) + ";" + string(global.turn) + ";" + string(global.bmenuno) + ";" + string(n) + ";" + string_format(sx, 0, 4) + ";" + string_format(sy, 0, 4) + ";" + string(rn));
    file_text_writeln(fh);
    file_text_close(fh);
    // Watch "@shots": a screenshot every 50 frames, to compare drawing with the Godot engine.
    if (global.ube_trace_watch == "@shots" && (tr_f mod 50) == 0)
    {
        screen_save("ube_trace_" + string(tr_f) + ".png");
    }
    if (tr_f >= tr_max)
    {
        tr_done = 1;
        ube_log("TRACE done frames=" + string(tr_f) + " hp=" + string(global.hp));
        game_end();
    }
}
