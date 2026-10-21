# DOMINHNHAT

Employee attendance mobile app and REST API.

## Backend

The ASP.NET Core 8 API is in [`backend/DOMINHNHAT.WebAPI`](backend/DOMINHNHAT.WebAPI). Run/setup instructions and required environment configuration are in [`backend/README.md`](backend/README.md).

Current backend routes include:

- Authentication: Employee/Guest registration, password login, optional email OTP, refresh, logout, current user.
- Admin CRUD: employees, shifts, worksites, QR challenges and attendance record voiding.
- Attendance: check-in, check-out, history and explanations.
- System: API health and Firestore connectivity health.

The backend is configured for Firebase project `ltdd-bec6d` and Firestore database `(default)`. Firestore connectivity has been verified from this machine. The Android app is also registered in Firebase as `DOMINHNHAT-Android` (`com.example.nhom_3_nguoi`, app ID `1:413318622405:android:a5c05bdfa9f90a9ecd14ac`); `android/app/google-services.json`, the Google Services Gradle plugin, and FlutterFire Core initialize the Firebase app at startup. Email OTP is optional and requires SMTP settings when enabled. Business data continues to use the backend REST API, so Firestore credentials are not included in the APK.

## Mobile

The Flutter Android app is in the project root. It includes login/register, optional OTP verification, secure token storage and refresh, role-aware dashboards, admin Employee/Shift/Worksite CRUD, attendance history, QR scanning/creation, and GPS submission.

The biometric feature is Android OS biometric unlock for an already authenticated session. Sign in once, enable **Mở khóa sinh trắc học** in the account menu, then reopen the app to verify with a face or fingerprint supported by the device. It is not face recognition and does not identify a user from a face image; the app does not receive or store face images. Smart attendance verification is implemented by the backend using QR validity, GPS accuracy/worksite radius, and shift time, with flagged records, employee explanations, and Admin review.

## Run the demo

The backend is configured for Firebase project `ltdd-bec6d`, database `(default)`. On this machine, its read-only Firestore health endpoint has returned `Healthy`.

Run the backend in terminal 1:

```sh
bash backend/run-demo.sh
```

The demo script skips email OTP by default, so no SMTP credentials are needed. Password login still validates the account and issues a normal session. To enable OTP, set `Auth__RequireEmailOtp=true` before starting the script and configure Gmail as described in [`backend/README.md`](backend/README.md). The ADC file is local, mode `0600`, outside the repository, and temporary. For a durable setup or another computer, use the ADC instructions in [`backend/README.md`](backend/README.md).

If the tunnel is stopped, run in terminal 2:

```sh
cloudflared tunnel --url http://localhost:5080
```

Use the HTTPS hostname printed by `cloudflared`; Quick Tunnel hostnames change when restarted. Swagger is available at `<HOSTNAME>/swagger`; health checks are at `<HOSTNAME>/api/health` and `<HOSTNAME>/api/health/firestore`.

Run the mobile app from terminal 3 or Android Studio:

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=https://HOSTNAME_CUA_BAN.trycloudflare.com
```

Registration stores an Employee or Guest account in Firestore without sending email. To demo Admin workflows, provision an existing account by changing `users/{sha256(lowercase username)}.role` to `Admin` in Firestore, as described in [`backend/README.md`](backend/README.md). Then sign in, create a worksite and shift, create a QR, and check in from an Employee account. Android needs Internet, camera, and location permissions. The APK built during development is `build/app/outputs/flutter-apk/app-debug.apk`.

Current external setup needed for an Admin workflow demo: an Admin account provisioned by a trusted operator. The debug APK is available, but device-level camera/GPS/biometric checks require installing it on an Android device or emulator with those capabilities.
