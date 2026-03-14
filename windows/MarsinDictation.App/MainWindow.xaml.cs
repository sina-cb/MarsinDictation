using System.ComponentModel;
using System.Windows;

namespace MarsinDictation.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    /// <summary>
    /// When the user closes the settings window, hide it instead of exiting the app.
    /// The app stays running in the tray.
    /// </summary>
    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        this.Hide();
    }
}
