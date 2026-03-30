using System.Diagnostics;
using System.IO;
using System.Windows;
using MarsinDictation.Core.Settings;

namespace MarsinDictation.App.UI;

public partial class ModelDownloadWindow : Window
{
    private readonly ModelDownloader _downloader;
    private readonly CancellationTokenSource _cts = new();
    private readonly string _modelName;
    private readonly string _targetPath;

    public bool WasSkipped { get; private set; }

    public ModelDownloadWindow(string modelName, string targetPath)
    {
        InitializeComponent();
        
        _modelName = modelName;
        _targetPath = targetPath;
        _downloader = new ModelDownloader();
        _downloader.ProgressChanged += OnProgressChanged;

        MessageText.Text = $"MarsinDictation needs to download the local speech model ({modelName}) for offline transcription.";
        
        Loaded += OnLoaded;
        Closing += OnClosing;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await _downloader.DownloadModelAsync(_modelName, _targetPath, _cts.Token);
            
            // Finished successfully
            DialogResult = true;
            Close();
        }
        catch (OperationCanceledException)
        {
            // Expected if canceled
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to download model:\n{ex.Message}", "Download Error", MessageBoxButton.OK, MessageBoxImage.Error);
            DialogResult = false;
        }
    }

    private void OnProgressChanged(long bytesRead, long? totalBytes)
    {
        // Must update UI on Dispatcher thread
        Dispatcher.Invoke(() =>
        {
            var downloadedMb = bytesRead / 1024.0 / 1024.0;
            
            if (totalBytes.HasValue)
            {
                var totalMb = totalBytes.Value / 1024.0 / 1024.0;
                var percent = (double)bytesRead / totalBytes.Value * 100.0;
                
                DownloadProgress.Value = percent;
                DownloadProgress.IsIndeterminate = false;
                ProgressText.Text = $"{downloadedMb:F1} MB / {totalMb:F1} MB ({percent:F0}%)";
            }
            else
            {
                DownloadProgress.IsIndeterminate = true;
                ProgressText.Text = $"{downloadedMb:F1} MB downloaded...";
            }
        });
    }

    private void OnSkipClicked(object sender, RoutedEventArgs e)
    {
        WasSkipped = true;
        _cts.Cancel();
        DialogResult = false;
        Close();
    }

    private void OnCancelClicked(object sender, RoutedEventArgs e)
    {
        _cts.Cancel();
        DialogResult = false;
        Close();
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        _downloader.ProgressChanged -= OnProgressChanged;
        // Ensure download stops if window is closed via X button
        if (!_cts.IsCancellationRequested)
        {
            _cts.Cancel();
        }
    }
}
