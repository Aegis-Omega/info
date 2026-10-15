# AEGIS Local Desk 0.1

Lokalni radni prostor koji možeš koristiti bez ChatGPT work kredita.
Desktop dio radi s Python 3.10+ bez pip paketa, pretplate ili API ključa.
Apple dio je nativni iPhone/iPad projekt za lokalni Apple model.
Nijedan dio ne mijenja GitHub granu niti pokreće Actions.

**Bez vlastitog Maca:** vidi `BEZ_MACA.md`. Priložen je zaseban macOS CI job za
Xcode build i simulator launch. On radi tek nakon objave ovog alata u vlastiti
repo i pokretanja joba; ne koristi RH repozitorij.

## 1. Računar / WSL: odmah upotrebljiv dio

Raspakuj ZIP. U terminalu otvori raspakovani `aegis-local-desk` direktorij:

```bash
python3 desk.py --repo /apsolutna/putanja/do/formal-conjectures
```

Na Windowsu bez WSL-a: `py -3 desk.py --repo "C:\putanja\formal-conjectures"`.
Otvori ispisani `http://127.0.0.1:8765`. Ako browser nije automatski otvoren,
prepiši tu adresu. Zaustavljanje: Ctrl+C u terminalu.
Ako port nije slobodan, dodaj `--port 8766`.

Repo i Lean toolchain moraju već biti dostupni na tvom računaru. Ovaj mali ZIP
ne sadrži cijeli RH korpus, Lean, Mathlib, OLEAN cache ili težine modela.
Pretraga i bilješke rade bez modela. Koristi postojeći checkout najjače grane;
alat ne radi automatski clone/pull/push.

Funkcije:

- Korpus: pretražuje .lean/.src/.md/.txt/.json/.py, uz putanje i linije;
  preskače build direktorije, symlinkove i pojedinačne fajlove veće od 8 MB.
- Bilješke: lokalni append-only JSONL dnevnik. Kopija nije vezana za ovu sesiju.
- Lean: kompajlira izabrani source i dodaje `#print axioms` izabrane deklaracije.
  Odbija greške, upozorenja, sorryAx, nestandardne aksiome i nedostajuće izvještaje.
  Jedna provjera istovremeno, najviše 180 sekundi. Postojeći lokalni import
  artefakti nisu ovim provenijencijski auditirani: ovo nije zamjena za exact-head CI.
  PASS ne utvrđuje da teorem nema hipoteze niti da dokazuje RH.
- 8 × 8: svih 64 uređenih parova trigrama i tačan cjelobrojni Walsh račun
  HᵀH = 8I. To je konačna algebra; samo po sebi ne daje znak Weilovog oblika.
- Model: ručno izabran već instalirani lokalni Ollama model; nijedna njegova
  naredba ili izmjena koda ne izvršava se automatski.

Podaci se čuvaju u `~/AEGIS-Local-Data/journal.jsonl`, izvan repozitorija.
Po želji dodaj `--data /putanja/za/trajne/podatke`. Sačuvaj backup cijelog tog
direktorija. Browser izvoz sadrži posljednjih 100 zapisa; puni dnevnik je JSONL.
Sama kopija datoteka u ChatGPT-u nije stalno uključen proces: program radi dok
je tvoj računar uključen i aplikacija pokrenuta.

### Opcionalni lokalni razgovor

Instaliraj Ollama iz službenog izvora i preuzmi lokalni model koji može stati
u tvoju slobodnu RAM memoriju. Na računaru sa 8 GB RAM-a prvo izmjeri potrošnju
malog kvantizovanog modela; ne pokreći istovremeno model i veliki Lean build.
Ne pretpostavljamo podršku za RX 570 niti je zahtijevamo.

Pokreni Ollama s isključenim cloud funkcijama:

```bash
OLLAMA_NO_CLOUD=1 ollama serve
```

