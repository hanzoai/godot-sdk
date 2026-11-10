using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;
using Hanzo.AI;
using Hanzo.AI.Api;
using Hanzo.AI.Model;

/// <summary>
/// Godot 4 .NET example node combining Godot's scene tree with the published
/// C# NuGet package `Hanzo` (hanzo-csharp/sdk).
/// </summary>
public partial class HanzoGodotNode : Node3D
{
    [Export] public string ChatModel { get; set; } = "zen6";
    [Export] public string DecisionModel { get; set; } = "kai";
    [Export] public string VoiceModel { get; set; } = "zen-voice";
    [Export] public string SaveBucket { get; set; } = "godot_game_saves";

    private AiApi _ai = null!;
    private KvApi _kv = null!;

    public override void _Ready()
    {
        var config = Gateway.Configuration(); // HANZO_API_KEY, HANZO_BASE_URL, HANZO_ORG_ID
        _ai = new AiApi(config);
        _kv = new KvApi(config);
    }

    public async Task<long?> SaveSlotAsync(string slotKey, string jsonState)
    {
        await _kv.PostKvByBucketAsync(SaveBucket, new KvBucketWrite(history: 5));
        var ack = await _kv.PutKvByBucketByKeyAsync(SaveBucket, slotKey, new KvKvWrite(value: jsonState));
        return ack.Revision;
    }

    public async Task<string> LoadSlotAsync(string slotKey)
    {
        var entry = await _kv.GetKvByBucketByKeyAsync(SaveBucket, slotKey);
        return entry.Value ?? "{}";
    }

    public async Task<AudioStreamMP3> SynthesizeVoiceAsync(string line, string voice = "alloy")
    {
        var mp3Bytes = await _ai.PostAudioSpeechBytesAsync(line, voice, VoiceModel);
        return new AudioStreamMP3 { Data = mp3Bytes };
    }

    public async Task<string> AskNpcAsync(string prompt)
    {
        var reply = await _ai.PostChatCompletionsAsync(new OpenaiChatCompletionRequest(
            model: ChatModel,
            maxTokens: 900,
            messages: new List<OpenaiChatCompletionMessage>
            {
                new(role: "user", content: prompt),
            }));
        return reply.Choices is { Count: > 0 } c ? c[0].Message?.Content ?? "" : "";
    }

    public async Task<string> DecideTacticAsync(int health, bool targetVisible)
    {
        var reply = await _ai.PostDecisionsAsync(new AiDecisionsRequest(
            model: DecisionModel,
            state: new { health, target_visible = targetVisible },
            questions: new Dictionary<string, AiDecisionsQuestion>
            {
                ["tactic"] = new(new AiDecisionsChoice(
                    type: AiDecisionsChoice.TypeEnum.Choice,
                    criteria: new Dictionary<string, string>
                    {
                        ["patrol"] = "keep patrolling when area is clear",
                        ["engage"] = "engage visible target when healthy",
                        ["retreat"] = "fall back when critically injured",
                    })),
            }));
        return reply.Answers["tactic"].Choice;
    }
}
