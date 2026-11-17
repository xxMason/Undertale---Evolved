// ube_csv(text, index): the index-th (0-based) comma-separated field of text, or "".
var s = argument0;
var i;
var p;
for (i = 0; i < argument1; i += 1)
{
    p = string_pos(",", s);
    if (p == 0)
    {
        return "";
    }
    s = string_delete(s, 1, p);
}
p = string_pos(",", s);
if (p > 0)
{
    s = string_copy(s, 1, p - 1);
}
return s;
