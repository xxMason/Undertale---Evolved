// ube_ed_keys(): the table of every boss-file key the editor knows, as "Section|Key",
// with whether it is text (1) or a number (0) and its default. Built once at start-up.
var n = 0;
var k;
var s;
global.ube_edk[n] = "Boss|Name";        global.ube_edk_s[n] = 1; global.ube_edk_d[n] = "New Boss"; n += 1;
global.ube_edk[n] = "Boss|HP";          global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 100; n += 1;
global.ube_edk[n] = "Boss|ATK";         global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 5; n += 1;
global.ube_edk[n] = "Boss|DEF";         global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
global.ube_edk[n] = "Boss|EXP";         global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
global.ube_edk[n] = "Boss|Gold";        global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
global.ube_edk[n] = "Boss|Sprite";      global.ube_edk_s[n] = 1; global.ube_edk_d[n] = "spr_dummybattle"; n += 1;
global.ube_edk[n] = "Boss|SpriteFile";  global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
global.ube_edk[n] = "Boss|Scale";       global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 1; n += 1;
global.ube_edk[n] = "Boss|Music";       global.ube_edk_s[n] = 1; global.ube_edk_d[n] = "battle1"; n += 1;
global.ube_edk[n] = "Boss|MusicVolume"; global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0.6; n += 1;
global.ube_edk[n] = "Boss|MusicPitch";  global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 1; n += 1;
global.ube_edk[n] = "Boss|Intro";       global.ube_edk_s[n] = 1; global.ube_edk_d[n] = "* A new boss appears."; n += 1;
global.ube_edk[n] = "Boss|Check";       global.ube_edk_s[n] = 1; global.ube_edk_d[n] = "* NEW BOSS&* Made in the Battle Creator."; n += 1;
global.ube_edk[n] = "Boss|Box";         global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 3; n += 1;
global.ube_edk[n] = "Boss|AttackOrder"; global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
global.ube_edk[n] = "Boss|SpareAfterActs"; global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
global.ube_edk[n] = "Boss|SpareWhenWeak";  global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
for (k = 1; k <= 6; k += 1)
{
    global.ube_edk[n] = "Boss|Flavor" + string(k); global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
    global.ube_edk[n] = "Boss|Speech" + string(k); global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
}
for (k = 1; k <= 5; k += 1)
{
    s = "Act" + string(k) + "|";
    global.ube_edk[n] = s + "Name";     global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
    global.ube_edk[n] = s + "Response"; global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
    global.ube_edk[n] = s + "Mercy";    global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
}
for (k = 1; k <= 8; k += 1)
{
    s = "Attack" + string(k) + "|";
    global.ube_edk[n] = s + "Pattern";  global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
    global.ube_edk[n] = s + "Count";    global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 2; n += 1;
    global.ube_edk[n] = s + "Speed";    global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 3; n += 1;
    global.ube_edk[n] = s + "Interval"; global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 20; n += 1;
    global.ube_edk[n] = s + "Duration"; global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 150; n += 1;
    global.ube_edk[n] = s + "Damage";   global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 5; n += 1;
    global.ube_edk[n] = s + "Bullet";   global.ube_edk_s[n] = 1; global.ube_edk_d[n] = "spr_bulletmd"; n += 1;
    // Timeline attacks (Pattern = "timeline"): box size and up to 40 placed objects.
    global.ube_edk[n] = s + "BoxW";     global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
    global.ube_edk[n] = s + "BoxH";     global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
    global.ube_edk[n] = s + "Objects";  global.ube_edk_s[n] = 0; global.ube_edk_d[n] = 0; n += 1;
    var o;
    for (o = 1; o <= 40; o += 1)
    {
        global.ube_edk[n] = s + "O" + string(o); global.ube_edk_s[n] = 1; global.ube_edk_d[n] = ""; n += 1;
    }
}
global.ube_edk_n = n;
global.ube_ed = ds_map_create();
