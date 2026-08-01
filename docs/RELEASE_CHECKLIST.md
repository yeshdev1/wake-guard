# Release Checklist

## Product and safety

- [ ] Core alarm works without HealthKit, location, calendar, or AI.
- [ ] No AI path can call AlarmKit directly.
- [ ] No response to a pre-alarm prompt leaves the original alarm unchanged.
- [ ] Critical alarm cancellation/delay requires explicit confirmation.
- [ ] Ten-second challenge pass is validated on real devices.
- [ ] Shaking alone does not pass in the accepted test matrix.
- [ ] Accessible non-walking fallback works.
- [ ] Alarm state reconciles on launch/foreground.
- [ ] Every mutation appears in audit history.
- [ ] Error UI states whether the alarm remains scheduled.

## Time

- [ ] DST spring-forward cases pass.
- [ ] DST fall-back cases pass.
- [ ] Half-hour/45-minute zones pass.
- [ ] International Date Line cases pass.
- [ ] Follow-local and fixed-zone semantics are documented and tested.
- [ ] Stale travel prompts are harmless.
- [ ] Manual clock/time-zone changes are tested.

## Lifecycle and reliability

- [ ] App terminated.
- [ ] Device restarted.
- [ ] Low Power Mode.
- [ ] Background App Refresh disabled.
- [ ] Notification permission revoked.
- [ ] Motion permission revoked mid-flow.
- [ ] Location/Health/Calendar denied and revoked.
- [ ] Storage/persistence failure.
- [ ] Duplicate/out-of-order callbacks.
- [ ] Async cancellation and uncertain external outcome.
- [ ] 100-cycle soak test.

## Privacy and security

- [ ] Privacy manifest.
- [ ] SDK inventory.
- [ ] Privacy Nutrition Label mapping.
- [ ] In-app privacy policy link.
- [ ] Explicit consent before third-party AI sharing.
- [ ] No raw sensitive logs.
- [ ] No health/motion/location/calendar advertising use.
- [ ] Export works.
- [ ] Deletion works.
- [ ] Secrets audit passes.
- [ ] Prompt injection corpus passes.

## Accessibility and visual quality

- [ ] VoiceOver.
- [ ] Dynamic Type at largest sizes.
- [ ] Reduce Motion.
- [ ] Increased contrast.
- [ ] Dark mode.
- [ ] 12/24-hour formats.
- [ ] RTL.
- [ ] Non-color status indicators.
- [ ] Touch targets.
- [ ] Sleep-inertia usability.
- [ ] Approved screenshot baseline.
- [ ] All key empty/loading/error/success states.

## Performance and battery

- [ ] Cold-launch budget.
- [ ] Reconciliation budget.
- [ ] Challenge start/pass latency.
- [ ] Overnight idle battery.
- [ ] Location/travel battery.
- [ ] No memory growth in soak test.
- [ ] AI latency has deterministic fallback.

## Store submission

- [ ] Latest stable toolchain accepted by App Store.
- [ ] Archive contains no debug tools.
- [ ] App Review notes explain AlarmKit, challenge, optional permissions, and AI safety.
- [ ] Metadata contains no diagnostic claims.
- [ ] Screenshots match shipping build.
- [ ] Support URL and privacy URL work.
- [ ] Demo steps work for reviewer.
- [ ] TestFlight critical matrix passed on exact build.
- [ ] Rollback and smart-feature kill-switch plan exists.
