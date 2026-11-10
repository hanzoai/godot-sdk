# Godot 4 .NET (C#) + `Hanzo` NuGet SDK

Standard Godot 4 projects use the pure-GDScript addon in [`addons/hanzo_ai/`](../../addons/hanzo_ai) with zero `.NET` dependency.

If your game uses **Godot 4 .NET (C#)** (`net8.0+`), you can also add the official [`Hanzo`](https://github.com/hanzo-csharp/sdk) NuGet package directly to your `.csproj`:

```bash
dotnet nuget add source "https://nuget.pkg.github.com/hanzo-csharp/index.json" \
  --name hanzo-github --username "$GITHUB_USER" --password "$(gh auth token)" --store-password-in-clear-text
dotnet add package Hanzo --version 8.5.1026
```

Then attach [`HanzoGodotNode.cs`](HanzoGodotNode.cs) to any `Node3D` to call `zen6` (`PostChatCompletionsAsync`) and `kai` (`PostDecisionsAsync`) asynchronously off the main render thread.
