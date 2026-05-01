using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

namespace FleetWebApp.Services;

/// <summary>
/// Azure Blob Storage implementation of <see cref="IBlobUrlService"/>.
///
/// Generates time-limited, read-only <em>User Delegation SAS</em> URLs.  The
/// underlying <c>UserDelegationKey</c> is obtained via the application's
/// system-assigned managed identity (<c>Storage Blob Data Delegator</c> role)
/// and is cached in memory, refreshed automatically before it expires or when
/// an individual SAS would outlive the cached key.
///
/// No storage account key is required at runtime.
/// </summary>
public sealed class BlobUrlService : IBlobUrlService, IDisposable
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly string _accountName;
    private readonly ILogger<BlobUrlService> _logger;
    private readonly SemaphoreSlim _keyLock = new(1, 1);

    // Thread-safety: key+expiry are stored together as a single immutable record so
    // the fast-path read (performed without holding the lock) always sees a consistent pair.
    private volatile CachedKey? _cached;

    // Re-fetch the delegation key when it is within this many minutes of expiry.
    private const int KeyRefreshMarginMinutes = 10;

    private sealed record CachedKey(UserDelegationKey Key, DateTimeOffset ExpiresOn);

    public BlobUrlService(
        BlobServiceClient blobServiceClient,
        string accountName,
        ILogger<BlobUrlService> logger)
    {
        _blobServiceClient = blobServiceClient;
        _accountName       = accountName;
        _logger            = logger;
    }

    public async Task<string> GetSasUrlAsync(
        string containerName, string blobName, int validForMinutes = 60)
    {
        var delegationKey = await GetOrRefreshDelegationKeyAsync(validForMinutes);

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = containerName,
            BlobName          = blobName,
            Resource          = "b",
            ExpiresOn         = DateTimeOffset.UtcNow.AddMinutes(validForMinutes)
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        var sasParams  = sasBuilder.ToSasQueryParameters(delegationKey, _accountName);
        var uriBuilder = new BlobUriBuilder(
            _blobServiceClient.GetBlobContainerClient(containerName).GetBlobClient(blobName).Uri)
        {
            Sas = sasParams
        };

        return uriBuilder.ToUri().ToString();
    }

    private async Task<UserDelegationKey> GetOrRefreshDelegationKeyAsync(int validForMinutes)
    {
        var now     = DateTimeOffset.UtcNow;
        var cached  = _cached;

        // Fast path: the cached key must (a) not be close to expiry overall, and
        // (b) outlive the SAS token we are about to generate.
        if (cached is not null &&
            now.AddMinutes(KeyRefreshMarginMinutes) < cached.ExpiresOn &&
            now.AddMinutes(validForMinutes)          < cached.ExpiresOn)
        {
            return cached.Key;
        }

        await _keyLock.WaitAsync();
        try
        {
            // Re-read under lock in case another thread already refreshed the key.
            cached = _cached;
            if (cached is not null &&
                now.AddMinutes(KeyRefreshMarginMinutes) < cached.ExpiresOn &&
                now.AddMinutes(validForMinutes)          < cached.ExpiresOn)
            {
                return cached.Key;
            }

            // Request a key that outlives the longest SAS we will generate, plus the
            // refresh margin so we do not immediately need to re-fetch after the first use.
            var keyDurationMinutes = validForMinutes + KeyRefreshMarginMinutes;
            var expiresOn          = now.AddMinutes(keyDurationMinutes);

            _logger.LogInformation(
                "Requesting new user delegation key (expires {ExpiresOn}).", expiresOn);

            var response = await _blobServiceClient.GetUserDelegationKeyAsync(
                startsOn:  null,
                expiresOn: expiresOn);

            _cached = new CachedKey(response.Value, expiresOn);
            return _cached.Key;
        }
        finally
        {
            _keyLock.Release();
        }
    }

    public void Dispose() => _keyLock.Dispose();
}
