/// UI language choice (Language screen 7.4). System follows the device locale
/// (fallback English). Session-local in the UI-first phase; true app-wide live
/// re-render needs the l10n layer (backend phase).
enum AppLanguage { system, english, ukrainian }
