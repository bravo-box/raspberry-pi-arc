using FleetFunctionApp.Functions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FleetFunctionApp.Tests.Functions;

public sealed class TaskCameraFunctionTests
{
    [Fact]
    public async Task RunAsync_ValidMessage_CompletesWithoutThrowing()
    {
        var sut     = new TaskCameraFunction(NullLogger<TaskCameraFunction>.Instance);
        var context = new Mock<FunctionContext>().Object;

        // Should return a completed task without throwing.
        await sut.RunAsync("{ \"device\": \"pi1\" }", context);
    }

    [Fact]
    public async Task RunAsync_EmptyBody_CompletesWithoutThrowing()
    {
        var sut     = new TaskCameraFunction(NullLogger<TaskCameraFunction>.Instance);
        var context = new Mock<FunctionContext>().Object;

        await sut.RunAsync(string.Empty, context);
    }
}
