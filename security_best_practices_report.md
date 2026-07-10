# Security-Review vor der Veröffentlichung

Stand: 2026-07-10

## Executive Summary

Die Anwendung hat bereits eine gute Sicherheitsbasis: keine offene Registrierung, explizite Auth-/Admin-Hooks für alle geschützten LiveViews, UUIDs als öffentliche IDs, erneuerte Sessions beim Login, gehashte Reset-Tokens, HTTPS-/Secure-Cookie-Konfiguration, CSRF-Schutz im Browser-Pipeline, eine restriktive CSP und validierte HTTP(S)-Redirect-Ziele.

Der Review identifizierte drei anonym ausnutzbare Availability-Probleme. Sie wurden am 2026-07-10 mit Regressionstests behoben:

1. Der Redirect-Cache wuchs bei neuen Host-/Slug-Misses ohne Obergrenze und entfernte abgelaufene Einträge nicht.
2. Die Click-Tracking-Queue hatte eine unbeschränkte Mailbox und persistierte jeden öffentlichen Treffer.
3. Der ETS-Rate-Limiter prüfte und erhöhte Zähler nicht atomar; parallele Requests konnten das Limit überschreiten.

Datenschutz und Release-Supply-Chain bleiben vor dem ersten öffentlichen Release zu härten. Der Produktions-Mailer und der Reset-Token-Lebenszyklus sind nun technisch vorbereitet; ein echter Zustelltest mit dem gewählten SMTP-Provider bleibt Teil des Deployments.

## Scope und durchgeführte Prüfungen

Geprüft wurden die anonym erreichbaren HTTP-/LiveView-Flows, Redirect-Auflösung, Passwortschutz, Login und Passwort-Reset, Session-/Token-Handling, Proxy-IP-Ermittlung, Security Header, CSP, Produktionskonfiguration, Docker-Image und Release-Workflow.

Validierung:

- `docker compose run --rm app mix precommit`: 170 Tests erfolgreich nach der Umsetzung von ORB-SEC-001 bis 005.
- `docker compose run --rm app mix hex.audit`: keine zurückgezogenen Pakete oder bekannten Hex-Security-Advisories.
- Produktions-Image lokal erfolgreich gebaut. Das Release startete mit vollständiger SMTP-Runtime-Konfiguration inklusive Migrationen und Endpoint; ohne SMTP-Pflichtvariablen brach es wie vorgesehen vor dem Start ab.
- Docker Scout nach dem Runtime-Hardening: 113 Pakete, 0 Critical, 0 High, 1 Medium, 23 Low und 3 nicht eingestufte Findings. Das verbliebene Medium-Finding betrifft `tar`, das die Anwendung nicht aufruft. Das Image wurde zusätzlich ohne Perl gestartet; Migrationen und die vollständige OTP-Anwendung liefen erfolgreich an.

## Hohe Priorität / Release-Blocker

### ORB-SEC-001: Unbeschränkter Redirect-Cache erlaubt anonymen Memory-DoS

**Status:** Behoben am 2026-07-10. Der Cache besitzt jetzt eine harte, konfigurierbare Maximalgröße, aktive TTL-Sweeps, einen geschützten ETS-Schreibpfad und Regressionstests für eindeutige Misses und ungelesene abgelaufene Keys.

**Auswirkung:** Ein nicht angemeldeter Angreifer kann mit zufälligen Slugs auf einer bekannten Domain fortlaufend DB-Lookups und dauerhaft verbleibende ETS-Einträge erzeugen, bis der BEAM-Speicher erschöpft ist und der Dienst ausfällt.

**Beleg:** `lib/orbitly/shortener/redirect_cache.ex:19-20,25-38,42-53,66-83`. Positive und negative Domain-/Slug-Lookups werden in einer öffentlichen ETS-Tabelle gespeichert. Der TTL wird nur beim erneuten Lesen desselben Keys geprüft. Es gibt keinen Sweep, kein LRU, keine maximale Tabellengröße und keine Entfernung abgelaufener, nie erneut gelesener Keys. `flush/0` läuft nur bei einer Domain-/Link-Mutation.

