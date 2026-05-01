using Azure.Messaging.ServiceBus;
using FleetFunctionApp.Models;
using FleetFunctionApp.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace FleetFunctionApp.Functions;

/// <summary>
/// Triggered by every message published to the <c>photo-upload</c> Service Bus
/// topic (subscription: <c>cloud-processor</c>).
///
/// Responsibilities:
/// <list type="number">
///   <item>Parse the upload notification.</item>
///   <item>Persist image metadata to the Cosmos DB <c>images</c> container.</item>
///   <item>Upsert the device record in the Cosmos DB <c>devices</c> container.</item>
///   <item>Send a <c>photo-processed</c> acknowledgement back to the Service Bus
///         so the Pi's file-service can delete the local copy.</item>
/// </list>
/// </summary>
public sealed class PhotoUploadFunction
{
    private readonly IFleetRepository _repository;
    private readonly ServiceBusClient _sbClient;
    private readonly ILogger<PhotoUploadFunction> _logger;

    public PhotoUploadFunction(
        IFleetRepository repository,
        ServiceBusClient sbClient,
        ILogger<PhotoUploadFunction> logger)
    {
        _repository = repository;
        _sbClient   = sbClient;
        _logger     = logger;
    }

    [Function(nameof(PhotoUploadFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger("photo-upload", "cloud-processor",
            Connection = "ServiceBusConnection")]
        string messageBody,
        FunctionContext context)
    {
        _logger.LogInformation("photo-upload message received: {Body}", messageBody);

        PhotoUploadMessage? message;
        try
        {
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            message = JsonSerializer.Deserialize<PhotoUploadMessage>(messageBody, options);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to deserialise photo-upload message body.");
            // Do not throw – a poison message should not block the queue.
            return;
        }

        if (message is null || string.IsNullOrWhiteSpace(message.FileName))
        {
            _logger.LogWarning("photo-upload message is missing required fields; skipping.");
            return;
        }

        var imageRecord = new ImageRecord
        {
            Id             = message.FileName,
            HostName       = message.HostName,
            FileName       = message.FileName,
            StorageAccount = message.StorageAccount,
            Container      = message.Container,
            UploadedAt     = DateTimeOffset.UtcNow
        };

        // Persist to Cosmos DB (image + device).
        await _repository.SaveImageAsync(imageRecord);
        await _repository.UpsertDeviceAsync(message.HostName);

        // Acknowledge back to the Pi so it can delete the local file.
        await SendAcknowledgementAsync(message.FileName);
    }

    private async Task SendAcknowledgementAsync(string fileName)
    {
        var payload = JsonSerializer.Serialize(new { file_name = fileName });
        var sender  = _sbClient.CreateSender("photo-processed");
        await using (sender.ConfigureAwait(false))
        {
            await sender.SendMessageAsync(new ServiceBusMessage(payload));
            _logger.LogInformation(
                "Sent photo-processed acknowledgement for {FileName}.", fileName);
        }
    }
}
