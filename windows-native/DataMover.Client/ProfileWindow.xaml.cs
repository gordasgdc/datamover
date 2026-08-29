using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using DataMover.Core.Services;
using Wpf.Ui.Controls;
using MessageBox = System.Windows.MessageBox;

namespace DataMover.Client;

/// Wrapper de afisare peste DependencyItem (record imutabil din Core) -
/// converteste starea in ce poate lega direct XAML-ul (culoare, vizibilitate),
/// fara sa incarce modelul Core cu detalii de UI WPF.
public sealed class DependencyItemView(DependencyItem item)
{
    public string Name => item.Name;
    public string Detail => item.Detail;
    public string? DownloadUrl => item.DownloadUrl;
    public Color StatusColor => item.IsPresent ? Colors.MediumSeaGreen : Colors.OrangeRed;
    public Visibility NeedsInstallVisibility =>
        !item.IsPresent && item.DownloadUrl is not null ? Visibility.Visible : Visibility.Collapsed;
}

public partial class ProfileWindow : FluentWindow
{
    public ProfileWindow()
    {
        InitializeComponent();
        ThemeCombo.SelectedIndex = (int)ThemeSettings.Current;
        RefreshDependencies();
        Loaded += async (_, _) =>
        {
            LoadProfile();
            LoadLicenseStatus();
            VersionInfoText.Text = $"Versiune instalată: {UpdateChecker.CurrentVersion}";
            await LicenseManager.Shared.RefreshRevocationAsync();
            LoadLicenseStatus();
        };
    }

    private void RefreshDependencies() =>
        DependencyList.ItemsSource = SystemDependencyChecker.CheckAll().Select(i => new DependencyItemView(i)).ToList();

    private void OnRecheckDependenciesClicked(object sender, RoutedEventArgs e) => RefreshDependencies();

    private void OnInstallDependencyClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string url } && !string.IsNullOrEmpty(url))
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
    }

    private void OnThemeChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (ThemeCombo.SelectedIndex < 0) return;
        ThemeSettings.Apply((AppTheme)ThemeCombo.SelectedIndex);
    }

    private void LoadProfile()
    {
        var profile = UserProfileStore.Shared;
        NameBox.Text = profile.Name;
        EmailBox.Text = profile.Email;
        MachineIdBox.Text = profile.MachineId;
    }

    private void LoadLicenseStatus()
    {
        var lic = LicenseManager.Shared;
        if (lic.IsLicensed)
        {
            var expiry = lic.LicenseExpiresAt == 0
                ? "pe viață"
                : $"până la {DateTimeOffset.FromUnixTimeSeconds(lic.LicenseExpiresAt):yyyy-MM-dd}";
            LicenseStatusText.Text = $"Licențiat ({expiry}).";
        }
        else if (lic.IsTrialActive)
        {
            LicenseStatusText.Text = $"Probă gratuită — {lic.TrialDaysRemaining} zile rămase.";
        }
        else
        {
            LicenseStatusText.Text = "Proba a expirat. Activează un cod de licență mai jos.";
        }
    }

    private void OnCopyMachineIdClicked(object sender, RoutedEventArgs e) =>
        System.Windows.Clipboard.SetText(MachineIdBox.Text);

    private void OnSaveProfileClicked(object sender, RoutedEventArgs e)
    {
        UserProfileStore.Shared.Save(NameBox.Text, EmailBox.Text, sendTelemetry: true);
        MessageBox.Show("Profil salvat.", "DataMover");
    }

    private void OnActivateClicked(object sender, RoutedEventArgs e)
    {
        var code = ActivationCodeBox.Text.Trim();
        if (string.IsNullOrEmpty(code)) return;
        if (LicenseManager.Shared.Activate(code))
        {
            MessageBox.Show("Licență activată cu succes.", "DataMover");
            LoadLicenseStatus();
        }
        else
        {
            MessageBox.Show(LicenseManager.Shared.ActivationError ?? "Cod invalid.", "DataMover");
        }
    }

    private void OnRequestCodeClicked(object sender, RoutedEventArgs e)
    {
        var text = $"Salut! Vreau o licență DataMover. Machine ID: {MachineIdBox.Text}";
        var url = $"https://wa.me/34643109970?text={Uri.EscapeDataString(text)}";
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }

    private async void OnCheckUpdatesClicked(object sender, RoutedEventArgs e)
    {
        await MainWindow.CheckForUpdatesAsync(this, respectDismissal: false);
        VersionInfoText.Text = $"Versiune instalată: {UpdateChecker.CurrentVersion}";
    }
}
