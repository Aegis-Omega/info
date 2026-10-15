# iPhone aplikacija bez vlastitog Maca

Vlastiti Mac nije potreban. Xcode se izvršava na udaljenom macOS računaru.
Ovaj paket sadrži GitHub Actions job na standardnom `macos-26` runneru.
Build simulatora ne zahtijeva Apple certifikate ni API ključeve.

## Pokretanje builda

1. Napravi zaseban GitHub repozitorij za ovaj alat, npr. `aegis-local-desk`.
   Javni repozitorij koristi besplatni standardni macOS runner prema službenoj
   GitHub dokumentaciji. Privatni repo može trošiti uključene minute ili novac;
   ovaj paket ne mijenja billing. Ne stavljaj proof korpus ili privatne podatke
   u javni repo: ovaj paket sadrži samo mali alat i javni checkpoint kontekst.
2. Objavi sadržaj direktorija `aegis-local-desk` u korijenu novog repozitorija,
   uključujući `.github/workflows/apple-simulator.yml` i `.gitignore`.
   Ako uploader izostavi skrivene direktorije, u GitHub editoru napravi fajl
   tačno pod `.github/workflows/apple-simulator.yml` i zalijepi njegov sadržaj.
3. Actions → Apple simulator build → Run workflow. Push Apple izvora također
   pokreće jedan build. Workflow mora biti na default grani za ručni Run gumb.
4. Job provjerava projekt, kompajlira bez potpisivanja, instalira i pokreće
   aplikaciju u dostupnom iOS >=26 simulatoru i sačuva screenshot.
5. Preuzmi `apple-simulator-SHA-RUNID` artefakt: source SHA, Xcode/SDK verzije,
   source hashovi, build log, launch log i screenshot. Tek stvarni uspješan run
   daje build/launch PASS. Ovaj paket još nije izvršen na macOS runneru.

Nema izmjena u `formal-conjectures`, njegovim granama ili workflowima.
Lokalna provjera YAML/shell/XML strukture ne zamjenjuje Xcode build.
Simulator launch i screenshot nisu funkcionalni UI testovi niti dokaz da Apple
model radi u simulatoru. Inferenciju treba provjeriti zasebno na podržanom uređaju.

## Instalacija na stvarni iPhone nakon zelenog builda

Simulator `.app` ne može se instalirati na stvarni iPhone. Potrebni su zasebni
device archive, Apple potpisivanje i distribucija. Tvoj Developer račun može se
koristiti za to na udaljenom Macu.

Putanja je: registracija jedinstvenog Bundle ID-a → App Store Connect app zapis
→ certifikat/provisioning → archive i export potpisanog IPA → upload → TestFlight.
Službene upute Applea dopuštaju upload preko command-line Transportera/API-ja;
Codemagic ima dokumentovan automatski signing bez vlastitog Maca.

U ovom paketu namjerno još nema automatskog signing/upload joba: Team ID, stvarni
Bundle ID, app zapis i signing konfiguracija nisu potvrđeni. Prvo treba Xcode
compile rezultat, pa konkretan potpisani artefakt za provjeru. Ne šalji privatne
`.p8`/`.p12` ključeve u chat ili repo; signing podaci idu u odgovarajuće secrets
izabranog CI servisa. Paket ne kreira certifikate, ne aktivira billing i ništa
ne šalje u App Store Connect.

## Službeni izvori

- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://docs.codemagic.io/flutter-code-signing/ios-code-signing/

Provjereno 2026-10-16 Sarajevo. Runner image se može mijenjati; svaki run zato
čuva stvarnu verziju Xcodea i SDK-a.
