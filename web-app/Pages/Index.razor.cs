using Microsoft.AspNetCore.Components;
using WebApp.Models;
using WebApp.Services;

namespace WebApp.Pages;

public partial class Index : ComponentBase, IDisposable
{
    [Inject] private ICosmosDbService CosmosDb { get; set; } = null!;
    [Inject] private IStorageService Storage { get; set; } = null!;
    [Inject] private IServiceBusService ServiceBus { get; set; } = null!;

    protected List<Device> _devices = new();
    protected List<TelemetryRecord> _telemetry = new();
    protected List<ImageRecord> _images = new();
    protected Device? _selectedDevice;
    protected bool _loadingFleet;
    protected bool _loadingTelemetry;
    protected bool _loadingImages;
    protected bool _sendingCommand;
    protected string? _commandFeedback;
    protected string _commandFeedbackClass = string.Empty;
    protected int _refreshCountdown = 30;

    private System.Threading.Timer? _refreshTimer;
    private System.Threading.Timer? _countdownTimer;

    protected override async Task OnInitializedAsync()
    {
        await LoadFleetAsync();
        StartRefreshTimers();
    }

    protected async Task LoadFleetAsync()
    {
        _loadingFleet = true;
        StateHasChanged();
        try
        {
            var result = await CosmosDb.GetAllDevicesAsync();
            _devices = result
                .OrderByDescending(d => d.IsHealthy)
                .ThenBy(d => d.Hostname)
                .ToList();
        }
        finally
        {
            _loadingFleet = false;
        }
    }

    protected async Task SelectDevice(Device device)
    {
        _selectedDevice = device;
        _telemetry.Clear();
        _images.Clear();
        _commandFeedback = null;
        StateHasChanged();
        await Task.WhenAll(
            LoadTelemetryAsync(device.AssetId),
            LoadImagesAsync(device.AssetId));
    }

    private async Task LoadTelemetryAsync(string assetId)
    {
        _loadingTelemetry = true;
        StateHasChanged();
        try
        {
            var result = await CosmosDb.GetTelemetryAsync(assetId, 50);
            _telemetry = result.OrderBy(t => t.Timestamp).ToList();
        }
        finally
        {
            _loadingTelemetry = false;
            StateHasChanged();
        }
    }

    private async Task LoadImagesAsync(string assetId)
    {
        _loadingImages = true;
        StateHasChanged();
        try
        {
            _images = (await CosmosDb.GetImagesAsync(assetId)).ToList();
        }
        finally
        {
            _loadingImages = false;
            StateHasChanged();
        }
    }

    protected async Task TakePicture()
    {
        if (_selectedDevice is null) return;
        _sendingCommand = true;
        _commandFeedback = null;
        StateHasChanged();
        try
        {
            await ServiceBus.SendTakePictureCommandAsync(_selectedDevice.AssetId);
            _commandFeedback = "\u2713 COMMAND TRANSMITTED";
            _commandFeedbackClass = "feedback-ok";
        }
        catch
        {
            _commandFeedback = "\u2717 TRANSMISSION FAILED";
            _commandFeedbackClass = "feedback-err";
        }
        finally
        {
            _sendingCommand = false;
            StateHasChanged();
        }
    }

    private void StartRefreshTimers()
    {
        _countdownTimer = new System.Threading.Timer(_ =>
        {
            _refreshCountdown--;
            if (_refreshCountdown <= 0) _refreshCountdown = 30;
            InvokeAsync(StateHasChanged);
        }, null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));