**Angriffspfad:** Wiederholte Requests wie `/random-<nonce>` auf einer gültigen Redirect-Domain. Jeder neue, formal gültige Slug umgeht den Nutzen des Negative Cache, löst einen DB-Lookup aus und fügt einen neuen Key ein. Bei der optional dokumentierten Catch-all-Proxy-Regel können zusätzlich zufällige Hostnamen den Domain-Cache füllen.

**Empfehlung:**

- Cache strikt begrenzen und abgelaufene Einträge aktiv entfernen, beispielsweise mit periodischem Sweep plus harter Maximalgröße oder einem bewährten bounded TTL/LRU-Cache.
- Negative Link-Lookups entweder nicht cachen oder in einem deutlich kleineren, separat begrenzten Cache halten.
- Unbekannte Hosts nicht dauerhaft negativ cachen; im Proxy konkrete Hosts bevorzugen.
- Regressionstest: Nach sehr vielen eindeutigen Misses bleibt die ETS-Größe unter dem festgelegten Maximum; abgelaufene Keys verschwinden ohne erneuten Zugriff.
- Ergänzend Rate-Limits am Edge/Traefik setzen. Das ersetzt den bounded Cache nicht.

### ORB-SEC-002: Unbeschränkte Click-Queue und persistenter Write-Amplifier

**Status:** Behoben am 2026-07-10. Ein atomarer Admission-Counter begrenzt Mailbox plus Buffer. Überzählige Events werden best-effort verworfen und per Telemetrie gezählt; IP, User-Agent und Referrer werden bereits vor dem Enqueue begrenzt.

**Auswirkung:** Ein Angreifer kann durch wiederholte Aufrufe eines öffentlichen Links die GenServer-Mailbox, den Anwendungsspeicher und die SQLite-Schreiblast unbeschränkt erhöhen und zusätzlich die Datenbank füllen.

**Beleg:** `lib/orbitly_web/plugs/redirector.ex:119-136` erfasst jeden erfolgreichen Redirect. `lib/orbitly/shortener/click_buffer.ex:19-20,32-40,48-52,66-73` nutzt asynchrone `GenServer.cast/2`. `@max_buffer 500` begrenzt nur die bereits abgearbeitete State-Liste, nicht die Prozess-Mailbox; jeder Hit wird anschließend als Rohdatensatz geschrieben. `priv/repo/migrations/20260709000000_create_initial_schema.exs:63-73` speichert IP, User-Agent und Referrer pro Klick.

**Empfehlung:**

- Click-Erfassung als best-effort, bounded Queue implementieren und bei Überlast kontrolliert droppen; der Redirect selbst muss weiter funktionieren.
- Mailbox-/Queue-Länge und Dropped-Event-Zähler als Telemetrie ausgeben und alarmieren.
- User-Agent/Referrer vor dem Enqueue auf eine kleine feste Länge begrenzen.
- Prüfen, ob aggregierte Zähler oder Sampling den Produktbedarf erfüllen, statt jeden Hit dauerhaft zu speichern.
- Belastungstest mit hoher Parallelität und festem Speicherlimit ergänzen.

### ORB-SEC-003: Rate-Limiter ist unter Parallelität umgehbar

**Status:** Behoben am 2026-07-10. Entscheidungen laufen serialisiert über den Owner-GenServer, Einträge tragen ihr tatsächliches Ablaufdatum, und ein Parallelitätstest beweist, dass nur exakt das konfigurierte Limit freigegeben wird.

**Auswirkung:** Parallele Login- oder Unlock-Versuche können deutlich mehr teure Bcrypt-Prüfungen auslösen als konfiguriert und damit Brute Force sowie CPU-DoS erleichtern.

**Beleg:** `lib/orbitly/shortener/rate_limiter.ex:20-31` liest zuerst den alten Zähler, erhöht ihn danach atomar, entscheidet aber anhand des zuvor gelesenen Werts. Viele gleichzeitige Aufrufer können denselben alten Wert sehen und jeweils erlaubt werden. Betroffen sind `POST /session` über `lib/orbitly_web/plugs/auth_rate_limit.ex:14-29` und Passwort-Unlocks über `lib/orbitly_web/plugs/redirector.ex:97-114`.

