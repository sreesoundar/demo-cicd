namespace Api;

public static class Greeter
{
    public static string Greet(string name) =>
        $"Hello, {(string.IsNullOrWhiteSpace(name) ? "world" : name.Trim())}!";
}
