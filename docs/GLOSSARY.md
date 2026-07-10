# Glossary (ubiquitous language)

Terms of the domain. Use exactly these in code and in conversations.

| Term | Meaning |
|---|---|
| **User** | An account in the application. Also the tenant: every user is their own tenant (ADR-0002). Created by the instance admin, no self-registration. |
| **Instance admin** | A user with the `admin` flag. Manages domains and users and has full access to all links (ADR-0006). |
| **Tenant** | Functionally identical to a user. Isolation is row-based via `owner_id`. |
| **Domain** | A concrete hostname created by the instance admin (e.g. `go.short.example`) under which short links are reachable. Shared by all users (ADR-0003). |
| **Primary domain** | The domain marked as primary (sentinel row). Only there does the dashboard (UI) run; all other domains are pure redirect hosts (ADR-0004). Its hostname comes from `MAIN_DOMAIN` and is synced at boot — changing it moves the dashboard and the links living on it to the new domain. |
| **Wildcard domain** | Pure infrastructure detail: the reverse proxy forwards `*.short.example` wholesale to the app and terminates TLS with a wildcard certificate. In the domain, only concrete domains exist. |
| **Link** | The central entity: belongs to exactly one user, hangs off exactly one domain, maps a slug to a target URL. Optional: expiry date, password protection. |
| **Slug** | The path part of a short link (`go.short.example/<slug>`). Unique per `(domain, slug)` across all users. Either generated or chosen by the user (custom slug). |
| **Reserved slug** | A configured list of slugs that are never handed out (`login`, `admin`, `stats`, …), so UI routes don't collide (ADR-0004). |
| **Root link** | A link on the domain root (`domain/`), stored as an empty slug (`""`). The admin creates it by typing `/` or `@` into the slug field. Only effective on redirect domains (the primary-domain root stays the dashboard). At most one per domain. |
| **Catch-all link** | A domain's fallback link, stored as slug `"*"` (input `/*` or `*`). Catches every request that doesn't hit a concrete slug — including multi-segment paths. A concrete slug and the root link take precedence. At most one per domain. |
| **Target URL** | The long URL a link redirects to. |
| **Expiry date** | An optional point in time from which a link no longer redirects. Expired links respond with 410. No click limit (deliberately rejected). |
| **Password protection** | An optional password on the link. Visitors see an interstitial with a password prompt; only afterwards does the redirect happen. |
| **Click event** | A raw record per click: timestamp, link, IP (unshortened), user agent, referrer. No country/GeoIP (dropped, ADR-0005). Retained for 12 months, then deleted. |
| **Redirect hot path** | The latency-critical path: host + slug → target URL → 301/302. Runs as its own plug with an ETS cache, bypassing Ash (ADR-0001). |
| **QR code** | A server-side generated QR image per link, pointing to the short link. |
