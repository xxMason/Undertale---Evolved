ptimer += 1;
if ((global.ube_test == "editor" || global.ube_test == "live") && global.ube_ed_resumed == 1 && ptimer == 30)
{
    ube_log("EXIT test=" + global.ube_test);
    game_end();
    exit;
}

// ---- Typing a text field. keyboard_string is GameMaker's own typed-text buffer
// (it handles Backspace); Enter finishes.
if (typing == 1)
{
    var ts = keyboard_string;
    if (string_length(ts) > 120)
    {
        ts = string_copy(ts, 1, 120);
        keyboard_string = ts;
    }
    tval = ts;
    if (keyboard_check_pressed(vk_enter))
    {
        // Double quotes would break the boss file.
        ts = string_replace_all(ts, chr(34), "'");
        if (tkey == "Boss|Name" && ts == "")
        {
            ts = "Boss";
        }
        ube_ed_set(tkey, ts);
        typing = 0;
        ptimer = 0;
        snd_play(snd_select);
    }
    exit;
}

// ---- Counts of ACTs and attacks (they are kept packed from 1).
var k;
var act_n = 0;
var atk_n = 0;
for (k = 1; k <= 5; k += 1)
{
    if (ube_ed_get("Act" + string(k) + "|Name") != "")
    {
        act_n = k;
    }
}
for (k = 1; k <= 8; k += 1)
{
    if (ube_ed_get("Attack" + string(k) + "|Pattern") != "")
    {
        atk_n = k;
    }
}

