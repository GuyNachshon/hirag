# Repository Guidelines

## Project Structure & Module Organization
- `src/`: application code
  - `assets/` (SCSS, fonts, icons; variables in `src/assets/variables.scss`)
  - `components/` (UI SFCs like `ChatTurn.vue`, `PromptBox.vue`)
  - `views/` (routes: `Chat.vue`, `Transcription.vue`)
  - `stores/` (Pinia stores, e.g., `chat.js`; export `useXStore` such as `useChatStore`)
  - `services/` (API client), `router/` (Vue Router), `App.vue`, `main.js`
- `public/`: static assets served as‑is
- `dist/`: production build output
- Root: `vite.config.js` (alias `@` → `src`), `index.html`, `Dockerfile*`, `nginx-frontend.conf`, `env.production`.

## Build, Test, and Development Commands
- `npm install`: install dependencies (Node 20+ recommended).
- `npm run dev`: start Vite dev server with HMR.
- `npm run build`: create production build in `dist/`.
- `npm run preview`: locally serve the built app.
- Docker (optional): `docker build -f Dockerfile -t frontend .`; run behind Nginx using `nginx-frontend.conf` to proxy `/api/`.

## Coding Style & Naming Conventions
- Vue 3 + Pinia. SFCs use PascalCase (e.g., `ChatTurn.vue`).
- Stores live in `src/stores` and export `useXStore` (e.g., `useChatStore`).
- ES modules (`.js`), 2‑space indentation, single quotes.
- Use `@` alias for imports (e.g., `import X from '@/components/X.vue'`).
- SCSS in `src/assets`; shared variables in `variables.scss`.

## Testing Guidelines
- No unit test framework yet. Prefer Vitest later.
- Name tests `*.spec.js` colocated with modules or under `src/__tests__/`.
- For now, do manual smoke tests: `npm run dev`, verify chat flow, file upload, and transcription; check browser console for errors.

## Commit & Pull Request Guidelines
- Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:` (e.g., `feat(chat): stream chunks`).
- PRs must include: clear description, linked issue(s), screenshots/GIFs for UI changes, test steps, and any breaking change notes.

## Security & Configuration Tips
- API calls target `/api/v1/*` and expect a reverse proxy.
- Vite reads `VITE_*` env vars (e.g., `VITE_API_URL`); see `env.production`.
- Local dev with separate backend: run behind the provided Nginx setup or configure CORS/proxy appropriately.