**Empfehlung:**

- Inkrement und Entscheidung serialisieren, etwa durch einen `GenServer.call/2`, oder das Ergebnis eines atomaren `:ets.update_counter/4` prüfen und den Window-Reset ebenfalls racesicher machen.
- Separate Limits für IP und Zielkonto/Link kombinieren; Edge-Limit in Traefik ergänzen.
- Einen echten Parallelitätstest mit gleichzeitig freigegebenen Tasks hinzufügen; nicht nur sequenzielle Requests testen.

## Mittlere Priorität

### ORB-SEC-004: Passwort-Reset-Limit läuft zu früh ab; Reset-Tokens sammeln sich an

**Status:** Behoben am 2026-07-10. Rate-Limit-Einträge werden anhand ihres tatsächlichen Windows bereinigt. Nach erfolgreicher Zustellung bleibt pro Benutzer genau ein Reset-Token aktiv. Schlägt die Zustellung fehl oder wirft der Adapter eine Exception, wird nur der neu erzeugte Token entfernt und ein zuvor erfolgreich zugestellter Token bleibt gültig.

**Beleg:** Der Reset fordert 3 Requests pro 60 Minuten (`lib/orbitly_web/live/user_forgot_password_live.ex:37-63`). Der generische Sweeper löscht jedoch alle Keys, die älter als fünf Minuten sind (`lib/orbitly/shortener/rate_limiter.ex:12,48-62`), unabhängig vom Window des Eintrags. Dadurch wird das Stundenlimit nach spätestens etwa zehn Minuten zurückgesetzt. Jeder erlaubte Request für eine existierende Adresse legt vor dem Mailversand einen weiteren Token an (`lib/orbitly/accounts.ex:82-87`); abgelaufene, unbenutzte Reset-Tokens werden nicht regelmäßig bereinigt.

**Empfehlung:** Pro Eintrag ein Ablaufdatum bzw. Window speichern und danach sweepen; Reset zusätzlich pro IP und normalisierter Adresse limitieren; vor dem Erzeugen eines neuen Reset-Tokens ältere Reset-Tokens des Users löschen oder upserten; abgelaufene Tokens regelmäßig purgen.

### ORB-SEC-005: Produktions-Mailer versendet keine echten Reset-Mails

**Status:** Behoben am 2026-07-10. Produktion überschreibt den lokalen Adapter mit dem generischen SMTP-Adapter. Relay, Credentials, Absender und Port kommen ausschließlich aus Runtime-Umgebungsvariablen; fehlende Pflichtwerte verhindern einen unsicheren Fehlstart. Authentifiziertes STARTTLS wird erzwungen und das Relay-Zertifikat geprüft. Delivery-Fehler werden intern protokolliert und hinterlassen keinen neuen nutzbaren Reset-Token. Die öffentliche Antwort bleibt absichtlich generisch.

**Beleg:** Der globale Mailer bleibt auf `Swoosh.Adapters.Local` (`config/config.exs:47-54`), während Produktion nur den lokalen Speicher deaktiviert (`config/prod.exs:26-30`). Ein externer Produktionsadapter, Absender und Credentials werden nicht gesetzt. Der anonyme Flow zeigt trotzdem immer Erfolg und ignoriert den Delivery-Rückgabewert (`lib/orbitly_web/live/user_forgot_password_live.ex:42-57`).

**Risiko:** Account-Recovery funktioniert nach dem Release nicht zuverlässig. Gleichzeitig können DB-Tokens entstehen, obwohl keine Mail zugestellt wurde.

**Empfehlung:** Produktionsadapter und `FROM_EMAIL` über Runtime-Umgebung konfigurieren, Delivery-Fehler intern loggen/monitoren, bei fehlgeschlagener Zustellung den neu erzeugten Token wieder entfernen und einen Integrationstest gegen einen Test-/Sandbox-Provider ausführen. Die öffentliche Antwort soll weiterhin keine Account-Existenz verraten.

### ORB-SEC-006: Roh-IP, User-Agent und Referrer werden zwölf Monate gespeichert

**Beleg:** `lib/orbitly/shortener/click_event.ex:1-23`, `lib/orbitly_web/plugs/redirector.ex:129-136` und `lib/orbitly/shortener/click_retention.ex:1-52`.