// ---- Rows of the current page
n = 0;
var pre;
if (epage == 0)
{
    ube_row("NAME", 2, "Boss|Name", 0, 0, 0);
    ube_row("HP", 1, "Boss|HP", 1, 9999, 10);
    ube_row("ATTACK", 1, "Boss|ATK", 0, 99, 1);
    ube_row("DEFENSE", 1, "Boss|DEF", -99, 999, 1);
    ube_row("GOLD", 1, "Boss|Gold", 0, 9999, 10);
    ube_row("IMAGE", 3, "Boss|Sprite", 3, 0, 0);
    ube_row("IMAGE SIZE", 4, "Boss|Scale", 0.5, 8, 0.5);
    ube_row("MUSIC", 3, "Boss|Music", 1, 0, 0);
    ube_row("BOX SIZE", 1, "Boss|Box", 0, 7, 1);
    ube_row("SPARE AFTER", 1, "Boss|SpareAfterActs", 0, 10, 1);
    ube_row("DIALOGUE", 0, "dialog", 0, 0, 0);
    ube_row("ACTS (" + string(act_n) + ")", 0, "acts", 0, 0, 0);
    ube_row("ATTACKS (" + string(atk_n) + ")", 0, "attacks", 0, 0, 0);
    ube_row("TEST FIGHT", 0, "test", 0, 0, 0);
    ube_row("SAVE AND EXIT", 0, "save", 0, 0, 0);
    if (del_confirm == 1)
    {
        ube_row("PRESS AGAIN TO DELETE", 0, "delete", 0, 0, 0);
    }
    else
    {
        ube_row("DELETE BOSS", 0, "delete", 0, 0, 0);
    }
}
if (epage == 1)
{
    ube_row("INTRO", 2, "Boss|Intro", 0, 0, 0);
    ube_row("CHECK", 2, "Boss|Check", 0, 0, 0);
    ube_row("FLAVOR 1", 2, "Boss|Flavor1", 0, 0, 0);
    ube_row("FLAVOR 2", 2, "Boss|Flavor2", 0, 0, 0);
    ube_row("FLAVOR 3", 2, "Boss|Flavor3", 0, 0, 0);
    ube_row("SPEECH 1", 2, "Boss|Speech1", 0, 0, 0);
    ube_row("SPEECH 2", 2, "Boss|Speech2", 0, 0, 0);
    ube_row("SPEECH 3", 2, "Boss|Speech3", 0, 0, 0);
    ube_row("BACK", 0, "back", 0, 0, 0);
}
if (epage == 2)
{
    for (k = 1; k <= act_n; k += 1)
    {
        ube_row(string(k) + ". " + ube_ed_get("Act" + string(k) + "|Name"), 0, "act", k, 0, 0);
    }
    if (act_n < 5)
    {
        ube_row("ADD ACT", 0, "addact", 0, 0, 0);
    }
    ube_row("BACK", 0, "back", 0, 0, 0);
}
if (epage == 3)
{
    pre = "Act" + string(eidx) + "|";
    ube_row("NAME", 2, pre + "Name", 0, 0, 0);
    ube_row("RESPONSE", 2, pre + "Response", 0, 0, 0);
    ube_row("MERCY POINTS", 1, pre + "Mercy", 0, 5, 1);
    ube_row("DELETE ACT", 0, "delact", 0, 0, 0);
    ube_row("BACK", 0, "back", 0, 0, 0);
}
if (epage == 4)
{
    for (k = 1; k <= atk_n; k += 1)
    {
        pre = "Attack" + string(k) + "|";
        if (ube_ed_get(pre + "Pattern") == "timeline")
        {
            ube_row(string(k) + ". LIVE BUILD  (" + string(ube_ed_get(pre + "Objects")) + " objects)", 0, "atk", k, 0, 0);
        }
        else
        {
            ube_row(string(k) + ". " + ube_ed_get(pre + "Pattern") + " x" + string(ube_ed_get(pre + "Count")), 0, "atk", k, 0, 0);
        }
    }
    if (atk_n < 8)
    {
        ube_row("+ NEW ATTACK (LIVE BUILD)", 0, "addlive", 0, 0, 0);
        ube_row("+ NEW SIMPLE ATTACK", 0, "addatk", 0, 0, 0);
    }
    ube_row("BACK", 0, "back", 0, 0, 0);
}
if (epage == 5)
{
    pre = "Attack" + string(eidx) + "|";
    ube_row("PATTERN", 3, pre + "Pattern", 0, 0, 0);
    ube_row("COUNT", 1, pre + "Count", 1, 40, 1);
    ube_row("SPEED", 4, pre + "Speed", 0.5, 12, 0.5);
    ube_row("INTERVAL", 1, pre + "Interval", 2, 300, 2);
    ube_row("DURATION", 1, pre + "Duration", 30, 900, 10);
    ube_row("DAMAGE", 1, pre + "Damage", 1, 99, 1);
    ube_row("BULLET", 3, pre + "Bullet", 2, 0, 0);
    ube_row("TEST LIVE", 0, "lab", 0, 0, 0);
    ube_row("DELETE ATTACK", 0, "delatk", 0, 0, 0);
    ube_row("BACK", 0, "back", 0, 0, 0);
}
if (esel >= n)
{
    esel = n - 1;
}

// ---- Input (same keys as the rest of the menus)
var k_up = keyboard_check_pressed(vk_up);
var k_down = keyboard_check_pressed(vk_down);
var k_left = keyboard_check_pressed(vk_left);
var k_right = keyboard_check_pressed(vk_right);
var k_ok = control_check_pressed(0);
var k_back = control_check_pressed(1);
if (ptimer < 4)
{
    k_ok = 0;
    k_back = 0;
}
if (keyboard_check(vk_left) || keyboard_check(vk_right))
{
    hold += 1;
}
else
{
    hold = 0;
}
if (hold > 15 && (hold mod 2) == 0)
{
    if (keyboard_check(vk_left))
    {
        k_left = 1;
    }
    if (keyboard_check(vk_right))
    {
        k_right = 1;
    }
}
if (k_down)
{
    esel = (esel + 1) mod n;
    del_confirm = 0;
    snd_play(snd_squeak);
}
if (k_up)
{
    esel = ((esel - 1) + n) mod n;
    del_confirm = 0;
    snd_play(snd_squeak);
}
if (esel < escroll)
{
    escroll = esel;
}
if (esel >= escroll + vis)
{
    escroll = (esel - vis) + 1;
}

