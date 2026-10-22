# DOMINHNHAT

Employee attendance mobile app and REST API.

## Backend

The ASP.NET Core 8 API is in [`backend/DOMINHNHAT.WebAPI`](backend/DOMINHNHAT.WebAPI). Run/setup instructions and required environment configuration are in [`backend/README.md`](backend/README.md).

Current backend routes include:

- Authentication: Employee/Guest registration, username/password login, refresh, logout, current user.
- Admin CRUD: employees, shifts, worksites, QR challenges and attendance record voiding.
- Attendance: check-in, check-out, history, explanations, review decisions and per-record audit history.
- System: API health and Firestore connectivity health.

The backend is configured for Firebase project `ltdd-bec6d` and Firestore database `(default)`. Firestore connectivity has been verified from this machine. The Android app is also registered in Firebase as `DOMINHNHAT-Android` (`com.example.nhom_3_nguoi`, app ID `1:413318622405:android:a5c05bdfa9f90a9ecd14ac`); `android/app/google-services.json`, the Google Services Gradle plugin, and FlutterFire Core initialize the Firebase app at startup. Business data continues to use the backend REST API, so server credentials are not included in the APK.

## Mobile

The Flutter Android app is in the project root. It includes email registration, username/password login, optional on-device biometric unlock for a previously authenticated session, secure token storage and refresh, role-aware dashboards, admin Employee/Shift/Worksite CRUD, attendance history, QR scanning/creation, and GPS submission.

To enable biometric login, sign in with username and password first, then choose **Thiết lập đăng nhập khuôn mặt / vân tay** in the account menu and confirm with an enrolled biometric. The next time the app opens, the login screen offers the device's face or fingerprint prompt for that saved account. This uses Android's biometric authentication; it does not enroll or recognize face images in the app.

Smart attendance verification is implemented by the backend using QR validity, GPS accuracy/worksite radius, and shift time, with flagged records, employee explanations, and Admin review.

The new transparent attendance receipt is shown immediately after check-in and in the attendance history. It includes the timestamp, shift, QR result, GPS accuracy, distance to the worksite, and the result of each verification check. Employees can submit an explanation; Admin can approve, reject, or request review with a note. The API stores review events in the Firestore `attendanceAuditEvents` collection and exposes the authorized history at `/api/v1/attendance/{id}/audit`.

## Run the demo

The backend is configured for Firebase project `ltdd-bec6d`, database `(default)`. On this machine, its read-only Firestore health endpoint has returned `Healthy`.

Run the backend in terminal 1:

```sh
bash backend/run-demo.sh
```

Username/password sign-in issues a session directly after the backend validates the credentials. Email registration still requires Firebase email verification. Firebase server APIs use local Application Default Credentials (ADC), normally created by `gcloud auth application-default login`; credentials stay outside the repository.

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

Registration sends an email verification link through Firebase Authentication and stores an Employee or Guest account in Firestore after verification. Enable the Email/Password provider in Firebase Authentication. To demo Admin workflows, provision an existing account by changing `users/{sha256(lowercase username)}.role` to `Admin` in Firestore, as described in [`backend/README.md`](backend/README.md). Then sign in, create a worksite and shift, create a QR, and check in from an Employee account. Android needs Internet, camera, and location permissions. The APK built during development is `build/app/outputs/flutter-apk/app-debug.apk`.

Current external setup needed for an Admin workflow demo: an Admin account provisioned by a trusted operator. The debug APK is available, but device-level camera and GPS checks require installing it on an Android device or emulator with those capabilities.
