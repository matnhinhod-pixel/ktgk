using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Mail;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using DOMINHNHAT.WebAPI.Contracts;

namespace DOMINHNHAT.WebAPI.Services;

public sealed class PasswordService
{
    public string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, 210_000, HashAlgorithmName.SHA256, 32);
        return $"pbkdf2-sha256$210000${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    public bool Verify(string password, string encoded)
    {
        var parts = encoded.Split('$');
        if (parts.Length != 4 || parts[0] != "pbkdf2-sha256" ||
            !int.TryParse(parts[1], out var iterations) || iterations < 100_000 || iterations > 1_000_000)
            return false;
        try
        {
            var salt = Convert.FromBase64String(parts[2]);
            var expected = Convert.FromBase64String(parts[3]);
            var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, expected.Length);
            return CryptographicOperations.FixedTimeEquals(actual, expected);
        }
        catch (FormatException) { return false; }
    }
}

public sealed class TokenService
{
    private readonly byte[] _key;
    private readonly string _issuer;
    private readonly int _minutes;

    public TokenService(IConfiguration configuration, IHostEnvironment environment)
    {
        var configured = configuration["Jwt:SigningKey"];
        if (environment.IsProduction() && string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException("Jwt:SigningKey must be configured in production.");
        _key = string.IsNullOrWhiteSpace(configured) ? RandomNumberGenerator.GetBytes(64) : Encoding.UTF8.GetBytes(configured);
        if (_key.Length < 32) throw new InvalidOperationException("Jwt:SigningKey must contain at least 32 bytes.");
        _issuer = configuration["Jwt:Issuer"] ?? "DOMINHNHAT";
        _minutes = int.TryParse(configuration["Jwt:AccessTokenMinutes"], out var value) ? Math.Clamp(value, 5, 120) : 30;
    }

    public (string Token, DateTimeOffset ExpiresAtUtc) Create(UserResponse user)
    {
        var expires = DateTimeOffset.UtcNow.AddMinutes(_minutes);
        var credentials = new SigningCredentials(new SymmetricSecurityKey(_key), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(_issuer, null,
        [
            new Claim(JwtRegisteredClaimNames.Sub, user.Id),
            new Claim(JwtRegisteredClaimNames.UniqueName, user.Username),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
            new Claim(ClaimTypes.Role, user.Role)
        ], expires: expires.UtcDateTime, signingCredentials: credentials);
        return (new JwtSecurityTokenHandler().WriteToken(token), expires);
    }

    public TokenValidationParameters ValidationParameters() => new()
    {
        ValidateIssuer = true,
        ValidIssuer = _issuer,
        ValidateAudience = false,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(_key),
        ValidateLifetime = true,
        ClockSkew = TimeSpan.FromSeconds(30)
    };

    public string HashOtp(string challengeId, string code) => Convert.ToHexString(
        HMACSHA256.HashData(_key, Encoding.UTF8.GetBytes($"{challengeId}:{code}")));
}

public sealed class OtpEmailSender(IConfiguration configuration)
{
    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(configuration["Smtp:Host"]) &&
        int.TryParse(configuration["Smtp:Port"], out _) &&
        !string.IsNullOrWhiteSpace(configuration["Smtp:From"]);

    public async Task SendAsync(string recipient, string code, CancellationToken cancellationToken)
    {
        if (!IsConfigured) throw new InvalidOperationException("Email OTP is not configured.");
        var host = configuration["Smtp:Host"]!;
        var port = int.Parse(configuration["Smtp:Port"]!);
        using var message = new MailMessage(configuration["Smtp:From"]!, recipient,
            "DOMINHNHAT verification code", $"Your verification code is {code}. It expires in 5 minutes.");
        using var client = new SmtpClient(host, port)
        {
            EnableSsl = bool.TryParse(configuration["Smtp:EnableSsl"], out var ssl) && ssl,
            DeliveryMethod = SmtpDeliveryMethod.Network
        };
        var username = configuration["Smtp:Username"];
        var password = configuration["Smtp:Password"];
        if (!string.IsNullOrWhiteSpace(username)) client.Credentials = new NetworkCredential(username, password);
        await client.SendMailAsync(message, cancellationToken);
    }
}
