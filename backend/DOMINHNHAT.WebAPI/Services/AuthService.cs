using System.Security.Cryptography;
using System.Text;
using DOMINHNHAT.WebAPI.Contracts;
using DOMINHNHAT.WebAPI.Infrastructure;
using Google.Cloud.Firestore;

namespace DOMINHNHAT.WebAPI.Services;

public sealed class AuthService(
    FirestoreContext firestore,
    PasswordService passwords,
    TokenService tokens,
    OtpEmailSender email,
    IConfiguration configuration,
    ILogger<AuthService> logger)
{
    public async Task<IResult> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken)
    {
        if (firestore.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrEmpty(request.Password))
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["account"] = ["Username, email and password are required."] });
        var accountType = request.AccountType?.Trim();
        if (string.IsNullOrWhiteSpace(accountType)) accountType = "Employee";
        if (string.Equals(accountType, "Employee", StringComparison.OrdinalIgnoreCase)) accountType = "Employee";
        else if (string.Equals(accountType, "Guest", StringComparison.OrdinalIgnoreCase)) accountType = "Guest";
        else
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["accountType"] = ["Account type must be Employee or Guest. Admin accounts are provisioned by a trusted administrator."] });
        var username = request.Username.Trim();
        var emailAddress = request.Email.Trim();
        if (username.Length is < 3 or > 40 || !username.All(c => char.IsLetterOrDigit(c) || c is '_' or '.' or '-'))
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["username"] = ["Username must be 3–40 characters and contain only letters, digits, '.', '_' or '-'."] });
        if (emailAddress.Length > 254 || !emailAddress.Contains('@'))
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["email"] = ["A valid email is required."] });
        if (request.Password.Length < 10 || request.Password.Length > 128)
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["password"] = ["Password must be 10–128 characters."] });

        var normalizedUsername = username.ToLowerInvariant();
        var normalizedEmail = emailAddress.ToLowerInvariant();
        var userId = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalizedUsername))).ToLowerInvariant();
        var userRef = firestore.Collection("users").Document(userId);
        if ((await userRef.GetSnapshotAsync(cancellationToken)).Exists)
            return Results.Conflict(new { error = "username_unavailable", message = "Username is already in use." });
        var emailMatches = await firestore.Collection("users").WhereEqualTo("emailNormalized", normalizedEmail).Limit(1).GetSnapshotAsync(cancellationToken);
        if (emailMatches.Count > 0)
            return Results.Conflict(new { error = "email_unavailable", message = "Email is already in use." });

        await userRef.CreateAsync(new Dictionary<string, object>
        {
            ["id"] = userId,
            ["username"] = username,
            ["usernameNormalized"] = normalizedUsername,
            ["email"] = emailAddress,
            ["emailNormalized"] = normalizedEmail,
            ["passwordHash"] = passwords.Hash(request.Password),
            ["role"] = accountType,
            ["isActive"] = true,
            ["createdAt"] = Timestamp.GetCurrentTimestamp()
        }, cancellationToken);
        if (accountType == "Employee")
        {
            await firestore.Collection("employees").Document(userId).CreateAsync(new Dictionary<string, object>
            {
                ["id"] = userId,
                ["userId"] = userId,
                ["employeeCode"] = username,
                ["employeeCodeNormalized"] = normalizedUsername,
                ["fullName"] = username,
                ["email"] = emailAddress,
                ["department"] = "",
                ["worksiteId"] = "",
                ["isActive"] = true,
                ["createdAt"] = Timestamp.GetCurrentTimestamp()
            }, cancellationToken);
        }

        return Results.Json(new
        {
            id = userId,
            username,
            email = emailAddress,
            role = accountType,
            message = "Account created. You can sign in now."
        }, statusCode: StatusCodes.Status201Created);
    }

    public async Task<IResult> LoginAsync(LoginRequest request, CancellationToken cancellationToken)
    {
        if (firestore.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
        var requireEmailOtp = configuration.GetValue("Auth:RequireEmailOtp", true);
        if (requireEmailOtp && !email.IsConfigured) return Results.Problem("Email OTP is not configured.", statusCode: 503);
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrEmpty(request.Password)) return Results.Unauthorized();
        var username = request.Username.Trim().ToLowerInvariant();
        var userId = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(username))).ToLowerInvariant();
        var userSnapshot = await firestore.Collection("users").Document(userId).GetSnapshotAsync(cancellationToken);
        if (!userSnapshot.Exists) return Results.Unauthorized();
        var user = userSnapshot.ToDictionary();
        var passwordHash = user.GetValueOrDefault("passwordHash") as string;
        if (passwordHash is null || !passwords.Verify(request.Password, passwordHash) || user.GetValueOrDefault("isActive") is not true)
            return Results.Unauthorized();

        if (!requireEmailOtp)
            return Results.Ok(await CreateAuthResponseAsync(userId, user, cancellationToken));

        var challengeId = Guid.NewGuid().ToString("N");
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var expires = DateTimeOffset.UtcNow.AddMinutes(5);
        await firestore.Collection("otpChallenges").Document(challengeId).CreateAsync(new Dictionary<string, object>
        {
            ["userId"] = userId,
            ["codeHash"] = tokens.HashOtp(challengeId, code),
            ["attemptCount"] = 0,
            ["expiresAt"] = Timestamp.FromDateTime(expires.UtcDateTime),
            ["consumed"] = false,
            ["createdAt"] = Timestamp.GetCurrentTimestamp()
        }, cancellationToken);

        try
        {
            await email.SendAsync((string)user["email"], code, cancellationToken);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Could not send login OTP.");
            await firestore.Collection("otpChallenges").Document(challengeId).DeleteAsync(cancellationToken: cancellationToken);
            return Results.Problem("Unable to deliver OTP email.", statusCode: 502);
        }
        return Results.Ok(new AuthChallengeResponse(challengeId, "OTP sent to the registered email address.", expires));
    }

    public async Task<IResult> VerifyOtpAsync(VerifyOtpRequest request, CancellationToken cancellationToken)
    {
        if (firestore.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
        if (string.IsNullOrWhiteSpace(request.ChallengeId) || request.Code is null || request.Code.Length != 6 || !request.Code.All(char.IsDigit))
            return Results.Unauthorized();
        var challengeRef = firestore.Collection("otpChallenges").Document(request.ChallengeId);
        var outcome = await firestore.Database.RunTransactionAsync(async transaction =>
        {
            var snapshot = await transaction.GetSnapshotAsync(challengeRef);
            if (!snapshot.Exists) return (UserId: (string?)null, Valid: false);
            var challenge = snapshot.ToDictionary();
            var expires = challenge.GetValueOrDefault("expiresAt") is Timestamp value ? value : (Timestamp?)null;
            var attempts = Convert.ToInt32(challenge.GetValueOrDefault("attemptCount") ?? 0);
            var storedHash = challenge.GetValueOrDefault("codeHash") as string;
            if (expires is null || expires.Value.ToDateTime() <= DateTime.UtcNow || challenge.GetValueOrDefault("consumed") is true || attempts >= 5 || storedHash is null)
                return (UserId: (string?)null, Valid: false);
            var candidateHash = tokens.HashOtp(request.ChallengeId, request.Code.Trim());
            if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(candidateHash), Convert.FromHexString(storedHash)))
            {
                transaction.Update(challengeRef, "attemptCount", attempts + 1);
                return (UserId: (string?)null, Valid: false);
            }
            transaction.Update(challengeRef, new Dictionary<string, object>
            {
                ["consumed"] = true,
                ["consumedAt"] = Timestamp.GetCurrentTimestamp()
            });
            return (UserId: challenge.GetValueOrDefault("userId")?.ToString(), Valid: true);
        }, cancellationToken: cancellationToken);
        if (!outcome.Valid || string.IsNullOrWhiteSpace(outcome.UserId)) return Results.Unauthorized();

        var userSnapshot = await firestore.Collection("users").Document(outcome.UserId).GetSnapshotAsync(cancellationToken);
        if (!userSnapshot.Exists) return Results.Unauthorized();
        var user = userSnapshot.ToDictionary();
        if (user.GetValueOrDefault("isActive") is not true) return Results.Forbid();
        return Results.Ok(await CreateAuthResponseAsync(outcome.UserId, user, cancellationToken));
    }

    public async Task<IResult> RefreshAsync(RefreshRequest request, CancellationToken cancellationToken)
    {
        if (firestore.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
        if (string.IsNullOrWhiteSpace(request.RefreshToken)) return Results.Unauthorized();
        var hash = HashRefreshToken(request.RefreshToken);
        var matches = await firestore.Collection("refreshSessions").WhereEqualTo("tokenHash", hash).Limit(1).GetSnapshotAsync(cancellationToken);
        if (matches.Count == 0) return Results.Unauthorized();
        var oldRef = matches.Documents[0].Reference;
        var oldData = matches.Documents[0].ToDictionary();
        var userId = oldData.GetValueOrDefault("userId")?.ToString();
        if (string.IsNullOrWhiteSpace(userId)) return Results.Unauthorized();
        var userSnapshot = await firestore.Collection("users").Document(userId).GetSnapshotAsync(cancellationToken);
        if (!userSnapshot.Exists) return Results.Unauthorized();
        var user = userSnapshot.ToDictionary();
        if (user.GetValueOrDefault("isActive") is not true) return Results.Unauthorized();
        var responseUser = new UserResponse((string)user["id"], (string)user["username"], (string)user["email"], (string)user["role"]);
        var rawRefresh = NewRefreshToken();
        var newRef = firestore.Collection("refreshSessions").Document(Guid.NewGuid().ToString("N"));
        var now = DateTime.UtcNow;
        var rotated = await firestore.Database.RunTransactionAsync(async transaction =>
        {
            var snapshot = await transaction.GetSnapshotAsync(oldRef);
            if (!snapshot.Exists) return false;
            var data = snapshot.ToDictionary();
            var expiry = data.GetValueOrDefault("expiresAt") is Timestamp value ? value.ToDateTime() : DateTime.MinValue;
            if (expiry <= DateTime.UtcNow || data.GetValueOrDefault("revoked") is true) return false;
            transaction.Update(oldRef, new Dictionary<string, object>
            {
                ["revoked"] = true,
                ["revokedAt"] = Timestamp.GetCurrentTimestamp()
            });
            transaction.Create(newRef, new Dictionary<string, object>
            {
                ["userId"] = userId,
                ["tokenHash"] = HashRefreshToken(rawRefresh),
                ["expiresAt"] = Timestamp.FromDateTime(now.AddDays(7)),
                ["revoked"] = false,
                ["createdAt"] = Timestamp.GetCurrentTimestamp()
            });
            return true;
        }, cancellationToken: cancellationToken);
        if (!rotated) return Results.Unauthorized();
        var (access, accessExpiry) = tokens.Create(responseUser);
        return Results.Ok(new AuthResponse(access, rawRefresh, "Bearer", accessExpiry, responseUser));
    }

    public async Task<IResult> LogoutAsync(LogoutRequest request, CancellationToken cancellationToken)
    {
        if (firestore.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
        if (string.IsNullOrWhiteSpace(request.RefreshToken)) return Results.NoContent();
        var matches = await firestore.Collection("refreshSessions")
            .WhereEqualTo("tokenHash", HashRefreshToken(request.RefreshToken)).Limit(1).GetSnapshotAsync(cancellationToken);
        if (matches.Count == 0) return Results.NoContent();
        var reference = matches.Documents[0].Reference;
        await reference.UpdateAsync(new Dictionary<string, object>
        {
            ["revoked"] = true,
            ["revokedAt"] = Timestamp.GetCurrentTimestamp()
        }, cancellationToken: cancellationToken);
        return Results.NoContent();
    }

    private static string NewRefreshToken() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private async Task<AuthResponse> CreateAuthResponseAsync(string userId, Dictionary<string, object> user, CancellationToken cancellationToken)
    {
        var responseUser = new UserResponse((string)user["id"], (string)user["username"], (string)user["email"], (string)user["role"]);
        var (token, tokenExpiry) = tokens.Create(responseUser);
        var refreshToken = NewRefreshToken();
        await firestore.Collection("refreshSessions").Document(Guid.NewGuid().ToString("N")).CreateAsync(new Dictionary<string, object>
        {
            ["userId"] = userId,
            ["tokenHash"] = HashRefreshToken(refreshToken),
            ["expiresAt"] = Timestamp.FromDateTime(DateTime.UtcNow.AddDays(7)),
            ["revoked"] = false,
            ["createdAt"] = Timestamp.GetCurrentTimestamp()
        }, cancellationToken);
        return new AuthResponse(token, refreshToken, "Bearer", tokenExpiry, responseUser);
    }

    private static string HashRefreshToken(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token.Trim())));
}
