# Vipps Spill — drop-ready ZIP

Uoffisielt spill inspirert av skjermbildene dine. Alle kroner, kort, lønninger og betalinger er lekepenger. Ingen BankID, ekte kort eller banktilkobling.

## Rask start / Vercel
1. Pakk ut ZIP-en og last opp innholdet til et GitHub-repository.
2. Importer repositoryet i Vercel. Framework: Other. Build: `npm run build`. Output: `dist`.
3. Deploy. Ingen pakker eller installasjon kreves.

Du kan også laste innholdet i `dist/` direkte opp til en statisk HTTPS-host. ZIP-en inneholder ferdig bygget `dist/` i tillegg til kildekoden. Netlify Drop: dra inn `dist/`.

## Venner på forskjellige telefoner (engangsoppsett)
Uten dette kjører appen lokal demo. Demo-venner er testprofiler, og lokale betalinger overføres ikke til andre telefoner.

1. Opprett et eget Supabase-prosjekt for dette spillet.
2. Kjør hele `supabase-setup.sql` én gang i SQL Editor.
3. Aktiver e-post/passord under Authentication. Bruk e-postbekreftelse, eller skru den av for et privat testspill. Sett Site URL til nettsiden din.
4. Fra Project Settings / API kopierer du prosjekt-URL og PUBLIC publishable key.
5. Sett disse i `config.js`:
   ```js
   window.APP_CONFIG = {
     SUPABASE_URL: 'https://DITT-PROSJEKT.supabase.co',
     SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_DIN_OFFENTLIGE_NOKKEL'
   };
   ```
6. Bygg/deploy på nytt. Ved direkte statisk opplasting må også `dist/config.js` oppdateres.
7. Hver venn oppretter konto på samme nettside. Deretter finnes de i Sosialt og Send. Du kan endre brukernavnet under profilbildet. Startnavn får en unik kode for å unngå kollisjoner.

Bruk aldri secret/service-role key i config.js. Databasen styrer saldo, lønn og kjøp. En betaling gjøres samlet og låst på serveren, og har en unik ID mot duplikater. Alle kontakter viser bare brukernavn og bilde; saldo og historikk er private. Nye kontoer får 1 000 lekekroner.

## Timelønn og oppgraderinger
- Grunninntekt: 10 kr/min = 600 kr/time.
- Opptjening går også mens appen er lukket. Hele timer betales ved neste åpning/synkronisering; i åpen app sjekkes dette hvert 15. sekund.
- Oppgraderinger øker inntekt per minutt. Utbetaling er fortsatt hver time fra kontoopprettelse.
- 4 typer kan oppgraderes uten et fast maks nivå. Kostnad = grunnpris × (nivå + 1)². Inntekt øker med 2, 8, 30 eller 120 kr/min per kjøp.
- Tid før et kjøp blir regnet med gammel inntekt. Ingen retroaktiv bonus.
- Profilbilder opp til 20 MB krympes automatisk til et 256 × 256 profilbilde.

## Hjemskjerm på iPhone
Åpne HTTPS-nettsiden i Safari → Del → Legg til på Hjem-skjerm. Appen åpnes uten vanlig nettleserlinje, med smileikonet fra referansen. Android: Installer app / Legg til på startskjermen. Operativsystemet bestemmer ikonets avrunding. Hvis gammelt ikon vises, fjern snarveien og legg den til igjen.

## Lokal kjøring
Node 20 eller nyere: `npm start`, åpne http://localhost:3000. `npm run build` lager `dist/`. Lokal demo bruker nettleserlagring. Multiplayer krever internett og Supabase. Skann-knappen finner venner fra brukernavn eller vennelenke, ikke kamera/ekte Vipps-QR.

## Verifisering
Kildekode, produksjonsbygg og inntektsberegninger er kontrollert lokalt. Database-skriptet er testet i lokal PostgreSQL (PGlite), inkludert overføringer, duplikatvern, oppgraderinger, forespørsler, lønn og tilgangskontroll. Full flerbrukertest mot din eksterne database må gjøres etter tilkobling. Interaksjoner er testet i en DOM-test: navigasjon, kjøp, sending, historikk og lagring av profil. Visuell nettlesertest kunne ikke kjøres fordi nettlesernedlastingen feilet. Ingen konto eller database er opprettet eller endret for deg.
