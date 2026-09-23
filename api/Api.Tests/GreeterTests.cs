using Api;

namespace Api.Tests;

public class GreeterTests
{
    [Fact]
    public void GreetsAName() => Assert.Equal("Hello, TimberCore!", Greeter.Greet("TimberCore"));

    [Fact]
    public void FallsBackToWorldWhenBlank() => Assert.Equal("Hello, world!", Greeter.Greet("  "));
}
