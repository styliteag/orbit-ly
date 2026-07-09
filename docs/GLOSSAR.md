# Glossar (Ubiquitous Language)

Begriffe der Domäne. In Code und Gesprächen genau so verwenden.

| Begriff | Bedeutung |
|---|---|
| **Benutzer** | Ein Konto in der Anwendung. Zugleich der Mandant: Jeder Benutzer ist sein eigener Mandant (ADR-0002). Wird vom Instanz-Admin angelegt, keine Selbstregistrierung. |
| **Instanz-Admin** | Benutzer mit `admin`-Flag. Verwaltet Domains und Benutzer und hat Vollzugriff auf alle Links (ADR-0006). |
| **Mandant** | Fachlich identisch mit Benutzer. Isolation zeilenbasiert über `owner_id` (Ash attribute-Multitenancy). |
| **Domain** | Ein konkreter, vom Instanz-Admin angelegter Hostname (z. B. `go.short.example`), unter dem Kurzlinks erreichbar sind. Von allen Benutzern gemeinsam genutzt (ADR-0003). |
| **Hauptdomain** | Die als primär markierte Domain. Nur dort läuft das Dashboard (UI); alle anderen Domains sind reine Redirect-Hosts (ADR-0004). |
| **Wildcard-Domain** | Reines Infrastruktur-Detail: Der Reverse Proxy leitet `*.short.example` pauschal an die App und terminiert TLS per Wildcard-Zertifikat. Fachlich existieren nur konkrete Domains. |
| **Link** | Die zentrale Entität: gehört genau einem Benutzer, hängt an genau einer Domain, bildet einen Slug auf eine Ziel-URL ab. Optional: Ablaufdatum, Passwortschutz. |
| **Slug** | Der Pfadteil eines Kurzlinks (`go.short.example/<slug>`). Eindeutig pro `(Domain, Slug)` über alle Benutzer. Entweder generiert oder vom Benutzer gewählt (Custom Slug). |
| **Reserved Slug** | Konfigurierte Liste von Slugs, die nie vergeben werden (`login`, `admin`, `stats`, …), damit UI-Routen nicht kollidieren (ADR-0004). |
| **Root-Link** | Ein Link auf die Domain-Wurzel (`domain/`), gespeichert als leerer Slug (`""`). Admin legt ihn an, indem er `/` oder `@` ins Slug-Feld tippt. Nur auf Redirect-Domains wirksam (die Hauptdomain-Wurzel bleibt das Dashboard). Höchstens einer pro Domain. |
| **Catch-all-Link** | Fallback-Link einer Domain, gespeichert als Slug `"*"` (Eingabe `/*` oder `*`). Fängt jede Anfrage, die keinen konkreten Slug trifft — auch mehrsegmentige Pfade. Konkreter Slug und Root-Link haben Vorrang. Höchstens einer pro Domain. |
| **Ziel-URL** | Die lange URL, auf die ein Link weiterleitet. |
| **Ablaufdatum** | Optionaler Zeitpunkt, ab dem ein Link nicht mehr weiterleitet. Abgelaufene Links antworten mit 410. Kein Klick-Limit (bewusst verworfen). |
| **Passwortschutz** | Optionales Passwort am Link. Besucher sehen eine Zwischenseite (Interstitial) mit Passwortabfrage, erst danach erfolgt die Weiterleitung. |
| **Klick-Event** | Roh-Datensatz pro Klick: Zeitstempel, Link, IP (unverkürzt), User-Agent, Referrer. Kein Land/GeoIP (gestrichen, ADR-0005). Aufbewahrung 12 Monate, dann Löschung. |
| **Redirect-Hotpath** | Der latenzkritische Pfad: Host + Slug → Ziel-URL → 301/302. Läuft als eigener Plug mit ETS-Cache an Ash vorbei (ADR-0001). |
| **QR-Code** | Serverseitig generiertes QR-Bild pro Link, zeigt auf den Kurzlink. |
