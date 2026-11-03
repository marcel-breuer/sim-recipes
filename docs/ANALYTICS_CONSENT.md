# Landing-page analytics and consent

## Scope and defaults

Analytics is limited to the public Laravel landing page at `/`. The iOS app and
`/api/*` routes do not load the consent interface, Google scripts, or analytics
events. With both environment values empty, the landing page does not render
the consent markup, its text, or its JavaScript. The page uses a restrictive
same-origin Content Security Policy in this state.

Set `GTM_CONTAINER_ID` and/or `GA4_MEASUREMENT_ID` in the API service's runtime
environment to render the consent interface. Values must match `GTM-…` and
`G-…`; malformed non-empty values keep the interface available but are ignored
for script loading. No IDs are embedded in source code. A configured ID never
starts tracking by itself.

Before launch, complete the legal and operational gates below. Until then,
leave both variables empty. This implementation does not establish that the
service is legally compliant.

## Consent behavior

- Necessary functionality is always on. Statistics is unchecked by default.
- Accept, reject, and configure are presented as equal actions. The settings
  link in the footer reopens the choice; saving necessary-only consent withdraws
  statistics consent.
- Consent is stored only in browser local storage as the purpose choices,
  consent-text version, and decision timestamp. No account, camera, recipe, or
  other application metadata is included. The record remains until the user
  clears browser data; a new consent version prompts for a new choice.
- A local Google Consent Mode v2 default denies `analytics_storage`,
  `ad_storage`, `ad_user_data`, and `ad_personalization`. No Google request is
  sent before opt-in (Basic Consent Mode). On withdrawal, statistics storage
  becomes denied and first-party `_ga` cookies on the current host are expired.
- Advertising purposes remain denied. Do not add advertising, remarketing,
  custom HTML, session recording, or other non-analytics tags to GTM.
- If GTM is configured, the container loads after opt-in and receives
  `simrecipes_analytics_ready` (including the optional GA4 measurement ID),
  `page_view`, and `feature_cta_click` events. Configure a GA4 tag to fire on
  the ready event, use the provided measurement ID, and map the named events.
  Disable Google Signals and advertising personalization in that tag and do
  not also configure an automatic page view.
- If only GA4 is configured, the Google tag loads after opt-in and sends one
  page view plus the same named CTA events. Hash fragments and query parameters
  are removed from `page_location`, and the referrer is omitted. Events contain no user IDs, email, recipe
  identifiers, camera metadata, or arbitrary data-layer values. This static
  page has anchor navigation, not SPA routing. `app_download_click` should only
  be added when a real store destination is present.

## Event catalog

| Event | Trigger | Parameters |
| --- | --- | --- |
| `page_view` | Once after opt-in on page load | `page_path`, sanitized `page_location`, fixed page title |
| `feature_cta_click` | Landing-page CTA links marked in the template | `page_path`, sanitized `page_location`, fixed page title |
| `app_download_click` | Reserved for a real App Store link | Same sanitized page context; no user or object identifiers |

Do not add free-form link text, full referrers, query strings, user-provided
values, exception details, or internal identifiers to the data layer.

## Deployment and GTM setup

1. Complete the launch gates below and configure the GA4 property and GTM
   container with only the approved analytics tags.
2. Set `GTM_CONTAINER_ID` and `GA4_MEASUREMENT_ID` as Coolify runtime environment
   values for the `api`, `queue`, and `scheduler` services. The canonical
   Compose file passes both values to the Laravel app. A GA4-only setup may set
   only `GA4_MEASUREMENT_ID`.
3. Clear/rebuild Laravel's cached configuration during deployment using the
   normal release procedure, then verify in a clean browser profile that no
   request to Google is made before consent, rejection persists, acceptance
   loads exactly one page view, and withdrawal prevents later events.
4. Verify the rendered CSP and event payloads in the browser network panel and
   GA4 DebugView before any public activation.

The content security policy permits the Google hosts needed for the configured
IDs only on `/`; all API responses remain outside that middleware. Basic
Consent Mode is intentional: there are no cookieless pings before consent.

## Legal, retention, and launch gates

The landing page currently links to the separate portfolio site's privacy and
imprint pages. Those pages are outside this repository. Before enabling either
ID, their owner must publish and review accurate notices covering the exact
analytics purposes, Google as provider, data transfers, retention, lawful
basis, consent withdrawal, and how to revisit settings. Review the imprint and
change it only if the new deployment details require it.

Also record the controller's documented privacy review, applicable processor
terms/data-processing agreement, transfer safeguards, GA4 data-retention and
data-sharing settings, deletion process, and an approval to activate analytics.
These are deployment/legal gates, not claims made by this code. The browser
consent record is not a server-side audit trail; it is local evidence of the
current browser's choice and can be erased by clearing browser data. Google
Analytics data retention/deletion must be controlled in the provider account.

## Rollback

Remove both environment values and redeploy (including a fresh Laravel config
cache). The consent markup, strings, and module then disappear and the page CSP
returns to same-origin sources. Previously collected GA4 data and browser
cookies are not deleted by rollback; handle those through the configured
Google property and the browser consent withdrawal path.
