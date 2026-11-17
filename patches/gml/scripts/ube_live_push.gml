// ube_live_push(): remember the current attack for UNDO (up to 40 steps) and clear REDO.
var i;
if (un >= 40)
{
    for (i = 0; i < 39; i += 1)
    {
        undo[i] = undo[i + 1];
    }
    un = 39;
}
undo[un] = ube_live_pack();
un += 1;
rn = 0;
