# NowDo project guidance

- Keep the web app at the repository root and the native Mac app in `macos/`. Their records are independent.
- Use `.agents/skills/product-clarity/SKILL.md` when reviewing product scope, onboarding, README, or release copy. Describe the actual user action and visible result before implementation details.
- Purple is the primary UI color. Keep start/pause/continue simple and avoid extra task-selection steps.
- Separate implemented features, synthetic checks, and real Calendar interaction in release claims. Do not mark a real drag or native Services menu verified from a unit test.
- Native records and screenshots of real calendars are private. Never commit Application Support data, logs, credentials, real calendar exports, or personal timing backups. Public screenshots must use isolated fixtures.
- Run the native build and relevant scripts in `macos/scripts/` for native changes. Preserve source Calendar events; no hidden clipboard polling or broad automation permissions.
