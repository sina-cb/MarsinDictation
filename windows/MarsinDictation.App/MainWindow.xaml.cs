using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using MarsinDictation.Core.Settings;

namespace MarsinDictation.App;

public partial class MainWindow : Window
{
    private readonly SettingsManager? _settingsManager;

    public MainWindow()
    {
        InitializeComponent();
    }

    public MainWindow(SettingsManager settingsManager) : this()
    {
        _settingsManager = settingsManager;
        LoadSettingsToUI();
    }

    private void LoadSettingsToUI()
    {
        if (_settingsManager == null) return;
        var s = _settingsManager.Settings;

        if (s.TranscriptionProvider == "openai") RadioOpenAI.IsChecked = true;
        else if (s.TranscriptionProvider == "localai") RadioLocalAI.IsChecked = true;
        else RadioEmbedded.IsChecked = true;

        TxtWhisperModel.Text = s.WhisperModel;
        TxtLocalAIEndpoint.Text = s.LocalAIEndpoint;
        TxtLocalAIModel.Text = s.LocalAIModel;
        
        TxtOpenAIKey.Password = Environment.GetEnvironmentVariable("OPENAI_API_KEY") ?? "";
        
        foreach (ComboBoxItem item in ComboOpenAIModel.Items)
        {
            if (item.Content.ToString() == s.OpenAIModel)
            {
                ComboOpenAIModel.SelectedItem = item;
                break;
            }
        }
        
        TxtLanguage.Text = s.Language;
        UpdatePanels();
    }

    private void Provider_Checked(object sender, RoutedEventArgs e)
    {
        UpdatePanels();
    }

    private void UpdatePanels()
    {
        if (PanelEmbedded == null || PanelLocalAI == null || PanelOpenAI == null) return;

        PanelEmbedded.Visibility = RadioEmbedded.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PanelLocalAI.Visibility = RadioLocalAI.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PanelOpenAI.Visibility = RadioOpenAI.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void BtnApply_Click(object sender, RoutedEventArgs e)
    {
        if (_settingsManager == null) return;
        var s = _settingsManager.Settings;

        if (RadioOpenAI.IsChecked == true) s.TranscriptionProvider = "openai";
        else if (RadioLocalAI.IsChecked == true) s.TranscriptionProvider = "localai";
        else s.TranscriptionProvider = "embedded";

        s.WhisperModel = TxtWhisperModel.Text;
        s.LocalAIEndpoint = TxtLocalAIEndpoint.Text;
        s.LocalAIModel = TxtLocalAIModel.Text;

        if (ComboOpenAIModel.SelectedItem is ComboBoxItem cbi)
        {
            s.OpenAIModel = cbi.Content.ToString() ?? "gpt-4o-mini-transcribe";
        }

        s.Language = TxtLanguage.Text;

        _settingsManager.Save();
        
        // Temporarily set env var for OpenAI API key to make it available to OpenAITranscriptionClient during current run
        // In a real app we'd use DPAPI SecretStore, replacing .env. For now, environment is enough since
        // the App reads from Environment.GetEnvironmentVariable("OPENAI_API_KEY").
        var key = TxtOpenAIKey.Password;
        if (!string.IsNullOrWhiteSpace(key))
        {
            Environment.SetEnvironmentVariable("OPENAI_API_KEY", key, EnvironmentVariableTarget.User);
            Environment.SetEnvironmentVariable("OPENAI_API_KEY", key, EnvironmentVariableTarget.Process);
        }

        TxtStatus.Visibility = Visibility.Visible;
        await Task.Delay(2000);
        TxtStatus.Visibility = Visibility.Hidden;
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
