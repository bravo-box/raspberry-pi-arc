using FleetFunctionApp.Functions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FleetFunctionApp.Tests.Functions;

public sealed class PhotoProcessedFunctionTests
{
    [Fact]
    public async Task RunAsync_ValidAckMessage_CompletesWithoutThrowing()
    {
        var sut     = new PhotoProcessedFunction(NullLogger<PhotoProcessedFunction>.Instance);
        var context = new Mock<FunctionContext>().Object;

        await sut.RunAsync("{ \"file_name\": \"pi1_20240101T120000_000000.jpg\" }", context);
    }

    [Fact]
    public async Task RunAsync_EmptyBody_CompletesWithoutThrowing()
    {
        var sut     = new PhotoProcessedFunction(NullLogger<PhotoProcessedFunction>.Instance);
        var context = new Mock<FunctionContext>().Object;

        await sut.RunAsync(string.Empty, context);
    }
}
