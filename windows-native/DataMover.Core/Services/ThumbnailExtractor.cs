using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-06] Thumbnail REAL per fisier pentru raportul HTML — port 1:1
/// al `thumbnailDataURI` (Mac, QLThumbnailGenerator). Cerut de Cristi dupa
/// ce a vazut cele din raportul CG Convertor ("arata foarte pro").
///
/// Windows nu are un echivalent direct al QuickLookThumbnailing — folosim
/// COM-ul nativ al Shell-ului, <c>IShellItemImageFactory::GetImage</c>
/// (ACELASI mecanism care alimenteaza vizualizarea "Large icons"/"Extra
/// large icons" din Explorer — o previzualizare REALA a continutului:
/// cadru de video, pagina 1 de PDF, imaginea insasi — nu doar iconita
/// generica de tip fisier, spre deosebire de `ShellIcon.cs`
/// (SHGetFileInfo, folosit acolo doar pentru iconite de disc).
/// </summary>
public static class ThumbnailExtractor
{
    [ComImport]
    [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        // Membri nefolositi, dar trebuie declarati pentru vtable-ul COM corect.
        void BindToHandler();
        void GetParent();
        void GetDisplayName();
        void GetAttributes();
        void Compare();
    }

    [ComImport]
    [Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, SIIGBF flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE { public int cx; public int cy; }

    [Flags]
    private enum SIIGBF
    {
        ResizeToFit = 0x00,
        BiggerSizeOk = 0x01,
        IconOnly = 0x04,
        ThumbnailOnly = 0x08,
        InCacheOnly = 0x10,
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        string path, IntPtr pbc, in Guid riid, out IShellItemImageFactory ppv);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    private static readonly Guid ImageFactoryGuid = typeof(IShellItemImageFactory).GUID;

    /// Returneaza un JPEG mic (160x90, ~55% calitate) ca data URI, sau
    /// null daca fisierul nu are handler de thumbnail (ex. .txt/.log) sau
    /// extragerea esueaza — un raport fara thumbnail pe un rand ramane la
    /// fel de valid, doar fara previzualizare.
    public static string? ThumbnailDataUri(string path)
    {
        var bytes = ThumbnailJpegBytes(path, 160, 90);
        return bytes == null ? null : $"data:image/jpeg;base64,{Convert.ToBase64String(bytes)}";
    }

    /// [M4, 2026-09-06] Aceeasi extragere, dar octeti JPEG bruti — pentru
    /// raportul PDF (QuestPDF), care are nevoie de un `byte[]` de imagine,
    /// nu de un data URI HTML. Cod comun extras din `ThumbnailDataUri`.
    public static byte[]? ThumbnailJpegBytes(string path, int width, int height)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return null;
        IntPtr hBitmap = IntPtr.Zero;
        try
        {
            SHCreateItemFromParsingName(path, IntPtr.Zero, ImageFactoryGuid, out var factory);
            var hr = factory.GetImage(new SIZE { cx = width, cy = height },
                SIIGBF.ThumbnailOnly | SIIGBF.BiggerSizeOk, out hBitmap);
            if (hr != 0 || hBitmap == IntPtr.Zero) return null;

            using var bitmap = Image.FromHbitmap(hBitmap);
            using var ms = new MemoryStream();
            var jpegEncoder = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
            using var encParams = new EncoderParameters(1);
            encParams.Param[0] = new EncoderParameter(Encoder.Quality, 60L);
            bitmap.Save(ms, jpegEncoder, encParams);
            return ms.ToArray();
        }
        catch
        {
            // COM/GDI poate esua pe un fisier corupt/blocat/fara handler
            // inregistrat - un thumbnail lipsa nu trebuie sa opreasca
            // generarea restului raportului.
            return null;
        }
        finally
        {
            if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
        }
    }
}