var kind = r_kind[esel];
var key = r_key[esel];
var d = k_right - k_left;
if (d != 0)
{
    if (kind == 1 || kind == 4)
    {
        var v = clamp(ube_ed_get(key) + (d * r_step[esel]), r_min[esel], r_max[esel]);
        if (v != ube_ed_get(key))
        {
            ube_ed_set(key, v);
            snd_play(snd_squeak);
        }
    }
    if (kind == 3)
    {
        var lid = r_min[esel];
        var ln = ube_list_n(lid);
        var cur = ube_ed_get(key);
        var pos = 0;
        var li;
        for (li = 0; li < ln; li += 1)
        {
            if (ube_list_get(lid, li) == cur)
            {
                pos = li;
            }
        }
        pos = ((pos + d) + ln) mod ln;
        ube_ed_set(key, ube_list_get(lid, pos));
        if (key == "Boss|Sprite")
        {
            // Picking one of the game's sprites replaces a PNG set in the file.
            ube_ed_set("Boss|SpriteFile", "");
        }
        snd_play(snd_squeak);
    }
}

var act = "";
if (k_ok)
{
    if (kind == 2)
    {
        typing = 1;
        tkey = key;
        tval = ube_ed_get(key);
        keyboard_string = tval;
        snd_play(snd_select);
        exit;
    }
    if (kind == 0)
    {
        act = key;
    }
}
if (k_back)
{
    act = "back";
}
if (act == "")
{
    exit;
}
snd_play(snd_select);
ptimer = 0;

