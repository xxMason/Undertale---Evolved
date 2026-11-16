// End of the speech turn: start attacking.
with (blconwd)
{
    instance_destroy();
}
with (blcon)
{
    instance_destroy();
}
blcon = noone;
blconwd = noone;
talked = 0;
whatiheard = -1;
global.mnfight = 2;
