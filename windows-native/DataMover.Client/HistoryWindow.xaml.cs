using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using DataMover.Core.Services;
using Wpf.Ui.Controls;
using MessageBox = System.Windows.MessageBox;
using MessageBoxButton = System.Windows.MessageBoxButton;
using MessageBoxImage = System.Windows.MessageBoxImage;
using MessageBoxResult = System.Windows.MessageBoxResult;

namespace DataMover.Client;

/// Istoric extins (2026-08-28) - sursa/destinatie complete + deschidere
/// directa in Explorer. Port 1:1 al HistoryView.swift (Mac).
public partial class HistoryWindow : FluentWindow
{
    public HistoryWindow()
    {
        InitializeComponent();
        Reload();
    }

    private void Reload() => HistoryList.ItemsSource = HistoryStore.Shared.Entries.AsEnumerable().Reverse().ToList();

    private static void OpenInExplorer(string? path)
    {
        if (string.IsNullOrEmpty(path) || !System.IO.Directory.Exists(path))
        {
            MessageBox.Show("Acest folder nu mai exista sau sesiunea e prea veche pentru a avea calea salvata.",
                "DataMover", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }

    private void OnOpenSourceClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).Tag is HistoryEntry entry)
            OpenInExplorer(entry.SourcePaths.FirstOrDefault());
    }

    private void OnOpenDestinationClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).Tag is HistoryEntry entry)
            foreach (var path in entry.DestinationTargetPaths)
                OpenInExplorer(path);
    }

    private void OnClearAllClicked(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Sigur vrei sa stergi tot istoricul?", "DataMover",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
        {
            HistoryStore.Shared.ClearAll();
            Reload();
        }
    }

    private void OnCloseClicked(object sender, RoutedEventArgs e) => Close();
}