// ---- Actions
var j;
var src;
var dst;
if (act == "back")
{
    if (epage == 0)
    {
        act = "save";
    }
    else if (epage == 3)
    {
        epage = 2;
        esel = eidx - 1;
    }
    else if (epage == 5)
    {
        epage = 4;
        esel = eidx - 1;
    }
    else
    {
        esel = 9 + epage;
        if (epage == 4)
        {
            esel = 12;
        }
        if (epage == 2)
        {
            esel = 11;
        }
        if (epage == 1)
        {
            esel = 10;
        }
        epage = 0;
    }
    escroll = 0;
}
if (act == "dialog")
{
    epage = 1;
    esel = 0;
    escroll = 0;
}
if (act == "acts")
{
    epage = 2;
    esel = 0;
    escroll = 0;
}
if (act == "attacks")
{
    epage = 4;
    esel = 0;
    escroll = 0;
}
if (act == "act")
{
    eidx = r_min[esel];
    epage = 3;
    esel = 0;
}
if (act == "addact")
{
    eidx = act_n + 1;
    pre = "Act" + string(eidx) + "|";
    ube_ed_set(pre + "Name", "Act " + string(eidx));
    ube_ed_set(pre + "Response", "* You do something.");
    ube_ed_set(pre + "Mercy", 0);
    epage = 3;
    esel = 0;
}
if (act == "delact")
{
    for (j = eidx; j < 5; j += 1)
    {
        src = "Act" + string(j + 1) + "|";
        dst = "Act" + string(j) + "|";
        ube_ed_set(dst + "Name", ube_ed_get(src + "Name"));
        ube_ed_set(dst + "Response", ube_ed_get(src + "Response"));
        ube_ed_set(dst + "Mercy", ube_ed_get(src + "Mercy"));
    }
    ube_ed_set("Act5|Name", "");
    epage = 2;
    esel = 0;
}
if (act == "addlive")
{
    eidx = atk_n + 1;
    pre = "Attack" + string(eidx) + "|";
    ube_ed_set(pre + "Pattern", "timeline");
    ube_ed_set(pre + "Duration", 240);
    ube_ed_set(pre + "BoxW", 160);
    ube_ed_set(pre + "BoxH", 135);
    ube_ed_set(pre + "Objects", 0);
    act = "golive";
}
if (act == "atk")
{
    if (ube_ed_get("Attack" + string(r_min[esel]) + "|Pattern") == "timeline")
    {
        eidx = r_min[esel];
        act = "golive";
    }
}
if (act == "golive")
{
    // Timeline attacks are edited on the large live-build screen.
    ube_ed_save(global.ube_ed_file);
    global.ube_cbl_name[global.ube_ed_i] = ube_ed_get("Boss|Name");
    ube_index_write();
    global.ube_live_idx = eidx;
    room_goto(room_ube_editor);
    exit;
}
if (act == "atk")
{
    eidx = r_min[esel];
    epage = 5;
    esel = 0;
}
if (act == "addatk")
{
    eidx = atk_n + 1;
    pre = "Attack" + string(eidx) + "|";
    ube_ed_set(pre + "Pattern", "rain");
    ube_ed_set(pre + "Count", 2);
    ube_ed_set(pre + "Speed", 3);
    ube_ed_set(pre + "Interval", 20);
    ube_ed_set(pre + "Duration", 150);
    ube_ed_set(pre + "Damage", max(1, ube_ed_get("Boss|ATK")));
    ube_ed_set(pre + "Bullet", "spr_bulletmd");
    epage = 5;
    esel = 0;
}
if (act == "delatk")
{
    for (j = eidx; j < 8; j += 1)
    {
        src = "Attack" + string(j + 1) + "|";
        dst = "Attack" + string(j) + "|";
        ube_ed_set(dst + "Pattern", ube_ed_get(src + "Pattern"));
        ube_ed_set(dst + "Count", ube_ed_get(src + "Count"));
        ube_ed_set(dst + "Speed", ube_ed_get(src + "Speed"));
        ube_ed_set(dst + "Interval", ube_ed_get(src + "Interval"));
        ube_ed_set(dst + "Duration", ube_ed_get(src + "Duration"));
        ube_ed_set(dst + "Damage", ube_ed_get(src + "Damage"));
        ube_ed_set(dst + "Bullet", ube_ed_get(src + "Bullet"));
    }
    ube_ed_set("Attack8|Pattern", "");
    epage = 4;
    esel = 0;
}
if (act == "test" || act == "lab")
{
    // Fights read the boss from its file, so testing saves first.
    ube_ed_save(global.ube_ed_file);
    global.ube_cbl_name[global.ube_ed_i] = ube_ed_get("Boss|Name");
    ube_index_write();
    global.ube_ed_pending = 1;
    global.ube_lab_pending = -1;
    global.ube_ed_rpage = 0;
    global.ube_ed_ridx = 1;
    global.ube_ed_rsel = 13;
    if (act == "lab")
    {
        global.ube_ed_pending = 2;
        global.ube_lab_pending = eidx - 1;
        global.ube_ed_rpage = 5;
        global.ube_ed_ridx = eidx;
        global.ube_ed_rsel = 7;
    }
    ube_start_encounter(1000 + global.ube_ed_i);
    exit;
}
if (act == "delete")
{
    if (del_confirm == 0)
    {
        del_confirm = 1;
        exit;
    }
    if (file_exists("custom/" + global.ube_ed_file))
    {
        file_delete("custom/" + global.ube_ed_file);
    }
    ube_log("EDITOR delete file=" + global.ube_ed_file);
    for (j = global.ube_ed_i; j < global.ube_cbl_count - 1; j += 1)
    {
        global.ube_cbl_file[j] = global.ube_cbl_file[j + 1];
        global.ube_cbl_name[j] = global.ube_cbl_name[j + 1];
    }
    global.ube_cbl_count -= 1;
    ube_index_write();
    with (obj_ube_controller)
    {
        page = 8;
        sel = 0;
        scroll = 0;
        ptimer = 0;
    }
    instance_destroy();
    exit;
}
if (act == "save")
{
    ube_ed_save(global.ube_ed_file);
    global.ube_cbl_name[global.ube_ed_i] = ube_ed_get("Boss|Name");
    ube_index_write();
    with (obj_ube_controller)
    {
        page = 8;
        sel = global.ube_ed_i;
        ptimer = 0;
    }
    instance_destroy();
}