**Risiko:** Das erhöht den Schaden bei DB-/Backup-Verlust und erzeugt Datenschutzpflichten für jeden anonymen Besucher. Der Kommentar nennt eine Rechtsgrundlage, aber im Repository sind keine öffentliche Datenschutzerklärung, Einwilligungs-/Widerspruchsentscheidung oder Backup-Löschstrategie ersichtlich.

**Empfehlung:** Daten minimieren: IP sofort kürzen oder keyed-hashen, Referrer-Query entfernen, Feldlängen begrenzen und kürzere Aufbewahrung erwägen. Datenschutzerklärung, Rechtsgrundlage, Auftragsverarbeitung, Auskunft/Löschung und Löschung aus Backups mit Datenschutzberatung klären. Dies ist keine Rechtsberatung.

### ORB-SEC-007: Finales Image enthält drei hoch bewertete Perl-CVEs

**Status:** Behoben am 2026-07-10. Die Runtime verwendet jetzt das eingebaute `C.UTF-8`, installiert das große `locales`-Paket nicht mehr und entfernt `perl-base` erst nach der vollständigen Konfiguration aller Runtime-Pakete und CA-Zertifikate. Das finale Image führt keine Paketverwaltung mehr aus. Ein Starttest der vollständigen Anwendung inklusive Migrationen war erfolgreich; die drei Perl-Findings sind verschwunden und Docker Scout meldet 0 Critical sowie 0 High Vulnerabilities.

**Ursprünglicher Beleg:** Docker Scout meldete für `perl 5.40.1-6` im damaligen Debian-Trixie-Image `CVE-2026-12087` (Critical), `CVE-2026-48959` und `CVE-2026-48962` (High). Perl war unter `/usr/bin/perl` vorhanden, wurde von Orbit-ly aber nicht aufgerufen.

**Bewertung:** Kein belegter anonymer Angriffspfad durch die Anwendung; die verwundbaren Perl-Funktionen benötigen Perl-Aufrufe mit speziell präparierten Daten. Trotzdem sollte unnötige Runtime-Software nicht mit ausgeliefert werden.

**Umsetzung:** `locales`/`locale-gen` wurden entfernt und durch `C.UTF-8` ersetzt. Weil Debian Slim weiterhin das essentielle `perl-base` mitbringt, wird es gezielt am Ende der Paketinstallation entfernt. Diese Reihenfolge erhält funktionierende CA-Zertifikate und OpenSSL, während die unveränderliche Runtime ohne apt/dpkg-Nutzung und ohne Perl ausgeliefert wird.

## Niedrige Priorität / Hardening

### ORB-SEC-008: Unlock-HTML umgeht Browser-Security-Pipeline

**Beleg:** `OrbitlyWeb.Redirector` läuft vor dem Router (`lib/orbitly_web/endpoint.ex:49-58`) und rendert das Passwortformular direkt (`lib/orbitly_web/plugs/redirector.ex:173-195`). Dadurch erhält diese Seite nicht `put_secure_browser_headers` und nicht die anwendungseigene CSP aus dem Browser-Pipeline. Das Formular enthält aktuell keine untrusted HTML-Interpolation, daher ist das unmittelbare XSS-Risiko niedrig.

**Empfehlung:** Gemeinsame Security Header vor dem Redirector setzen oder auf der Unlock-Antwort explizit eine restriktive CSP, `nosniff`, Referrer-Policy und `frame-ancestors 'none'` ausgeben.

### ORB-SEC-009: Release-Supply-Chain ist weniger nachvollziehbar als möglich

**Beleg:** GitHub Actions werden nur auf Major-Tags statt vollständige Commit-SHAs gepinnt (`.github/workflows/release.yml:45-47,62-74,95-97,116-151,177-178`). Container-Provenance und SBOM werden explizit deaktiviert (`.github/workflows/release.yml:72-87`; ebenso `build-and-push.sh:132-140`). Die Docker-Basis wird über Tags statt im Dockerfile festgeschriebene Digests gewählt.

