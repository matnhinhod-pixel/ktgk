using Google.Cloud.Firestore;
using Google.Api.Gax;

namespace DOMINHNHAT.WebAPI.Infrastructure;

public sealed class FirestoreContext
{
    private readonly Lazy<FirestoreDb?> _database;
    private Exception? _initializationError;

    public bool IsConfigured { get; }
    public Exception? InitializationError => _initializationError;
    public FirestoreDb? Database
    {
        get
        {
            if (!IsConfigured) return null;
            try
            {
                return _database.Value;
            }
            catch (Exception exception)
            {
                Interlocked.CompareExchange(ref _initializationError, exception, null);
                return null;
            }
        }
    }

    public FirestoreContext(IConfiguration configuration)
    {
        var projectId = configuration["Firestore:ProjectId"];
        var databaseId = configuration["Firestore:DatabaseId"];
        IsConfigured = !string.IsNullOrWhiteSpace(projectId);
        _database = new Lazy<FirestoreDb?>(() => !IsConfigured ? null : new FirestoreDbBuilder
        {
            ProjectId = projectId!,
            DatabaseId = string.IsNullOrWhiteSpace(databaseId) ? "(default)" : databaseId,
            EmulatorDetection = EmulatorDetection.EmulatorOrProduction
        }.Build(), LazyThreadSafetyMode.ExecutionAndPublication);
    }

    public CollectionReference Collection(string name) =>
        (Database ?? throw new InvalidOperationException("Firestore is not configured.")).Collection(name);
}
