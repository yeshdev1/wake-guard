# WakeGuard privacy policy (requirements) — WG-188

The required content for the in-app and web privacy policy. Backed by `PrivacyPolicyRequirementsTests`,
which checks every required section is present. Wording here is the source of truth for the published
policy.

## Collection

WakeGuard is on-device first. In the default build **no personal data is collected** — nothing is
transmitted off your device. Alarms, sleep journal, motion-derived signals, sleep readiness, calendar-based
wake plans, and audit history are created and stored **only on your device**.

## Use

We use each permission only for its stated feature: **Health (sleep)** to estimate readiness on device;
**Motion** for the wake-up walk challenge and the pre-alarm awake check; **Location** (significant-change
only, never continuous GPS) to keep alarms correct across time zones; **Calendar** (event times only, never
titles) to compute the latest safe wake time; **Notifications** for pre-alarm prompts and alarm alerts.

## Sharing

We do not share your data with third parties. There are no advertising networks, no analytics SDKs, and no
data brokers. WakeGuard ships **zero** third-party SDKs.

## Retention

Data is retained locally on its own schedule: derived motion and recommendations expire soonest, the sleep
journal longer, and the audit log longest — with a documented **minimum retention for critical-alarm audit
events** so safety-relevant history is not lost (WG-182).

## Deletion

You can delete individual optional data categories (motion, recommendations, journal, health-derived) or
**all app data** at any time, without an account (WG-184). Deleting all data cancels scheduled alarms, and
we ask you to confirm that consequence first. You can also export your data before deleting it (WG-183).

## AI providers

AI is advisory and permission-gated. By default it runs **on device** (Apple Foundation Models); nothing is
sent to a server. **Optional cloud AI is off by default** and requires a separate, explicit consent; when
enabled it sends only minimized, **redacted** derived summaries — never raw health, location, calendar
text, journal text, or prompts containing sensitive data.

## Health and motion are never used for advertising

Health and motion data are used **only** to provide the features above, on your device. They are **never
used for advertising or marketing**, never sold, and never shared with data brokers or third parties. This
prohibition is explicit and permanent.

## No diagnosis

WakeGuard provides wellness estimates, not medical advice. It does **not** diagnose, treat, or make medical
claims.

## Contact

Questions or requests about your privacy: **privacy@wakeguard.app**. We provide a contact path in-app and on
the web policy page.
