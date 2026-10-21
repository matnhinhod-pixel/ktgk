# DOMINHNHAT Backend

ASP.NET Core 8 Web API project for the DOMINHNHAT attendance app.

## Requirements

- .NET SDK 8.0.132 (or another .NET 8 SDK)
- Firebase project `ltdd-bec6d`, Firestore database `(default)`, and server credentials (Application Default Credentials)
- SMTP account for email OTP

## Run locally

From this directory:

```sh
dotnet restore DOMINHNHAT.WebAPI/DOMINHNHAT.WebAPI.csproj
dotnet run --project DOMINHNHAT.WebAPI/DOMINHNHAT.WebAPI.csproj --launch-profile http
```

The HTTP launch profile is configured for `http://localhost:5080`. Open Swagger at `/swagger` and the unauthenticated liveness endpoint at `/api/health`.

After the local API responds, a Quick Tunnel can be started in another terminal:

```sh
cloudflared tunnel --url http://localhost:5080
```

Use the HTTPS hostname printed by `cloudflared`; it is temporary and changes when a new Quick Tunnel is started.

## Current scope

- Swagger UI and an OpenAPI v1 document.
- Bearer JWT scheme reserved in Swagger for the authentication phase.
- `GET /api/health` reports API process liveness only. It does not claim that Firestore is connected.
- `GET /api/health/firestore` performs a read-only Firestore query.
- Authentication uses PBKDF2 password hashes, email OTP and short-lived JWTs. Set `Jwt__SigningKey` to a stable secret of at least 32 bytes before using multiple instances. In Development, an ephemeral key is generated if it is missing; tokens stop validating after restart.
- Firestore APIs require `Firestore__ProjectId`; `Firestore__DatabaseId` is optional and defaults to `(default)`. Set `GOOGLE_APPLICATION_CREDENTIALS` outside the repository when using a service account locally, or use Application Default Credentials.
- This repository is configured for the existing Firebase project `ltdd-bec6d` and its `(default)` Firestore database. The Android app is registered in Firebase and initializes Firebase Core using `android/app/google-services.json`; Firestore business data still goes through this backend, and server credentials stay out of the APK.
- For the current local demo session, the backend uses a mode-0600 ADC file at `/tmp/dominhnhat-adc.json` derived from the already signed-in Firebase CLI user. It is outside the repository and is temporary. For a durable local setup, use the Google Cloud CLI ADC login below; for deployment, attach a least-privilege service account to the backend runtime, or point `GOOGLE_APPLICATION_CREDENTIALS` at a service-account file stored outside this repository.
- For local development with a Google user account, install the Google Cloud CLI and run `gcloud auth application-default login`, then grant that Google account the Firestore access needed by the backend. Firebase CLI login alone does not provide Application Default Credentials to the .NET Firestore SDK.
- For local Firestore Emulator use, set `FIRESTORE_EMULATOR_HOST` and `Firestore__ProjectId`; the backend detects the emulator automatically. Emulator data is separate from Firebase production data.
- Email OTP requires `Smtp__Host`, `Smtp__Port`, `Smtp__From`; optional authenticated SMTP uses `Smtp__Username` and `Smtp__Password`. `Smtp__EnableSsl` controls TLS.
- `Auth:RequireEmailOtp` controls password-login OTP and defaults to `true`. The local `backend/run-demo.sh` demo defaults this setting to `false`, so valid username/password credentials issue a session directly and no SMTP connection is needed. Set `Auth__RequireEmailOtp=true` before running the script to enable OTP; it then asks for the Gmail sender and App Password without echoing or saving the password. Do not use your normal Google account password.
- The Android biometric flow uses `local_auth` and the OS biometric prompt to unlock an existing authenticated session. Android selects the enrolled face or fingerprint modality; the app does not process or store a face image. Face detection only finds a face and does not identify a person. Standalone face recognition would require a separate enrollment/matching system and presentation-attack defenses.
- Register/login endpoints: `POST /api/v1/auth/register`, `/login`; when OTP is enabled, complete login with `/verify-otp`. Refresh/logout: `POST /api/v1/auth/refresh`, `/logout`; current user: `GET /api/v1/auth/me`.
- Public registration accepts `accountType: Employee` or `Guest`; Admin cannot be selected at registration. Employee accounts get an employee profile; Guest accounts do not. Guests can view active shifts but attendance endpoints and employee records require Employee or Admin. Registration does not require SMTP.
- Employee CRUD: `/api/v1/employees`; Shift CRUD: `/api/v1/shifts`; Worksite CRUD: `/api/v1/worksites`; attendance check-in/out, history, QR and explanations: `/api/v1/attendance`.
- Employee registrations receive an employee profile; Guest registrations do not. To provision the first Admin, register an account, then have a trusted operator change `users/{userId}.role` to `Admin` in Firestore. `userId` is the lowercase SHA-256 hex of the normalized username. The public registration endpoint never accepts an Admin role.
- QR challenges expire after 15–300 seconds and are consumed once. Attendance stores GPS accuracy, applies the configured shift timezone and worksite radius, and marks irregular records for review. GPS is a signal, not proof of device location.
- Refresh tokens are stored as hashes and rotated on refresh. Logout revokes the refresh session; existing access JWTs remain valid until their short expiry (maximum 120 minutes).
- Employee and attendance API operations require Firestore configuration. JWT-protected operations enforce roles in the API; Swagger does not disable authorization.
