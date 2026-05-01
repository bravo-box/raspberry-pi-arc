using FleetWebApp.Controllers;
using FleetWebApp.Models;
using FleetWebApp.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FleetWebApp.Tests.Controllers;

public sealed class DevicesControllerTests
{
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static IConfiguration EmptyConfig() =>
        new ConfigurationBuilder().Build();

    private static DevicesController BuildController(
        IFleetRepository? repo    = null,
        IBlobUrlService?  blobSvc = null,
        IConfiguration?   config  = null)
    {
        return new DevicesController(
            repo    ?? Mock.Of<IFleetRepository>(),
            blobSvc ?? Mock.Of<IBlobUrlService>(),
            config  ?? EmptyConfig(),
            NullLogger<DevicesController>.Instance);
    }

    // ------------------------------------------------------------------
    // Index
    // ------------------------------------------------------------------

    [Fact]
    public async Task Index_ReturnsViewWithAllDevices()
    {
        var devices = new List<Device>
        {
            new() { Id = "pi1", Hostname = "pi1", ImageCount = 5 },
            new() { Id = "pi2", Hostname = "pi2", ImageCount = 3 }
        };

        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetAllDevicesAsync(default)).ReturnsAsync(devices);

        var controller = BuildController(repo: mockRepo.Object);

        var result = await controller.Index(CancellationToken.None);

        var view  = Assert.IsType<ViewResult>(result);
        var model = Assert.IsAssignableFrom<IEnumerable<Device>>(view.Model);
        Assert.Equal(2, model.Count());
    }

    [Fact]
    public async Task Index_EmptyFleet_ReturnsViewWithEmptyList()
    {
        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetAllDevicesAsync(default))
                .ReturnsAsync(Array.Empty<Device>());

        var controller = BuildController(repo: mockRepo.Object);

        var result = await controller.Index(CancellationToken.None);

        var view  = Assert.IsType<ViewResult>(result);
        var model = Assert.IsAssignableFrom<IEnumerable<Device>>(view.Model);
        Assert.Empty(model);
    }

    // ------------------------------------------------------------------
    // Details
    // ------------------------------------------------------------------

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Details_EmptyOrWhitespaceHostname_ReturnsBadRequest(string hostname)
    {
        var controller = BuildController();

        var result = await controller.Details(hostname, CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task Details_UnknownHostname_ReturnsNotFound()
    {
        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetDeviceAsync("ghost", default))
                .ReturnsAsync((Device?)null);

        var controller = BuildController(repo: mockRepo.Object);

        var result = await controller.Details("ghost", CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task Details_KnownHostname_ReturnsViewWithEnrichedImages()
    {
        const string hostname  = "pi1";
        const string fakeSasUrl = "https://example.blob.core.windows.net/photos/img.jpg?sv=2020";

        var device = new Device { Id = hostname, Hostname = hostname, ImageCount = 1 };
        var images = new List<DeviceImage>
        {
            new() { Id = "img1.jpg", HostName = hostname, FileName = "img1.jpg", Container = "photos" }
        };

        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetDeviceAsync(hostname, default)).ReturnsAsync(device);
        mockRepo.Setup(r => r.GetDeviceImagesAsync(hostname, default)).ReturnsAsync(images);

        var mockBlob = new Mock<IBlobUrlService>();
        mockBlob.Setup(b => b.GetSasUrlAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()))
                .ReturnsAsync(fakeSasUrl);

        var controller = BuildController(repo: mockRepo.Object, blobSvc: mockBlob.Object);

        var result = await controller.Details(hostname, CancellationToken.None);

        var view  = Assert.IsType<ViewResult>(result);
        var model = Assert.IsAssignableFrom<IEnumerable<DeviceImage>>(view.Model);
        var img   = Assert.Single(model);
        Assert.Equal(fakeSasUrl, img.ImageUrl);
    }

    [Fact]
    public async Task Details_KnownHostname_SetsDeviceInViewBag()
    {
        const string hostname = "pi1";
        var device = new Device { Id = hostname, Hostname = hostname };

        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetDeviceAsync(hostname, default)).ReturnsAsync(device);
        mockRepo.Setup(r => r.GetDeviceImagesAsync(hostname, default))
                .ReturnsAsync(Array.Empty<DeviceImage>());

        var mockBlob = new Mock<IBlobUrlService>();

        var controller = BuildController(repo: mockRepo.Object, blobSvc: mockBlob.Object);

        var result = await controller.Details(hostname, CancellationToken.None);

        var view = Assert.IsType<ViewResult>(result);
        var viewBagDevice = (Device?)controller.ViewBag.Device;
        Assert.NotNull(viewBagDevice);
        Assert.Equal(hostname, viewBagDevice!.Hostname);
    }

    [Fact]
    public async Task Details_MultipleImages_AllEnrichedWithSasUrl()
    {
        const string hostname = "pi1";
        var device  = new Device { Id = hostname, Hostname = hostname };
        var images  = Enumerable.Range(1, 3).Select(i => new DeviceImage
        {
            Id       = $"img{i}.jpg",
            HostName = hostname,
            FileName = $"img{i}.jpg",
            Container = "photos"
        }).ToList();

        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetDeviceAsync(hostname, default)).ReturnsAsync(device);
        mockRepo.Setup(r => r.GetDeviceImagesAsync(hostname, default)).ReturnsAsync(images);

        var mockBlob = new Mock<IBlobUrlService>();
        mockBlob.Setup(b => b.GetSasUrlAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()))
                .ReturnsAsync((string container, string blob, int _) =>
                    $"https://example.blob.core.windows.net/{container}/{blob}?sas=token");

        var controller = BuildController(repo: mockRepo.Object, blobSvc: mockBlob.Object);

        var result = await controller.Details(hostname, CancellationToken.None);

        var view  = Assert.IsType<ViewResult>(result);
        var model = Assert.IsAssignableFrom<IEnumerable<DeviceImage>>(view.Model).ToList();

        Assert.Equal(3, model.Count);
        Assert.All(model, img => Assert.False(string.IsNullOrEmpty(img.ImageUrl)));
    }

    [Fact]
    public async Task Details_ImageWithEmptyContainer_FallsBackToConfiguredContainer()
    {
        const string hostname = "pi1";
        var device = new Device { Id = hostname, Hostname = hostname };
        var images = new List<DeviceImage>
        {
            new() { FileName = "img.jpg", HostName = hostname, Container = "" }
        };

        var mockRepo = new Mock<IFleetRepository>();
        mockRepo.Setup(r => r.GetDeviceAsync(hostname, default)).ReturnsAsync(device);
        mockRepo.Setup(r => r.GetDeviceImagesAsync(hostname, default)).ReturnsAsync(images);

        string? capturedContainer = null;
        var mockBlob = new Mock<IBlobUrlService>();
        mockBlob.Setup(b => b.GetSasUrlAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()))
                .Callback<string, string, int>((c, _, _) => capturedContainer = c)
                .ReturnsAsync("https://dummy");

        // Provide config with a custom default container name
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Storage:PhotoContainer"] = "fleet-photos" })
            .Build();

        var controller = BuildController(repo: mockRepo.Object, blobSvc: mockBlob.Object, config: config);
        await controller.Details(hostname, CancellationToken.None);

        Assert.Equal("fleet-photos", capturedContainer);
    }
}
