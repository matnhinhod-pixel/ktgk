using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using DOMINHNHAT.WebAPI.Contracts;
using DOMINHNHAT.WebAPI.Infrastructure;
using Google.Cloud.Firestore;

namespace DOMINHNHAT.WebAPI.Endpoints;

public static class AttendanceEndpoints
{
    public static IEndpointRouteBuilder MapAttendanceEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/attendance").WithTags("Attendance").RequireAuthorization();

        group.MapPost("/qr-challenges", async (CreateQrRequest request, FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (request.LifetimeSeconds is < 15 or > 300)
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["lifetimeSeconds"] = ["QR lifetime must be between 15 and 300 seconds."] });
            var shift = await db.Collection("shifts").Document(request.ShiftId).GetSnapshotAsync(ct);
            if (!shift.Exists || shift.ToDictionary().GetValueOrDefault("isActive") is not true) return Results.NotFound();
            var rawToken = Base64Url(RandomNumberGenerator.GetBytes(32));
            var id = Guid.NewGuid().ToString("N");
            var expires = DateTimeOffset.UtcNow.AddSeconds(request.LifetimeSeconds);
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawToken)));
            await db.Collection("qrChallenges").Document(id).CreateAsync(new Dictionary<string, object>
            {
                ["id"] = id, ["shiftId"] = request.ShiftId, ["tokenHash"] = hash,
                ["createdBy"] = CrudEndpoints.UserId(user), ["createdAt"] = Timestamp.GetCurrentTimestamp(),
                ["expiresAt"] = Timestamp.FromDateTime(expires.UtcDateTime), ["consumed"] = false
            }, cancellationToken: ct);
            // The raw token is returned only once so the admin screen can render its QR image.
            return Results.Created($"/api/v1/attendance/qr-challenges/{id}", new { challengeId = id, qrToken = rawToken, expiresAtUtc = expires });
        }).RequireAuthorization("AdminOnly").WithName("CreateAttendanceQr").WithSummary("Create a short-lived, single-use QR challenge");

        group.MapPost("/check-in", async (CheckInRequest request, FirestoreContext db, ClaimsPrincipal user, IConfiguration configuration, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (!ValidLocation(request.Latitude, request.Longitude, request.AccuracyMeters))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["location"] = ["Valid coordinates and GPS accuracy from 0 to 200 meters are required."] });
            if (string.IsNullOrWhiteSpace(request.QrToken)) return Results.Unauthorized();
            var userId = CrudEndpoints.UserId(user);
            var shiftSnapshot = await db.Collection("shifts").Document(request.ShiftId).GetSnapshotAsync(ct);
            if (!shiftSnapshot.Exists) return Results.NotFound(new { error = "shift_not_found" });
            var shift = shiftSnapshot.ToDictionary();
            if (shift.GetValueOrDefault("isActive") is not true) return Results.Conflict(new { error = "shift_inactive" });

            var tokenHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(request.QrToken.Trim())));
            var qrQuery = await db.Collection("qrChallenges").WhereEqualTo("tokenHash", tokenHash).Limit(1).GetSnapshotAsync(ct);
            if (qrQuery.Count == 0) return Results.Unauthorized();
            var qrSnapshot = qrQuery.Documents[0];
            var qr = qrSnapshot.ToDictionary();
            var qrExpiry = qr.GetValueOrDefault("expiresAt") is Timestamp timestamp ? timestamp.ToDateTime() : DateTime.MinValue;
            if (!Equals(qr.GetValueOrDefault("shiftId"), request.ShiftId) || qrExpiry <= DateTime.UtcNow || qr.GetValueOrDefault("consumed") is true)
                return Results.Conflict(new { error = "qr_invalid_expired_or_used" });

            var tzId = configuration["Attendance:TimeZoneId"] ?? "Asia/Ho_Chi_Minh";
            var now = DateTimeOffset.UtcNow;
            var localNow = TimeZoneInfo.ConvertTime(now, SafeTimeZone(tzId)).TimeOfDay;
            var start = TimeOnly.TryParse(shift.GetValueOrDefault("startTime")?.ToString(), out var parsedStart) ? parsedStart : new TimeOnly(0, 0);
            var end = TimeOnly.TryParse(shift.GetValueOrDefault("endTime")?.ToString(), out var parsedEnd) ? parsedEnd : new TimeOnly(23, 59);
            var grace = Convert.ToInt32(shift.GetValueOrDefault("graceMinutes") ?? 0);
            var earliest = start.AddMinutes(-grace).ToTimeSpan();
            var insideShift = start <= end
                ? localNow >= earliest && localNow <= end.ToTimeSpan()
                : localNow >= earliest || localNow <= end.ToTimeSpan();
            var flags = new List<string>();
            if (!insideShift) flags.Add("outside_shift_window");
            if (request.AccuracyMeters > 50) flags.Add("low_gps_accuracy");

            var worksiteId = shift.GetValueOrDefault("worksiteId")?.ToString() ?? "";
            if (!string.IsNullOrWhiteSpace(worksiteId))
            {
                var siteSnapshot = await db.Collection("worksites").Document(worksiteId).GetSnapshotAsync(ct);
                if (siteSnapshot.Exists)
                {
                    var site = siteSnapshot.ToDictionary();
                    if (site.GetValueOrDefault("isActive") is not true) flags.Add("worksite_inactive");
                    var lat = Number(site.GetValueOrDefault("latitude"));
                    var lon = Number(site.GetValueOrDefault("longitude"));
                    var radius = Number(site.GetValueOrDefault("allowedRadiusMeters"));
                    if (DistanceMeters(request.Latitude, request.Longitude, lat, lon) > radius + request.AccuracyMeters)
                        flags.Add("outside_worksite_radius");
                }
                else flags.Add("worksite_not_configured");
            }
            else flags.Add("shift_has_no_worksite");

            var transactionResult = await db.Database!.RunTransactionAsync(async transaction =>
            {
                var currentQr = await transaction.GetSnapshotAsync(qrSnapshot.Reference);
                if (!currentQr.Exists || currentQr.ToDictionary().GetValueOrDefault("consumed") is true) return false;
                var expiresAt = currentQr.ToDictionary().GetValueOrDefault("expiresAt") is Timestamp expiry ? expiry.ToDateTime() : DateTime.MinValue;
                if (expiresAt <= DateTime.UtcNow) return false;
                transaction.Update(qrSnapshot.Reference, new Dictionary<string, object>
                {
                    ["consumed"] = true, ["consumedBy"] = userId, ["consumedAt"] = Timestamp.GetCurrentTimestamp()
                });
                return true;
            }, cancellationToken: ct);
            if (!transactionResult) return Results.Conflict(new { error = "qr_already_used_or_expired" });

            var previous = await db.Collection("attendanceRecords").WhereEqualTo("employeeId", userId)
                .WhereEqualTo("shiftId", request.ShiftId).WhereEqualTo("status", "Open").Limit(1).GetSnapshotAsync(ct);
            if (previous.Count > 0) return Results.Conflict(new { error = "open_attendance_exists" });

            var recordId = Guid.NewGuid().ToString("N");
            var verification = flags.Count == 0 ? "Verified" : "ReviewRequired";
            var record = new Dictionary<string, object>
            {
                ["id"] = recordId, ["employeeId"] = userId, ["shiftId"] = request.ShiftId, ["qrChallengeId"] = qrSnapshot.Id,
                ["checkInAt"] = Timestamp.FromDateTime(now.UtcDateTime), ["checkInLatitude"] = request.Latitude,
                ["checkInLongitude"] = request.Longitude, ["checkInAccuracyMeters"] = request.AccuracyMeters,
                ["status"] = "Open", ["verificationStatus"] = verification, ["flags"] = flags,
                ["createdAt"] = Timestamp.GetCurrentTimestamp()
            };
            await db.Collection("attendanceRecords").Document(recordId).CreateAsync(record, ct);
            return Results.Created($"/api/v1/attendance/{recordId}", new
            {
                id = recordId, status = "Open", verificationStatus = verification, flags,
                checkInAtUtc = now, message = verification == "Verified" ? "Attendance recorded." : "Attendance recorded and flagged for review."
            });
        }).RequireAuthorization("EmployeeOnly").WithName("CheckIn").WithSummary("Check in using a single-use QR token, GPS and shift window");

        group.MapPost("/check-out", async (CheckOutRequest request, FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (!ValidLocation(request.Latitude, request.Longitude, request.AccuracyMeters))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["location"] = ["Valid coordinates and GPS accuracy from 0 to 200 meters are required."] });
            var query = await db.Collection("attendanceRecords").WhereEqualTo("employeeId", CrudEndpoints.UserId(user))
                .WhereEqualTo("status", "Open").Limit(1).GetSnapshotAsync(ct);
            if (query.Count == 0) return Results.Conflict(new { error = "no_open_attendance" });
            var snapshot = query.Documents[0];
            var now = DateTimeOffset.UtcNow;
            await snapshot.Reference.UpdateAsync(new Dictionary<string, object>
            {
                ["checkOutAt"] = Timestamp.FromDateTime(now.UtcDateTime), ["checkOutLatitude"] = request.Latitude,
                ["checkOutLongitude"] = request.Longitude, ["checkOutAccuracyMeters"] = request.AccuracyMeters,
                ["status"] = "Closed", ["updatedAt"] = Timestamp.GetCurrentTimestamp()
            }, cancellationToken: ct);
            return Results.Ok(new { id = snapshot.Id, status = "Closed", checkOutAtUtc = now });
        }).RequireAuthorization("EmployeeOnly").WithName("CheckOut");

        group.MapGet("/history", async (FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            Query query = db.Collection("attendanceRecords");
            if (!user.IsInRole("Admin")) query = query.WhereEqualTo("employeeId", CrudEndpoints.UserId(user));
            var snapshot = await query.OrderByDescending("checkInAt").Limit(100).GetSnapshotAsync(ct);
            return Results.Ok(snapshot.Documents.Select(ToResponse));
        }).RequireAuthorization("EmployeeOrAdmin").WithName("GetAttendanceHistory").WithSummary("List the current employee history or all records for Admin (max 100)");

        group.MapGet("/{id}", async (string id, FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var snapshot = await db.Collection("attendanceRecords").Document(id).GetSnapshotAsync(ct);
            if (!snapshot.Exists) return Results.NotFound();
            var record = snapshot.ToDictionary();
            if (!user.IsInRole("Admin") && !Equals(record.GetValueOrDefault("employeeId"), CrudEndpoints.UserId(user))) return Results.Forbid();
            return Results.Ok(ToResponse(snapshot));
        }).RequireAuthorization("EmployeeOrAdmin").WithName("GetAttendanceRecord");

        group.MapPut("/{id}", async (string id, UpdateAttendanceRequest request, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (request.VerificationStatus is not ("Verified" or "ReviewRequired" or "ExplanationSubmitted"))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["verificationStatus"] = ["Allowed values: Verified, ReviewRequired, ExplanationSubmitted."] });
            if (request.Explanation?.Length > 2000)
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["explanation"] = ["Admin note cannot exceed 2000 characters."] });
            var reference = db.Collection("attendanceRecords").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            var updates = new Dictionary<string, object>
            {
                ["verificationStatus"] = request.VerificationStatus,
                ["reviewedAt"] = Timestamp.GetCurrentTimestamp()
            };
            if (request.Explanation is not null) updates["adminNote"] = request.Explanation.Trim();
            await reference.UpdateAsync(updates, cancellationToken: ct);
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly").WithName("UpdateAttendanceRecord").WithSummary("Admin review of attendance verification status");

        group.MapPost("/{id}/explanations", async (string id, ExplanationRequest request, FirestoreContext db, ClaimsPrincipal user, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            if (string.IsNullOrWhiteSpace(request.Explanation) || request.Explanation.Length > 2000)
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["explanation"] = ["Explanation must be between 1 and 2000 characters."] });
            var reference = db.Collection("attendanceRecords").Document(id);
            var record = await reference.GetSnapshotAsync(ct);
            if (!record.Exists) return Results.NotFound();
            if (!user.IsInRole("Admin") && !Equals(record.ToDictionary().GetValueOrDefault("employeeId"), CrudEndpoints.UserId(user))) return Results.Forbid();
            await reference.UpdateAsync(new Dictionary<string, object>
            {
                ["explanation"] = request.Explanation.Trim(), ["explanationSubmittedAt"] = Timestamp.GetCurrentTimestamp(),
                ["verificationStatus"] = "ExplanationSubmitted"
            }, cancellationToken: ct);
            return Results.Accepted($"/api/v1/attendance/{id}");
        }).RequireAuthorization("EmployeeOrAdmin").WithName("SubmitAttendanceExplanation");

        group.MapDelete("/{id}", async (string id, FirestoreContext db, CancellationToken ct) =>
        {
            if (!db.IsConfigured()) return Results.Problem("Firestore is not configured.", statusCode: 503);
            var reference = db.Collection("attendanceRecords").Document(id);
            if (!(await reference.GetSnapshotAsync(ct)).Exists) return Results.NotFound();
            await reference.UpdateAsync(new Dictionary<string, object>
            {
                ["status"] = "Voided", ["voidedAt"] = Timestamp.GetCurrentTimestamp()
            }, cancellationToken: ct);
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly").WithName("VoidAttendanceRecord").WithSummary("Void a record while retaining its audit history");

        return endpoints;
    }

    private static bool ValidLocation(double lat, double lon, double accuracy) =>
        double.IsFinite(lat) && double.IsFinite(lon) && lat is >= -90 and <= 90 && lon is >= -180 and <= 180 && double.IsFinite(accuracy) && accuracy is >= 0 and <= 200;
    private static double Number(object? value) => value is null ? 0 : Convert.ToDouble(value);
    private static double DistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double earthRadius = 6_371_000;
        var dLat = Degrees(lat2 - lat1);
        var dLon = Degrees(lon2 - lon1);
        var a = Math.Pow(Math.Sin(dLat / 2), 2) + Math.Cos(Degrees(lat1)) * Math.Cos(Degrees(lat2)) * Math.Pow(Math.Sin(dLon / 2), 2);
        return earthRadius * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
    private static double Degrees(double angle) => angle * Math.PI / 180;
    private static TimeZoneInfo SafeTimeZone(string id)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (TimeZoneNotFoundException) { return TimeZoneInfo.Utc; }
        catch (InvalidTimeZoneException) { return TimeZoneInfo.Utc; }
    }
    private static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    private static object ToResponse(DocumentSnapshot snapshot)
    {
        var d = snapshot.ToDictionary();
        return new
        {
            id = snapshot.Id, employeeId = d.GetValueOrDefault("employeeId")?.ToString(), shiftId = d.GetValueOrDefault("shiftId")?.ToString(),
            status = d.GetValueOrDefault("status")?.ToString(), verificationStatus = d.GetValueOrDefault("verificationStatus")?.ToString(),
            checkInAtUtc = Utc(d.GetValueOrDefault("checkInAt")), checkOutAtUtc = Utc(d.GetValueOrDefault("checkOutAt")),
            flags = d.GetValueOrDefault("flags"), explanation = d.GetValueOrDefault("explanation")?.ToString(),
            adminNote = d.GetValueOrDefault("adminNote")?.ToString()
        };
    }
    private static DateTimeOffset? Utc(object? value) => value is Timestamp timestamp ? new DateTimeOffset(timestamp.ToDateTime(), TimeSpan.Zero) : null;
}
