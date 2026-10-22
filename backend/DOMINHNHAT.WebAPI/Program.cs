using DOMINHNHAT.WebAPI.Endpoints;
using DOMINHNHAT.WebAPI.Infrastructure;
using DOMINHNHAT.WebAPI.Services;
using FirebaseAdmin;
using FirebaseAdmin.Auth;
using Google.Apis.Auth.OAuth2;
using Microsoft.AspNetCore.Authentication.JwtBearer;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<FirestoreContext>();
builder.Services.AddSingleton<FirebaseAuth>(_ =>
{
    var firebaseApp = FirebaseApp.Create(new AppOptions
    {
        Credential = GoogleCredential.GetApplicationDefault(),
        ProjectId = builder.Configuration["Firestore:ProjectId"]
    }, "DOMINHNHAT.Auth");
    return FirebaseAuth.GetAuth(firebaseApp);
});
builder.Services.AddSingleton<PasswordService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton<AuthorizeOperationFilter>();

var tokenService = new TokenService(builder.Configuration, builder.Environment);
builder.Services.AddSingleton(tokenService);
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options => options.TokenValidationParameters = tokenService.ValidationParameters());
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"));
    options.AddPolicy("EmployeeOnly", policy => policy.RequireRole("Employee"));
    options.AddPolicy("EmployeeOrAdmin", policy => policy.RequireRole("Employee", "Admin"));
    options.AddPolicy("EmployeeGuestOrAdmin", policy => policy.RequireRole("Employee", "Guest", "Admin"));
});
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "DOMINHNHAT Web API",
        Version = "v1",
        Description = "REST API for the DOMINHNHAT employee attendance system."
    });
    options.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Description = "Enter the JWT access token. Swagger UI adds the Bearer prefix.",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT"
    });
    options.OperationFilter<AuthorizeOperationFilter>();
});

var app = builder.Build();
app.UseSwagger();
app.UseSwaggerUI(options => options.SwaggerEndpoint("/swagger/v1/swagger.json", "DOMINHNHAT Web API v1"));
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/api/health", () => Results.Ok(new
{
    status = "Healthy",
    service = "DOMINHNHAT.WebAPI",
    checkedAtUtc = DateTimeOffset.UtcNow
}))
.WithName("GetApiHealth")
.WithTags("System")
.WithSummary("Check whether the API process is responding")
.WithDescription("Liveness only; this endpoint does not check Firestore.")
.AllowAnonymous();

app.MapGet("/api/health/firestore", async (FirestoreContext context, CancellationToken cancellationToken) =>
{
    if (!context.IsConfigured)
        return Results.Problem("Firestore is not configured.", statusCode: StatusCodes.Status503ServiceUnavailable);
    try
    {
        var database = context.Database;
        if (database is null)
            return Results.Problem("Firestore credentials are unavailable.", statusCode: StatusCodes.Status503ServiceUnavailable);
        await database.Collection("_systemHealth").Limit(1).GetSnapshotAsync(cancellationToken);
        return Results.Ok(new { status = "Healthy", dependency = "Firestore", checkedAtUtc = DateTimeOffset.UtcNow });
    }
    catch
    {
        return Results.Problem("Firestore is unavailable.", statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("GetFirestoreHealth")
.WithTags("System")
.WithSummary("Check Firestore connectivity with a read-only query")
.AllowAnonymous();

app.MapAuthEndpoints();
app.MapCrudEndpoints();
app.MapAttendanceEndpoints();

app.Run();

public partial class Program { }
