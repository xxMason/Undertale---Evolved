// Automated self-test driver. Only ever created when ube_config.ini has [Test] Scenario set
// (the launcher writes that for --selftest and clears it for normal launches).
t = 0;
total = 0;
shot = 0;
mt = 0;
seq_i = 0;
battles = 0;
last_room = -1;
esc = 0;
gear_done = 0;
train_r = 0;
ready = 0;
probe = 0;
kready = 0;
kp = 0;
rt = 0;
gear_go = 0;
cb_seen = 0;
cs_t = 0;
cs_key = 90;
cs_menu = -1;
cs_menu_t = 0;
cs_shot2 = 0;
cs_shot10 = 0;
tl_logged = 0;
tl_shot = 0;
v_done = 0;
rec_on = 0;
rec_f = 0;
rec_keys = 0;
// Scenario "trace" (frame-by-frame comparison with the Godot engine): battle frame
// counter, keys held by the driver, keys the game saw this frame, and the frame cap.
tr_f = 0;
tr_keys = 0;
tr_seen = 0;
tr_done = 0;
tr_max = global.ube_trace_frames;
if (global.ube_test == "trace")
{
    // Drawn last, so the log line sees everything the frame's Draw events did.
    depth = -100000;
}
