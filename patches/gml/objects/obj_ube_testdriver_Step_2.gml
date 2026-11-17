// Recording for the Godot comparison (scenario "record"), written after collisions have
// been resolved for the frame. One line per frame of the monster's attack:
//   REC f;keys;heart_x;heart_y;hp;invc;lborder_x;uborder_y;rborder_x;dborder_y;bullets
// keys = what the driver holds from this frame's Step on (it acts on the next frame's
// keyboard events): 1 left, 2 right, 4 up, 8 down, 16 X.
if ((global.ube_test == "record" || global.ube_test == "record2") && rec_on == 1 && room == room_battle)
{
    // Every bullet's position, in instance order.
    var bl = "";
    with (obj_ube_bullet)
    {
        bl += string_format(x, 0, 6) + "," + string_format(y, 0, 6) + "," + string(bbox_left) + "," + string(bbox_top) + "," + string(bbox_right) + "," + string(bbox_bottom) + "|";
    }
    var fh = file_text_open_append("ube_record.txt");
    file_text_write_string(fh, "REC " + string(rec_f) + ";" + string(rec_keys) + ";" + string(obj_heart.x) + ";" + string(obj_heart.y) + ";" + string(global.hp) + ";" + string(global.invc) + ";" + string(obj_lborder.x) + ";" + string(obj_uborder.y) + ";" + string(obj_rborder.x) + ";" + string(obj_dborder.y) + ";" + string(instance_number(obj_ube_bullet)) + ";" + bl);
    file_text_writeln(fh);
    file_text_close(fh);
    rec_f += 1;
    if (rec_f >= 245)
    {
        ube_log("RECORD done frames=" + string(rec_f) + " hp=" + string(global.hp));
        game_end();
    }
}
