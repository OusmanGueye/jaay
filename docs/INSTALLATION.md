# Installation et compilation

## Installer l'APK sur le terminal (utilisateur)
1. Copiez `Jaay.apk` sur le terminal (téléchargement, Bluetooth, Google Drive ou `python3 -m http.server` depuis un ordinateur sur le même Wi-Fi).
2. Ouvrez le fichier. Si Android bloque : **Paramètres → Autoriser depuis cette source**.
3. **Installer**, puis **Ouvrir**.
4. Une version déjà installée est mise à jour **sans perdre les données**.

Si l'installation échoue (« application non installée »), désinstallez l'ancienne version puis réinstallez (les données locales seront perdues : sauvegardez en ligne avant).

## Compiler (développeur)
Prérequis : Flutter 3.47+ (Dart ^3.13), JDK 17+, Android SDK (compileSdk 37).

```bash
git clone <ce dépôt> && cd <dossier>
flutter pub get
flutter analyze
flutter test
flutter run
```

### Code d'activation
Le code source public utilise le code de démonstration **`DEMO-2026`**.
Pour une version de production, calculez l'empreinte de votre code :

```bash
python3 -c "import hashlib; print(hashlib.sha256(b'gueye-facturation-v1:VOTRE_CODE').hexdigest())"
flutter build apk --release --dart-define=ACTIVATION_HASH=<empreinte>
```

L'APK est dans `build/app/outputs/flutter-apk/app-release.apk`.

### Signature
Le build release utilise actuellement la clé de **debug**. Pour une diffusion sérieuse, créez un keystore et configurez `signingConfigs.release` dans `android/app/build.gradle.kts` (ne publiez jamais le keystore).

### Sauvegarde en ligne (votre propre Supabase)
1. Créez un projet Supabase.
2. Exécutez `supabase/schema.sql` dans l'éditeur SQL.
3. Remplacez `kSupabaseUrl` et `kSupabaseKey` (clé *publishable*) dans `lib/sync.dart`.
4. Auth → activez e-mail / mot de passe.

## Tests
`flutter test` exécute 23 tests : formats et montants en lettres, quantités, icônes, périodes, activation, ESC/POS et trames, base de données (ventes, tranches, remboursement, stock, journal de synchro, restauration), tickets.
