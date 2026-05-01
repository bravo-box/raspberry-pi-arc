using FleetWebApp.Models;
using FleetWebApp.Services;
using Microsoft.AspNetCore.Mvc;

namespace FleetWebApp.Controllers;

/// <summary>
/// Renders the fleet device dashboard.
///
/// Routes:
/// <list type="bullet">
///   <item><c>GET /</c>             — list of all registered devices</item>
///   <item><c>GET /Devices</c>      — same as above</item>
///   <item><c>GET /Devices/{hostname}</c> — image grid for a single device</item>
/// </list>
/// </summary>
public sealed class DevicesController : Controller
{
    private readonly IFleetRepository _repository;
    private readonly IBlobUrlService  _blobUrlService;
    private readonly IConfiguration   _configuration;
    private readonly ILogger<DevicesController> _logger;

    public DevicesController(
        IFleetRepository repository,
        IBlobUrlService  blobUrlService,
        IConfiguration   configuration,
        ILogger<DevicesController> logger)
    {
        _repository     = repository;
        _blobUrlService = blobUrlService;
        _configuration  = configuration;
        _logger         = logger;
    }

    // GET / or GET /Devices
    [HttpGet("/")]
    [HttpGet("/Devices")]
    public async Task<IActionResult> Index(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Loading all registered devices.");
        var devices = await _repository.GetAllDevicesAsync(cancellationToken);
        return View(devices);
    }

    // GET /Devices/{hostname}
    [HttpGet("/Devices/{hostname}")]
    public async Task<IActionResult> Details(string hostname, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(hostname))
            return BadRequest("hostname is required.");

        _logger.LogInformation("Loading images for device {Hostname}.", hostname.Replace(Environment.NewLine, string.Empty));

        var device = await _repository.GetDeviceAsync(hostname, cancellationToken);
        if (device is null)
            return NotFound($"Device '{hostname}' not found.");

        var images = await _repository.GetDeviceImagesAsync(hostname, cancellationToken);

        var photoContainer = _configuration["Storage:PhotoContainer"] ?? "photos";

        // Enrich each image record with a short-lived User Delegation SAS URL for display.
        var enriched = await Task.WhenAll(images.Select(async img =>
        {
            img.ImageUrl = await _blobUrlService.GetSasUrlAsync(
                containerName:   img.Container.Length > 0 ? img.Container : photoContainer,
                blobName:        img.FileName,
                validForMinutes: 120);
            return img;
        }));

        ViewBag.Device = device;
        return View(enriched);
    }
}