        _refreshTimer = new System.Threading.Timer(async _ =>
        {
            await InvokeAsync(async () =>
            {
                await LoadFleetAsync();
                _refreshCountdown = 30;
                if (_selectedDevice is not null)
                {
                    var updated = _devices.FirstOrDefault(d => d.AssetId == _selectedDevice.AssetId);
                    if (updated is not null) _selectedDevice = updated;
                }
                StateHasChanged();
            });
        }, null, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(30));
    }

    protected bool IsSelected(Device d) => _selectedDevice?.AssetId == d.AssetId;

    protected static string TruncateId(string id) =>
        id.Length > 12 ? id[..8] + "..." : id;

    protected MarkupString BuildTemperatureChart()
    {
        const int svgWidth = 700;
        const int svgHeight = 200;
        const int padLeft = 50;
        const int padRight = 20;
        const int padTop = 15;
        const int padBottom = 35;
        int chartW = svgWidth - padLeft - padRight;
        int chartH = svgHeight - padTop - padBottom;

        var temps = _telemetry.Select(t => t.Temperature).ToList();
        if (temps.Count == 0) return new MarkupString(string.Empty);

        double minT = temps.Min() - 1;
        double maxT = temps.Max() + 1;
        double rangeT = maxT - minT;
        if (rangeT < 0.001) rangeT = 1;

        int n = temps.Count;
        double ScaleX(int i) => padLeft + (n > 1 ? (double)i / (n - 1) * chartW : chartW / 2.0);
        double ScaleY(double t) => padTop + chartH - ((t - minT) / rangeT * chartH);

        var sb = new System.Text.StringBuilder();
        sb.Append($"<svg width=\"100%\" viewBox=\"0 0 {svgWidth} {svgHeight}\" xmlns=\"http://www.w3.org/2000/svg\">");
        sb.Append($"<rect width=\"{svgWidth}\" height=\"{svgHeight}\" fill=\"#070b14\" rx=\"4\"/>");

        // Grid lines
        for (int g = 0; g <= 4; g++)
        {
            double y = padTop + (double)g / 4 * chartH;
            double tempVal = maxT - (double)g / 4 * rangeT;
            sb.Append($"<line x1=\"{padLeft}\" y1=\"{y:F1}\" x2=\"{padLeft + chartW}\" y2=\"{y:F1}\" stroke=\"#1e3a5f\" stroke-width=\"1\"/>");
            sb.Append($"<text x=\"{padLeft - 5}\" y=\"{y + 4:F1}\" fill=\"#a0c4e8\" font-size=\"10\" text-anchor=\"end\" font-family=\"monospace\">{tempVal:F1}\u00b0</text>");
        }

        // Axes
        sb.Append($"<line x1=\"{padLeft}\" y1=\"{padTop}\" x2=\"{padLeft}\" y2=\"{padTop + chartH}\" stroke=\"#1e3a5f\" stroke-width=\"1\"/>");
        sb.Append($"<line x1=\"{padLeft}\" y1=\"{padTop + chartH}\" x2=\"{padLeft + chartW}\" y2=\"{padTop + chartH}\" stroke=\"#1e3a5f\" stroke-width=\"1\"/>");

        // Y-axis label
        double midY = padTop + chartH / 2.0;
        sb.Append($"<text x=\"{padLeft - 40}\" y=\"{midY:F1}\" fill=\"#00c8ff\" font-size=\"10\" text-anchor=\"middle\" transform=\"rotate(-90,{padLeft - 40},{midY:F1})\" font-family=\"monospace\">\u00b0C</text>");

        // Polyline
        string points = string.Join(" ", temps.Select((t, i) => $"{ScaleX(i):F1},{ScaleY(t):F1}"));
        sb.Append($"<polyline points=\"{points}\" fill=\"none\" stroke=\"#00c8ff\" stroke-width=\"2\" stroke-linejoin=\"round\"/>");

        // Data point dots
        for (int i = 0; i < n; i++)
            sb.Append($"<circle cx=\"{ScaleX(i):F1}\" cy=\"{ScaleY(temps[i]):F1}\" r=\"3\" fill=\"#00ff88\"/>");

        // X-axis time labels: first, mid, last — deduplicated for small datasets
        var labelIndices = new List<int> { 0 };
        if (n > 2) labelIndices.Add(n / 2);
        if (n > 1) labelIndices.Add(n - 1);
        foreach (var i in labelIndices)
        {
            double x = ScaleX(i);
            string label = _telemetry[i].Timestamp.ToString("HH:mm");
            sb.Append($"<text x=\"{x:F1}\" y=\"{svgHeight - 5}\" fill=\"#a0c4e8\" font-size=\"10\" text-anchor=\"middle\" font-family=\"monospace\">{label}</text>");
        }

        sb.Append("</svg>");
        return new MarkupString(sb.ToString());
    }

    public void Dispose()
    {
        _refreshTimer?.Dispose();
        _countdownTimer?.Dispose();
    }
}
