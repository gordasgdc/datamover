using System.Windows;
using Wpf.Ui.Controls;
using MessageBox = System.Windows.MessageBox;
using MessageBoxButton = System.Windows.MessageBoxButton;
using MessageBoxImage = System.Windows.MessageBoxImage;
using MessageBoxResult = System.Windows.MessageBoxResult;

namespace DataMover.Client;

public enum DuplicateChoice { Cancel, Resume, NewFolder, Overwrite }

/// Dialog "Reia / Folder nou / Suprascrie" (2026-08-28) - port 1:1 al
/// confirmationDialog din ContentView.swift (Mac) / _show_duplicate_dialog
/// (Python).
public partial class DuplicateDialog : FluentWindow
{
    public DuplicateChoice Result { get; private set; } = DuplicateChoice.Cancel;

    public DuplicateDialog(string existingFolderName)
    {
        InitializeComponent();
        MessageText.Text = $"Folderul \"{existingFolderName}\" exista deja si contine fisiere. Ce vrei sa faci?";
    }

    private void OnResumeClicked(object sender, RoutedEventArgs e) { Result = DuplicateChoice.Resume; Close(); }
    private void OnNewFolderClicked(object sender, RoutedEventArgs e) { Result = DuplicateChoice.NewFolder; Close(); }
    private void OnOverwriteClicked(object sender, RoutedEventArgs e)
    {
        var confirm = MessageBox.Show(
            "Sigur vrei sa stergi tot continutul existent la toate destinatiile si sa copiezi din nou?",
            "Suprascrie complet", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (confirm == MessageBoxResult.Yes) { Result = DuplicateChoice.Overwrite; Close(); }
    }
    private void OnCancelClicked(object sender, RoutedEventArgs e) { Result = DuplicateChoice.Cancel; Close(); }
}
