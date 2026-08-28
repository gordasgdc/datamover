using System.Windows;

namespace DataMover.Client;

/// Fereastra minimala de progres cat dureaza descarcarea/instalarea unui
/// update (Regula 20, CLAUDE.md) - Window simplu, NU ui:FluentWindow
/// (tranzitorie, fara nevoie de TitleBar/drag).
public partial class UpdateProgressWindow : Window
{
    public UpdateProgressWindow(string version)
    {
        InitializeComponent();
        Title = $"Actualizare DataMover {version}";
    }

    public void SetStatus(string text) => Dispatcher.Invoke(() => StatusLabel.Text = text);
}
