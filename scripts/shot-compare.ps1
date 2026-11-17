# Compares the real game's trace screenshots (real_<frame>.png) with the Godot engine's
# (godot_<frame>.png) in one folder: prints the number of differing pixels per frame and
# writes diff_<frame>.png (the real frame dimmed, differing pixels in red).
#   powershell -ExecutionPolicy Bypass -File scripts\shot-compare.ps1 -Dir logs\trace\shots_g95
param([Parameter(Mandatory = $true)][string]$Dir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('ShotDiff' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class ShotDiff {
    static int[] Pixels(Bitmap b) {
        var r = new Rectangle(0, 0, b.Width, b.Height);
        var d = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var p = new int[b.Width * b.Height];
        Marshal.Copy(d.Scan0, p, 0, p.Length);
        b.UnlockBits(d);
        return p;
    }
    // Returns the number of differing pixels and writes the diff image.
    public static int Compare(string a, string b, string outPath) {
        using (var ba = new Bitmap(a)) using (var bb = new Bitmap(b)) {
            int w = Math.Min(ba.Width, bb.Width), h = Math.Min(ba.Height, bb.Height);
            var pa = Pixels(ba); var pb = Pixels(bb);
            var o = new int[w * h];
            int n = 0;
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                int ca = pa[y * ba.Width + x] & 0xFFFFFF, cb = pb[y * bb.Width + x] & 0xFFFFFF;
                if (ca != cb) { n++; o[y * w + x] = unchecked((int)0xFFFF0000); }
                else { int g = ((ca >> 16 & 255) + (ca >> 8 & 255) + (ca & 255)) / 9; o[y * w + x] = unchecked((int)0xFF000000) | g << 16 | g << 8 | g; }
            }
            using (var bo = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                var d = bo.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                Marshal.Copy(o, 0, d.Scan0, o.Length);
                bo.UnlockBits(d);
                bo.Save(outPath, ImageFormat.Png);
            }
            return n;
        }
    }
}
'@
}
$dirFull = (Resolve-Path $Dir).Path
$total = 0; $bad = 0
foreach ($r in (Get-ChildItem $dirFull -Filter 'real_*.png' | Sort-Object { [int]($_.BaseName -replace '\D', '') })) {
    $f = [int]($r.BaseName -replace '\D', '')
    $g = Join-Path $dirFull "godot_$f.png"
    if (-not (Test-Path $g)) { Write-Host ("SHOT f={0} missing in Godot" -f $f); continue }
    $n = [ShotDiff]::Compare($r.FullName, $g, (Join-Path $dirFull "diff_$f.png"))
    $total++
    if ($n -gt 0) { $bad++ }
    Write-Host ("SHOT f={0} differing_pixels={1}" -f $f, $n)
}
Write-Host ("SHOTS compared={0} identical={1} differing={2} -> {3}" -f $total, ($total - $bad), $bad, $dirFull)
