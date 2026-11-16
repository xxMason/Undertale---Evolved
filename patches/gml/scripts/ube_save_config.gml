// ube_save_config(): write the player setup and settings to ube_config.ini.
var k;
ini_open("ube_config.ini");
ini_write_real("Player", "LOVE", global.ube_lv);
ini_write_real("Player", "HP", global.ube_hp);
ini_write_real("Player", "Weapon", global.ube_weapon);
ini_write_real("Player", "Armor", global.ube_armor);
for (k = 0; k < 8; k += 1)
{
    ini_write_real("Player", "Item" + string(k), global.ube_item[k]);
}
ini_write_real("Settings", "Movement", global.ube_wasd);
ini_close();
