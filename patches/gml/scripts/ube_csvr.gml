// ube_csvr(text, index): the index-th comma-separated field as a number (0 if missing
// or not a number, so a hand-edited boss file cannot crash the game).
var s = ube_csv(argument0, argument1);
var i;
var c;
var digits = 0;
if (s == "")
{
    return 0;
}
for (i = 1; i <= string_length(s); i += 1)
{
    c = string_char_at(s, i);
    if (c >= "0" && c <= "9")
    {
        digits += 1;
    }
    else if (!(c == "." || (c == "-" && i == 1)))
    {
        return 0;
    }
}
if (digits == 0)
{
    return 0;
}
return real(s);