**Empfehlung:** Actions auf vollständige geprüfte SHAs pinnen und per Dependabot/Renovate aktualisieren; `provenance: mode=max` und `sbom: true` aktivieren; veröffentlichte Images zusätzlich attestieren/signieren; Base-Image-Digests automatisiert aktualisieren und regelmäßig scannen.

## Wichtige positive Kontrollen

- Alle geschützten LiveViews deklarieren `live_user_required` oder `live_admin_required`; die Context-Funktionen prüfen Link-Ownership zusätzlich.
- Keine offene Registrierung; Benutzer werden durch Admins angelegt.
- Session-Fixation-Schutz durch Session-Renewal beim Login; Logout invalidiert das serverseitige Session-Token.
- Reset-Tokens sind zufällig, kurzlebig und in der DB gehasht; Passwortänderungen löschen alle Sessions/Tokens.
- Login-Antwort und Passwort-Reset-Antwort vermeiden Account-Enumeration.
- Ziel-URLs werden auf absolute `http`/`https`-URLs beschränkt; kein serverseitiges Fetching beim Redirect.
- Phoenix escaping wird nicht durch `raw/1` umgangen; keine offensichtlichen XSS-/SQL-Injection-Sinks gefunden.
- Produktion erzwingt HTTPS, Secure Session Cookies und unbekannte Hosts liefern standardmäßig 404.
- CSP, CSRF und Standard-Browser-Header sind für normale UI-Routen aktiv.
- Das finale Container-Image läuft als `nobody`; der App-Port wird im Produktions-Compose nicht direkt auf den Host veröffentlicht.
- `mix hex.audit` war am Prüftag sauber.

## Deployment-Checkliste vor Go-live

1. ORB-SEC-001 bis 003 sind behoben; vor Go-live zusätzlich einen externen Lasttest gegen eine produktionsnahe Instanz ausführen.
2. SMTP-Variablen setzen und einen echten Reset-End-to-End-Test einschließlich Zustellung durchführen; SPF/DKIM des Absenders prüfen.
3. Nur konkrete Traefik-Hosts routen; die Catch-all-Regel nicht ohne harte Host-/Rate-Grenzen verwenden.
4. Sicherstellen, dass der einzige direkte Netzwerkpfad zur App über den vertrauenswürdigen Proxy führt und dieser `X-Forwarded-*` kontrolliert setzt. `TRUSTED_PROXY_HOPS` muss exakt zur Kette passen.
5. SQLite-Volume und Backups verschlüsseln/schützen; Restore testen; Retention und Token-/Click-Löschung auch für Backups definieren.
6. Starkes, einmaliges Admin-Passwort verwenden; den Beispielwert nie produktiv einsetzen. Für Admins mittelfristig MFA oder externes SSO erwägen.
7. Speicher, BEAM-Mailboxen, 429-Raten, SQLite-Größe, Click-Drops, Mail-Fehler und 5xx alarmieren.
8. Runtime-Image ist bereinigt und erneut ohne Critical-/High-Findings gescannt; SBOM/Provenance beim Release noch aktivieren.

## Referenzen

- [Phoenix 1.8 Security Guide](https://hexdocs.pm/phoenix/1.8.0/security.html)
- [Phoenix LiveView Security Model](https://phoenix-live-view.hexdocs.pm/security-model.html)
- [Plug HTTPS / Proxy-Hardening](https://hexdocs.pm/plug/https.html)
- [Plug.SSL / Forwarded Headers](https://hexdocs.pm/plug/Plug.SSL.html)
- [Swoosh Adapter- und Produktionskonfiguration](https://hexdocs.pm/swoosh/)
- [GitHub Actions Security Hardening](https://docs.github.com/en/code-security/tutorials/secure-your-organization/protect-against-threats)
- [Docker Build Attestations](https://docs.docker.com/build/metadata/attestations/)
- [Debian Tracker: CVE-2026-12087](https://security-tracker.debian.org/tracker/CVE-2026-12087)
- [Debian Tracker: CVE-2026-48959](https://security-tracker.debian.org/tracker/CVE-2026-48959)
- [Debian Tracker: CVE-2026-48962](https://security-tracker.debian.org/tracker/CVE-2026-48962)
