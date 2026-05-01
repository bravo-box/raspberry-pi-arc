using Azure.Identity;
using Azure.Storage.Blobs;
using FleetWebApp.Services;
using Microsoft.Azure.Cosmos;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// MVC
// ---------------------------------------------------------------------------
builder.Services.AddControllersWithViews();

// ---------------------------------------------------------------------------
// Cosmos DB (singleton – thread-safe, expensive to construct)
// ---------------------------------------------------------------------------
builder.Services.AddSingleton(sp =>
{
    var cfg      = sp.GetRequiredService<IConfiguration>();
    var endpoint = cfg["CosmosDb:Endpoint"]
        ?? throw new InvalidOperationException("CosmosDb:Endpoint is required.");
    var key      = cfg["CosmosDb:AccountKey"]
        ?? throw new InvalidOperationException("CosmosDb:AccountKey is required.");

    return new CosmosClient(endpoint, key, new CosmosClientOptions
    {
        SerializerOptions = new CosmosSerializationOptions
        {
            PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
        }
    });
});

// ---------------------------------------------------------------------------
// Azure Blob Storage – accessed via system-assigned managed identity.
// In App Service the managed identity is used automatically; locally the
// DefaultAzureCredential falls back to the Azure CLI credential.
// No storage account key is required.
// ---------------------------------------------------------------------------
builder.Services.AddSingleton(sp =>
{
    var cfg         = sp.GetRequiredService<IConfiguration>();
    var accountName = cfg["Storage:AccountName"]
        ?? throw new InvalidOperationException("Storage:AccountName is required.");

    // Azure Government storage endpoint
    var blobEndpoint = new Uri($"https://{accountName}.blob.core.usgovcloudapi.net");
    return new BlobServiceClient(blobEndpoint, new DefaultAzureCredential());
});

// ---------------------------------------------------------------------------
// Application services
// ---------------------------------------------------------------------------
builder.Services.AddSingleton<IFleetRepository, CosmosFleetRepository>();
builder.Services.AddSingleton<IBlobUrlService>(sp =>
{
    var cfg         = sp.GetRequiredService<IConfiguration>();
    var accountName = cfg["Storage:AccountName"]
        ?? throw new InvalidOperationException("Storage:AccountName is required.");
    return new BlobUrlService(
        sp.GetRequiredService<BlobServiceClient>(),
        accountName,
        sp.GetRequiredService<ILogger<BlobUrlService>>());
});

// ---------------------------------------------------------------------------
// Build & run
// ---------------------------------------------------------------------------
var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Devices}/{action=Index}/{id?}");

app.Run();
