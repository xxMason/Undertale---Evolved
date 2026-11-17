// "verify" self-test: compare how long this bullet really lived with what the live-build
// preview predicts (vplife), for bullets that were not aimed at the SOUL.
if (global.ube_test == "verify")
{
    if (vaim == 0 && vplife >= 0 && vplife < 10000)
    {
        var err = vage - vplife;
        global.ube_v_n += 1;
        global.ube_v_sum += err;
        if (abs(err) > abs(global.ube_v_max))
        {
            global.ube_v_max = err;
        }
        if (abs(err) > 3)
        {
            global.ube_v_bad += 1;
            if (global.ube_v_bad <= 6)
            {
                ube_log("VERIFY outlier lived=" + string(vage) + " predicted=" + string(vplife) + " from=" + string(vsx) + "," + string(vsy) + " dir=" + string(direction) + " spd=" + string(speed) + " died_at=" + string(x) + "," + string(y));
            }
        }
    }
}
