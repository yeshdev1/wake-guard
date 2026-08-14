# App Privacy Nutrition Label mapping (WG-187)

Maps every data type Alarm Agent touches to its App Store privacy classification. Backed by
`PrivacyNutritionLabel` and checked by `PrivacyNutritionLabelTests`, so the mapping stays matched to app
behavior and the WG-186 privacy manifest.

**Summary:** in the default build **no data is collected** (nothing is transmitted off device). The **only**
data that can ever leave the device is minimized, redacted derived summaries sent to the **optional** cloud
model, and only after separate consent. **Nothing** is linked to identity or used for tracking.

| Data type | Collection | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Health & Fitness (sleep) | Not collected (on device) | No | No | Estimate readiness; raw samples never leave the device. |
| Coarse location | Not collected (on device) | No | No | Detect time-zone travel via significant-location changes; never stored or sent. |
| Calendar events | Not collected (on device) | No | No | Read only event times for wake planning; titles never leave the device. |
| User content (journal) | Not collected (on device) | No | No | Stored and processed on device. |
| Diagnostics | Not collected (on device) | No | No | No analytics/crash transmission; diagnostics stay on device. |
| Cloud derived summaries | **Optional, redacted** | No | No | When cloud AI is on: only minimized, redacted derived summaries — never raw health, location, calendar, or journal text. |

## Optional collection

The single transmitted category — *cloud derived summaries* — is **optional** (cloud AI is off by default,
WG-174) and always **redacted** (only non-identifying derived values, never raw data). It is documented here
even though it is optional, and it is not linked to identity and not used for tracking. Enabling it is a
separate, explicit consent.
