using System.Security.Claims;
using DOMINHNHAT.WebAPI.Contracts;
using DOMINHNHAT.WebAPI.Services;

namespace DOMINHNHAT.WebAPI.Endpoints;

public static class AuthEndpoints
{
    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/auth").WithTags("Authentication");
        group.MapPost("/register", (RegisterRequest request, AuthService auth, CancellationToken ct) => auth.RegisterAsync(request, ct))
            .WithName("RegisterAccount").WithSummary("Register an account after Firebase email verification").AllowAnonymous();
        group.MapPost("/login", (LoginRequest request, AuthService auth, CancellationToken ct) => auth.LoginAsync(request, ct))
            .WithName("LoginWithPassword").WithSummary("Validate username/password and issue a session").AllowAnonymous();
        group.MapPost("/refresh", (RefreshRequest request, AuthService auth, CancellationToken ct) => auth.RefreshAsync(request, ct))
            .WithName("RefreshSession").WithSummary("Rotate a refresh token and issue a new access token").AllowAnonymous();
        group.MapPost("/logout", (LogoutRequest request, AuthService auth, CancellationToken ct) => auth.LogoutAsync(request, ct))
            .WithName("Logout").WithSummary("Revoke the refresh session").RequireAuthorization();
        group.MapGet("/me", (ClaimsPrincipal principal) => Results.Ok(new UserResponse(
                principal.FindFirstValue(ClaimTypes.NameIdentifier) ?? principal.FindFirstValue("sub") ?? "",
                principal.FindFirstValue(ClaimTypes.Name) ?? principal.FindFirstValue("unique_name") ?? "",
                principal.FindFirstValue(ClaimTypes.Email) ?? "",
                principal.FindFirstValue(ClaimTypes.Role) ?? "")))
            .WithName("GetCurrentUser").WithSummary("Get the current authenticated account").RequireAuthorization();
        return endpoints;
    }
}
