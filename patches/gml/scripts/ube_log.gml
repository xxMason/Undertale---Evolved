// ube_log(message): append one line to ube_log.txt in the (isolated) save directory.
var f = file_text_open_append("ube_log.txt");
file_text_write_string(f, argument0);
file_text_writeln(f);
file_text_close(f);
