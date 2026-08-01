# Official Reference Checklist

Verify APIs again against the current SDK and App Store requirements at implementation and release time.

## Apple

- AlarmKit framework and AlarmManager.
- Scheduling an alarm with AlarmKit.
- Core Motion: CMPedometer and CMMotionActivityManager.
- Core Location: significant-location-change monitoring and background location guidance.
- BackgroundTasks: BGTaskScheduler.
- UserNotifications: actionable notification categories and response handling.
- Foundation: system time-zone change notification and TimeZone APIs.
- HealthKit: authorizing health data and sleep analysis categories.
- EventKit: requesting the minimum calendar access needed.
- Foundation Models: structured/guided generation, Generable, tool calling, availability, and safety.
- Human Interface Guidelines: HealthKit, privacy, accessibility, notifications, and generative AI.
- App Review Guidelines, especially privacy, sensitive data, notifications, minimum functionality, and third-party AI disclosure.
- App Privacy Details and privacy manifests.

## Anthropic / Claude Code

- Claude Code project memory and CLAUDE.md.
- Claude Code skills.
- Claude Code custom subagents.
- Claude Code local `/code-review`.
- Claude Code common workflows and prompting best practices.

## Release-time rule

Apple and Claude Code APIs evolve. Before shipping, create a task that rechecks every entitlement, availability annotation, API name, App Store rule, privacy requirement, and Claude Code configuration against the current official documentation.
