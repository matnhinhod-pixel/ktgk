using System.IdentityModel.Tokens.Jwt;
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

}
