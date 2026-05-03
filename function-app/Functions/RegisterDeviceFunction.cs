using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using FleetFunctionApp.Models;
using FleetFunctionApp.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace FleetFunctionApp.Functions;

/// <summary>
/// Triggered by every message published to the <c>register-device</c> Service
/// Bus topic (subscription: <c>registration-function</c>).
///
/// Responsibilities:
/// <list type="number">
///   <item>Parse the registration request containing the device hostname.</item>
///   <item>Create or update the device record in Cosmos DB and obtain a stable
///         GUID for the device.</item>
///   <item>Ensure a per-device blob container exists in Azure Storage (named
///         after the normalised hostname).</item>
///   <item>Publish a <c>device-registered</c> response containing the hostname
///         and assigned device GUID back to the Pi's registration-service.</item>
/// </list>
/// </summary>
public sealed class RegisterDeviceFunction
{
    private readonly IFleetRepository _repository;
    private readonly ServiceBusClient _sbClient;
    private readonly BlobServiceClient _blobClient;
    private readonly ILogger<RegisterDeviceFunction> _logger;

    public RegisterDeviceFunction(
        IFleetRepository repository,
        ServiceBusClient sbClient,
        BlobServiceClient blobClient,
        ILogger<RegisterDeviceFunction> logger)
    {
        _repository = repository;
        _sbClient   = sbClient;
        _blobClient = blobClient;
        _logger     = logger;
    }

    [Function(nameof(RegisterDeviceFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger("register-device", "registration-function",
            Connection = "ServiceBusConnection")]
        string messageBody,
        FunctionContext context)
    {
        _logger.LogInformation("register-device message received: {Body}", messageBody);

        RegisterDeviceMessage? message;
        try
        {
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            message = JsonSerializer.Deserialize<RegisterDeviceMessage>(messageBody, options);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to deserialise register-device message body.");
            return;
        }

        if (message is null || string.IsNullOrWhiteSpace(message.Hostname))
        {
            _logger.LogWarning("register-device message is missing the hostname field; skipping.");
            return;
        }

        var hostname = message.Hostname;

        // 1. Persist / retrieve the device record and its GUID.
        var deviceId = await _repository.RegisterDeviceAsync(hostname);

        // 2. Ensure a dedicated blob container exists for this device's images.
        await EnsureDeviceContainerAsync(hostname);

        // 3. Reply to the Pi with the assigned device ID.
        await SendRegisteredResponseAsync(hostname, deviceId);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// <summary>
    /// Creates a blob container whose name is derived from the device hostname.
    /// Azure Storage container names must be lowercase, 3-63 characters, and
    /// may only contain letters, numbers, and hyphens.
    /// </summary>
    private async Task EnsureDeviceContainerAsync(string hostname)
    {
        var containerName = NormaliseContainerName(hostname);
        var containerClient = _blobClient.GetBlobContainerClient(containerName);
        var created = await containerClient.CreateIfNotExistsAsync();

        if (created?.Value is not null)
            _logger.LogInformation(
                "Created blob container '{ContainerName}' for device '{Hostname}'.",
                containerName, hostname);
        else
            _logger.LogInformation(
                "Blob container '{ContainerName}' for device '{Hostname}' already exists.",
                containerName, hostname);
    }

    private async Task SendRegisteredResponseAsync(string hostname, string deviceId)
    {
        var payload = JsonSerializer.Serialize(new DeviceRegisteredMessage
        {
            Hostname = hostname,
            DeviceId = deviceId
        });

        var sender = _sbClient.CreateSender("device-registered");
        await using (sender.ConfigureAwait(false))
        {
            await sender.SendMessageAsync(new ServiceBusMessage(payload));
            _logger.LogInformation(
                "Sent device-registered response for {Hostname} with DeviceId {DeviceId}.",
                hostname, deviceId);
        }
    }

    /// <summary>
    /// Normalises a hostname into a valid Azure Blob Storage container name:
    /// lowercase, alphanumeric and hyphens only, max 63 characters.
    /// </summary>
    public static string NormaliseContainerName(string hostname)
    {
        var lower = hostname.ToLowerInvariant();
        // Replace any character that is not a letter, digit, or hyphen with a hyphen.
        var normalised = Regex.Replace(lower, @"[^a-z0-9\-]", "-");
        // Collapse consecutive hyphens.
        normalised = Regex.Replace(normalised, @"-{2,}", "-");
        // Trim leading/trailing hyphens.
        normalised = normalised.Trim('-');
        // Enforce length constraints (3–63 characters).
        if (normalised.Length < 3)
            normalised = normalised.PadRight(3, '0');
        if (normalised.Length > 63)
            normalised = normalised[..63].TrimEnd('-');
        return normalised;
    }
}
