if (spin != 0)
{
    image_angle += spin;
}
if (global.ube_test == "verify")
{
    // How far has it already moved when its first Step runs (in frames of travel)?
    if (vage == 0 && speed > 0)
    {
        global.ube_v_ofs = point_distance(x, y, vsx, vsy) / speed;
    }
    vage += 1;
}
