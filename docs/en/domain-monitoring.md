# Domain monitoring

← [Back to README](../../README.md) · English | [Türkçe](../tr/domain-monitoring.md)

**Domain Monitoring** checks domains and HTTP(S) addresses from the Horus server: reachability, response time,
uptime over 24 hours / 7 days / 30 days and the TLS certificate (expiry, issuer, chain and host name). Everything runs
in the existing Horus workers, database, permissions and notifications - nothing extra to install.

- [What is measured](#what-is-measured)
- [Adding a monitor](#adding-a-monitor)
- [Status, uptime and coverage](#status-uptime-and-coverage)
- [TLS certificates](#tls-certificates)
- [Notifications](#notifications)
- [Internal targets and SSRF protection](#internal-targets-and-ssrf-protection)
- [Permissions](#permissions)
- [Data retention](#data-retention)
- [Settings](#settings)

![Domain monitoring list](../images/domain-monitoring.png)
*The list: status, last check and error, response time, uptime with measured coverage, TLS expiry.*

## What is measured

> [!IMPORTANT]
> All values are measured **from the network of the Horus server**. A site that is down only for some of your users,
> or that the Horus server cannot reach, shows up that way. Checks a browser makes are never used as evidence.

Each check, run by a worker:

1. resolves the host name once and validates every address (see [SSRF protection](#internal-targets-and-ssrf-protection));
2. connects to exactly that validated address - for `https://` with TLS, SNI and full certificate verification;
3. sends a light `GET` (`Connection: close`) and reads **only the status line and headers** - the body is never
   downloaded;
4. follows up to 5 redirects, each target validated again;
5. compares the final HTTP status with the expected codes (default `200-299`).

Failures are classified as **DNS**, **timeout**, **connection**, **TLS**, **HTTP status**, **redirect**,
**blocked target**, **protocol** or **invalid URL**.

## Adding a monitor

**Domain Monitoring → Add monitor**:

| Field | Default | Notes |
|---|---|---|
| Name | - | shown in lists and notifications |
| Domain or URL | - | `example.com` becomes `https://example.com/`; only `http://` / `https://`, no user name or password |
| Check interval | 60 s | 30 s - 24 h |
| Timeout | 10 s | 1 - 30 s, shorter than the interval |
| Expected HTTP status | `200-299` | codes and ranges, e.g. `200-299, 301` |
| Alert after failed checks | 3 | consecutive failures before an outage is notified |
| Tags | - | optional, for filtering |

Monitors can be edited, paused, resumed and deleted. **Check now** queues an immediate check for a worker; it is
limited to once per 30 seconds per monitor and 20 per user in 10 minutes.

Checks of all monitors are spread over their interval and run with bounded concurrency (`HORUS_MONITOR_CONCURRENCY`).
One monitor is never checked by two workers at the same time.

## Status, uptime and coverage

| Status | Meaning |
|---|---|
| Reachable | the last check succeeded |
| Unreachable | the last check failed (the error type and message are shown) |
| Outage | the failure streak reached the alert threshold |
| Paused | not checked; paused time is not measured |
| Not measured yet | no check has run yet |

**Uptime** is time-weighted: a check result stands for the time until the next result, but at most twice the interval.

- **uptime %** = available time / (available + unavailable time)
- **coverage %** = (available + unavailable time) / window

Time **before the first check, while paused and without results** (for example a stopped worker) is **unknown**: it
is never counted as available. A monitor added an hour ago shows its uptime with a coverage of a few percent for the
30-day window - not a 30-day history it does not have. Windows are aligned to whole UTC hours. Timestamps are stored
in UTC and shown in your browser's time zone.

The detail page shows the response time chart (24 h per check, 7 / 30 days as hourly averages), outages with start,
end and duration, the check history with error causes, HTTP status and the resolved IP addresses, and daily summaries.

![Monitor detail](../images/domain-monitoring-detail.png)
*Detail of one monitor: response time, certificate, last check with resolved addresses, check history.*

## TLS certificates

For `https://` addresses the certificate is queried with SNI; chain and host name are verified by the TLS stack. The
list shows the expiry date and the days left, the detail page the validity period, issuer, subject, names and the
results of chain and host-name verification. A certificate that cannot be verified makes the check **fail** (TLS); its
details are then read through a separate handshake that sends no request - verification is never switched off for
the request itself. For `http://` addresses the TLS fields show **not applicable**.

## Notifications

Notifications use the existing Horus notifications (in-app and the configured Email / Slack / Teams / Webhook
channels and their routing rules). In-app they are visible to users with `monitors:read`.

| Event | When | Repeats |
|---|---|---|
| Outage | after N consecutive failed checks (default 3) | once per outage |
| Recovered | first successful check after an outage | once |
| Certificate expiring | 30, 14, 7, 3 and 1 days before expiry | once per threshold; reset when the certificate is renewed |
| Certificate expired | after expiry | once |
| Certificate problem | untrusted chain or wrong host name | once per distinct error |

The alert threshold only decides when to notify. Uptime always counts every failed check as unavailable time.

## Internal targets and SSRF protection

By default only **public internet addresses** are checked. Refused: loopback, private networks, link-local, CGNAT,
multicast, reserved and documentation ranges and cloud metadata addresses - IPv4 and IPv6, including IPv4 embedded in
IPv6 (mapped, 6to4, Teredo, NAT64). A name must resolve **only** to allowed addresses; the connection then goes to the
validated address, so DNS rebinding cannot switch it to an internal one. Every redirect target is validated again.

To monitor internal services, a user with `settings:write` adds networks under **Domain Monitoring → Internal
targets**: enter the IP address or CIDR of the internal network you explicitly want Horus to monitor (example
placeholder: `<internal-cidr>` - replace it with your own network; host names and `0.0.0.0/0` are refused). Cloud
metadata addresses stay blocked even then. Changes are recorded in the audit log.

## Permissions

| Permission | Allows | Default roles |
|---|---|---|
| `monitors:read` | lists, details, history | Super Admin, Security Admin, System Admin, Security Analyst, Auditor |
| `monitors:manage` | add, edit, pause, resume, delete, check now | Super Admin, Security Admin, System Admin |
| `settings:write` | internal-target allowlist | Super Admin |

## Data retention

| Data | Kept |
|---|---|
| Raw check results | 90 days (`HORUS_MONITOR_RETENTION_DAYS`) |
| Hourly summaries | as long as the raw results |
| Daily summaries, outages | until the monitor is deleted |

The daily task `horus.monitor_maintenance` writes the daily summaries and purges older raw results. Deleting a
monitor removes its results, outages and summaries; the audit log keeps who deleted what.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `HORUS_MONITOR_CONCURRENCY` | `8` | checks running at the same time per dispatch run |
| `HORUS_MONITOR_RETENTION_DAYS` | `90` | days raw check results and hourly summaries are kept (7 - 3650) |
