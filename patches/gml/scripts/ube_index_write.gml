// ube_index_write(): rewrite custom/index.ini from the in-memory boss list.
var i;
ini_open("custom/index.ini");
ini_write_real("Index", "Count", global.ube_cbl_count);
for (i = 0; i < global.ube_cbl_count; i += 1)
{
    ini_write_string("Index", "File" + string(i), global.ube_cbl_file[i]);
    ini_write_string("Index", "Name" + string(i), global.ube_cbl_name[i]);
}
ini_close();
