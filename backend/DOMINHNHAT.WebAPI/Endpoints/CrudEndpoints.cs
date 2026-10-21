using System.Security.Claims;
using DOMINHNHAT.WebAPI.Contracts;
using DOMINHNHAT.WebAPI.Infrastructure;
using Google.Cloud.Firestore;

namespace DOMINHNHAT.WebAPI.Endpoints;

public static class CrudEndpoints
{
    public static IEndpointRouteBuilder MapCrudEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var employees = endpoints.MapGroup("/api/v1/employees").WithTags("Employees").RequireAuthorization();
        employees.MapGet("/", async (FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (db.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
            Query query = db.Collection("employees");
            if (!user.IsInRole("Admin")) query = query.WhereEqualTo("userId", UserId(user));
            var result = await query.GetSnapshotAsync(ct);
            return Results.Ok(result.Documents.Select(ToEmployee));
        }).RequireAuthorization("EmployeeOrAdmin").WithName("GetEmployees").WithSummary("List employees (Admin) or the current employee profile");

        employees.MapGet("/{id}", async (string id, FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (db.Database is null) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var snapshot = await db.Collection("employees").Document(id).GetSnapshotAsync(ct);
            if (!snapshot.Exists) return Results.NotFound();
            var data = snapshot.ToDictionary();
            if (!user.IsInRole("Admin") && !Equals(data.GetValueOrDefault("userId"), UserId(user))) return Results.Forbid();
            return Results.Ok(ToEmployee(snapshot));
        }).RequireAuthorization("EmployeeOrAdmin").WithName("GetEmployee");

        employees.MapPost("/", async (CreateEmployeeRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (string.IsNullOrWhiteSpace(request.EmployeeCode) || string.IsNullOrWhiteSpace(request.FullName) || string.IsNullOrWhiteSpace(request.Email))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["employee"] = ["Employee code, name and email are required."] });
            var duplicate = await db.Collection("employees").WhereEqualTo("employeeCodeNormalized", request.EmployeeCode.Trim().ToUpperInvariant()).Limit(1).GetSnapshotAsync(ct);
            if (duplicate.Count > 0) return Results.Conflict(new { error = "employee_code_exists" });
            var id = Guid.NewGuid().ToString("N");
            var body = new Dictionary<string, object>
            {
                ["id"] = id, ["employeeCode"] = request.EmployeeCode.Trim(), ["employeeCodeNormalized"] = request.EmployeeCode.Trim().ToUpperInvariant(),
                ["fullName"] = request.FullName.Trim(), ["email"] = request.Email.Trim(), ["department"] = request.Department.Trim(),
                ["worksiteId"] = request.WorksiteId ?? "", ["userId"] = "", ["isActive"] = true, ["createdAt"] = Timestamp.GetCurrentTimestamp()
            };
            await db.Collection("employees").Document(id).CreateAsync(body, ct);
            return Results.Created($"/api/v1/employees/{id}", body.Where(p => p.Key != "employeeCodeNormalized"));
        }).RequireAuthorization("AdminOnly").WithName("CreateEmployee");

        employees.MapPut("/{id}", async (string id, UpdateEmployeeRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var reference = db.Collection("employees").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            if (string.IsNullOrWhiteSpace(request.FullName) || string.IsNullOrWhiteSpace(request.Email))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["employee"] = ["Name and email are required."] });
            await reference.UpdateAsync(new Dictionary<string, object>
            {
                ["employeeCode"] = request.EmployeeCode.Trim(), ["employeeCodeNormalized"] = request.EmployeeCode.Trim().ToUpperInvariant(),
                ["fullName"] = request.FullName.Trim(), ["email"] = request.Email.Trim(), ["department"] = request.Department.Trim(),
                ["worksiteId"] = request.WorksiteId ?? "", ["isActive"] = request.IsActive, ["updatedAt"] = Timestamp.GetCurrentTimestamp()
            }, cancellationToken: ct);
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly").WithName("UpdateEmployee");

        employees.MapDelete("/{id}", async (string id, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var reference = db.Collection("employees").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            await reference.UpdateAsync(new Dictionary<string, object> { ["isActive"] = false }, cancellationToken: ct);
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly").WithName("DeleteEmployee").WithSummary("Soft-delete an employee to preserve attendance history");

        var shifts = endpoints.MapGroup("/api/v1/shifts").WithTags("Shifts").RequireAuthorization("EmployeeGuestOrAdmin");
        shifts.MapGet("/", async (FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            Query query = db.Collection("shifts");
            if (!user.IsInRole("Admin")) query = query.WhereEqualTo("isActive", true);
            var result = await query.GetSnapshotAsync(ct);
            return Results.Ok(result.Documents.Select(ToShift));
        }).WithName("GetShifts");

        shifts.MapGet("/{id}", async (string id, FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var snapshot = await db.Collection("shifts").Document(id).GetSnapshotAsync(ct);
            if (!snapshot.Exists) return Results.NotFound();
            if (!user.IsInRole("Admin") && snapshot.ToDictionary().GetValueOrDefault("isActive") is not true) return Results.NotFound();
            return Results.Ok(ToShift(snapshot));
        }).WithName("GetShift");

        shifts.MapPost("/", async (CreateShiftRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (!ValidShift(request.StartTime, request.EndTime, request.GraceMinutes, request.Name))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["shift"] = ["Provide a name, valid 24-hour times, and grace minutes from 0 to 120."] });
            var id = Guid.NewGuid().ToString("N");
            var data = new Dictionary<string, object>
            {
                ["id"] = id, ["name"] = request.Name.Trim(), ["startTime"] = request.StartTime, ["endTime"] = request.EndTime,
                ["graceMinutes"] = request.GraceMinutes, ["worksiteId"] = request.WorksiteId ?? "", ["isActive"] = true,
                ["createdAt"] = Timestamp.GetCurrentTimestamp()
            };
            await db.Collection("shifts").Document(id).CreateAsync(data, ct);
            return Results.Created($"/api/v1/shifts/{id}", ToShift(data));
        }).RequireAuthorization("AdminOnly").WithName("CreateShift");

        shifts.MapPut("/{id}", async (string id, UpdateShiftRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (!ValidShift(request.StartTime, request.EndTime, request.GraceMinutes, request.Name))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["shift"] = ["Provide a name, valid 24-hour times, and grace minutes from 0 to 120."] });
            var reference = db.Collection("shifts").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            await reference.UpdateAsync(new Dictionary<string, object>
            {
                ["name"] = request.Name.Trim(), ["startTime"] = request.StartTime, ["endTime"] = request.EndTime,
                ["graceMinutes"] = request.GraceMinutes, ["worksiteId"] = request.WorksiteId ?? "", ["isActive"] = request.IsActive,
                ["updatedAt"] = Timestamp.GetCurrentTimestamp()
            }, cancellationToken: ct);
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly").WithName("UpdateShift");

        shifts.MapDelete("/{id}", async (string id, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var reference = db.Collection("shifts").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            await reference.UpdateAsync(new Dictionary<string, object> { ["isActive"] = false }, cancellationToken: ct);
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly").WithName("DeleteShift");

        var worksites = endpoints.MapGroup("/api/v1/worksites").WithTags("Worksites").RequireAuthorization("AdminOnly");
        worksites.MapGet("/", async (FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var snapshot = await db.Collection("worksites").GetSnapshotAsync(ct);
            return Results.Ok(snapshot.Documents.Select(d => ToWorksite(d.ToDictionary())));
        }).WithName("GetWorksites");
        worksites.MapPost("/", async (WorksiteRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (!ValidWorksite(request)) return Results.ValidationProblem(new Dictionary<string, string[]> { ["worksite"] = ["Name, valid coordinates, and radius from 10 to 5000 meters are required."] });
            var id = Guid.NewGuid().ToString("N");
            var data = new Dictionary<string, object>
            {
                ["id"] = id, ["name"] = request.Name.Trim(), ["latitude"] = request.Latitude,
                ["longitude"] = request.Longitude, ["allowedRadiusMeters"] = request.AllowedRadiusMeters,
                ["isActive"] = request.IsActive, ["createdAt"] = Timestamp.GetCurrentTimestamp()
            };
            await db.Collection("worksites").Document(id).CreateAsync(data, ct);
            return Results.Created($"/api/v1/worksites/{id}", ToWorksite(data));
        }).WithName("CreateWorksite");
        worksites.MapPut("/{id}", async (string id, WorksiteRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (!ValidWorksite(request)) return Results.ValidationProblem(new Dictionary<string, string[]> { ["worksite"] = ["Name, valid coordinates, and radius from 10 to 5000 meters are required."] });
            var reference = db.Collection("worksites").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            await reference.UpdateAsync(new Dictionary<string, object>
            {
                ["name"] = request.Name.Trim(), ["latitude"] = request.Latitude, ["longitude"] = request.Longitude,
                ["allowedRadiusMeters"] = request.AllowedRadiusMeters, ["isActive"] = request.IsActive,
                ["updatedAt"] = Timestamp.GetCurrentTimestamp()
            }, cancellationToken: ct);
            return Results.NoContent();
        }).WithName("UpdateWorksite");
        worksites.MapDelete("/{id}", async (string id, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var reference = db.Collection("worksites").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            await reference.UpdateAsync(new Dictionary<string, object> { ["isActive"] = false }, cancellationToken: ct);
            return Results.NoContent();
        }).WithName("DeleteWorksite").WithSummary("Deactivate a worksite while preserving attendance references");

        return endpoints;
    }

    internal static string UserId(ClaimsPrincipal user) => user.FindFirstValue(ClaimTypes.NameIdentifier) ?? user.FindFirstValue("sub") ?? "";
    internal static bool IsConfigured(this FirestoreContext db) => db.Database is not null;
    private static bool ValidShift(string start, string end, int grace, string name) =>
        !string.IsNullOrWhiteSpace(name) && TimeOnly.TryParse(start, out _) && TimeOnly.TryParse(end, out _) && grace is >= 0 and <= 120;
    private static bool ValidWorksite(WorksiteRequest request) => !string.IsNullOrWhiteSpace(request.Name) &&
        double.IsFinite(request.Latitude) && request.Latitude is >= -90 and <= 90 &&
        double.IsFinite(request.Longitude) && request.Longitude is >= -180 and <= 180 &&
        double.IsFinite(request.AllowedRadiusMeters) && request.AllowedRadiusMeters is >= 10 and <= 5000;
    private static object ToWorksite(IDictionary<string, object> d) => new
    {
        id = Get(d, "id"), name = Get(d, "name"), latitude = Convert.ToDouble(d.GetValueOrDefault("latitude") ?? 0),
        longitude = Convert.ToDouble(d.GetValueOrDefault("longitude") ?? 0),
        allowedRadiusMeters = Convert.ToDouble(d.GetValueOrDefault("allowedRadiusMeters") ?? 0),
        isActive = d.GetValueOrDefault("isActive") is true
    };
    private static object ToEmployee(DocumentSnapshot snapshot) => ToEmployee(snapshot.ToDictionary());
    private static object ToEmployee(IDictionary<string, object> d) => new
    {
        id = Get(d, "id"), employeeCode = Get(d, "employeeCode"), fullName = Get(d, "fullName"), email = Get(d, "email"),
        department = Get(d, "department"), worksiteId = Get(d, "worksiteId"), userId = Get(d, "userId"), isActive = d.GetValueOrDefault("isActive") is true
    };
    private static object ToShift(DocumentSnapshot snapshot) => ToShift(snapshot.ToDictionary());
    private static object ToShift(IDictionary<string, object> d) => new
    {
        id = Get(d, "id"), name = Get(d, "name"), startTime = Get(d, "startTime"), endTime = Get(d, "endTime"),
        graceMinutes = Convert.ToInt32(d.GetValueOrDefault("graceMinutes") ?? 0), worksiteId = Get(d, "worksiteId"), isActive = d.GetValueOrDefault("isActive") is true
    };
    private static string Get(IDictionary<string, object> d, string key) => d.GetValueOrDefault(key)?.ToString() ?? "";
    private static object? GetValueOrDefault(this IDictionary<string, object> d, string key) => d.TryGetValue(key, out var value) ? value : null;
}
