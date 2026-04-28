using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using Microsoft.Azure.Cosmos;
using WebApp.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();
builder.Services.AddServerSideBlazor();

var credential = new DefaultAzureCredential();

// Cosmos DB
var cosmosEndpoint = builder.Configuration["CosmosDb:Endpoint"]
    ?? throw new InvalidOperationException("CosmosDb:Endpoint is required");
builder.Services.AddSingleton(_ => new CosmosClient(cosmosEndpoint, credential));
builder.Services.AddSingleton<ICosmosDbService, CosmosDbService>();

// Azure Blob Storage
var storageAccountUrl = builder.Configuration["Storage:AccountUrl"]
    ?? throw new InvalidOperationException("Storage:AccountUrl is required");
builder.Services.AddSingleton(_ => new BlobServiceClient(new Uri(storageAccountUrl), credential));
builder.Services.AddSingleton<IStorageService, StorageService>();

// Azure Service Bus
var serviceBusNamespace = builder.Configuration["ServiceBus:FullyQualifiedNamespace"]
    ?? throw new InvalidOperationException("ServiceBus:FullyQualifiedNamespace is required");
builder.Services.AddSingleton(_ => new ServiceBusClient(serviceBusNamespace, credential));
builder.Services.AddSingleton<IServiceBusService, ServiceBusService>();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseStaticFiles();
app.UseRouting();

app.MapBlazorHub();
app.MapFallbackToPage("/_Host");

app.Run();
