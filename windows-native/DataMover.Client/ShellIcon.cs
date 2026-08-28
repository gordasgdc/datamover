using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace DataMover.Client;

/// <summary>
/// Iconita NATIVA Windows pentru un disc/volum (aceeasi pe care o arata
/// Explorer) - via Shell32 SHGetFileInfo, nu o pictograma desenata de noi.
/// Cerut explicit de Cristi (2026-08-28): "sa apara imaginea, iconitele,
/// simbolurile de la hard disk-uri, asa cum sunt prezentate in Windows".
/// Fara dependinta System.Drawing - HICON e convertit direct in
/// BitmapSource prin Imaging.CreateBitmapSourceFromHIcon.
/// </summary>
public static class ShellIcon
{
    [StructLayout(LayoutKind.Sequential)]
    private struct SHFILEINFO
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string szTypeName;
    }

    private const uint SHGFI_ICON = 0x100;
    private const uint SHGFI_LARGEICON = 0x0;

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr hIcon);

    /// Returneaza iconita reala a discului (litera de drive, ex. "D:\") sau
    /// null daca Shell32 nu poate rezolva calea (ex. card scos intre timp).
    public static BitmapSource? GetDriveIcon(string rootPath)
    {
        try
        {
            var shinfo = new SHFILEINFO();
            var result = SHGetFileInfo(rootPath, 0, ref shinfo, (uint)Marshal.SizeOf(shinfo), SHGFI_ICON | SHGFI_LARGEICON);
            if (result == IntPtr.Zero || shinfo.hIcon == IntPtr.Zero) return null;
            try
            {
                var src = Imaging.CreateBitmapSourceFromHIcon(shinfo.hIcon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                src.Freeze();
                return src;
            }
            finally { DestroyIcon(shinfo.hIcon); }
        }
        catch { return null; }
    }
}