Ako Ollama već radi kao servis/aplikacija, postavi `OLLAMA_NO_CLOUD=1` za taj
proces i restartuj ga prema službenoj dokumentaciji. Program se spaja isključivo
na `127.0.0.1:11434`, ne preuzima modele, ne koristi API ključ, odbija cloud
oznake i remote metadata. Najjednostavnija provjera offline rada: isključi
internet poslije preuzimanja i probaj razgovor. Preuzimanje modela i električna
energija imaju svoje resursne troškove; nema ChatGPT token naplate za ovaj alat.

### Provjere

```bash
python3 -m unittest -v
```

Testovi provjeravaju svih 64 parova/Walsh identitet, fail-closed axiom parser,
trajnost dnevnika, ograničenje putanja i simulirane Lean rezultate. Pravi Lean
replay nije izvršen u okruženju u kojem je ovaj alat napravljen jer toolchain
i korpus tu trenutno nisu instalirani. Ollama inference nije ovdje testiran.

## 2. iPhone/iPad: Apple Foundation Models

U `Apple/AEGISLocal.xcodeproj` je kompletan mali SwiftUI projekt bez vanjskih
paketa. Cilj iOS/iPadOS 26+. Uključuje:

- trajnu bilješku i dnevnik odgovora u app sandboxu;
- uvoz UTF-8 Lean/tekst izvora kroz Files (do 2 MB po fajlu);
- pretragu s linijama;
- lokalnu generaciju preko `SystemLanguageModel` / `LanguageModelSession`;
- provjeru dostupnosti Apple modela, obradu grešaka i JSON backup kroz Share;
- bez serverskih ključeva, plaćenog modelskog API-ja ili GitHub integracije.

**Status Apple dijela: source pripremljen; nije kompajliran niti potpisan.**
Ovo Linux okruženje nema Xcode/Apple SDK, pa nema tvrdnje da build ili rad na
uređaju prolazi. Treba obaviti sljedeće na Macu s Xcode 26 ili novijim:

1. Otvori `Apple/AEGISLocal.xcodeproj` u Xcodeu.
2. Settings → Accounts: dodaj svoj Apple Developer račun.
3. Target → Signing & Capabilities: izaberi svoj Team; promijeni bundle ID
   u jedinstveni identifikator pod tvojim računom.
4. Izaberi povezani iPhone; uključi Developer Mode ako Xcode to zatraži.
5. Product → Build, zatim Run. Ispravi eventualne SDK kompatibilnosti prije distribucije.
6. Na kompatibilnom uređaju uključi Apple Intelligence i završi preuzimanje
   modela. Ako je model nedostupan, bilješke i izvori i dalje rade.
7. Provjeri bilješke poslije ponovnog pokretanja, uvoz fajla, razgovor bez
   interneta i izvoz JSON backupa. BHS podrška zavisi od modela: engleski je
   početno uključen, a jezičke greške se prikazuju.

Developer članstvo omogućava razvojne/distribucijske postupke, ali samo po sebi
ne instalira ovu aplikaciju i ne zamjenjuje Mac/Xcode. Nema podešavanja App Store
Connecta, potpisivanja, uploada ni dodatnog plaćenog servisa u ovom paketu.
Apple aplikacija ne izvršava Lean kernel. Desktop provjera ostaje odvojena.
Prije brisanja aplikacije obavezno izvezi backup; reinstalacija može obrisati
lokalne podatke. JSON izvoz je čitljiv arhiv; ova verzija nema automatski restore
ni sinhronizaciju desktopa i iPhonea.

## 3. Kontinuitet rada

U `CONTINUITY.md` su posljednji potvrđeni zeleni head i tvoje ideje označene
kao ideje, odvojeno od provjerenih teorema. Promjene i modelsku sugestiju prvo
zapiši; tek odvojena provjera može dati dokazni rezultat.

## Službeni izvori API-ja (provjereni 2026-10-16 po Sarajevo vremenu)

- https://developer.apple.com/foundation-models-framework/
- https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
- https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- https://docs.ollama.com/api/chat
- https://docs.ollama.com/faq

## Licenca

Kod ovog alata: MIT, vidi LICENSE. Uvezeni izvori i modeli zadržavaju svoje licence.
