# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AI-powered transcription web application built with Next.js 16, React 19, and TypeScript. The app transforms audio recordings into searchable transcripts with AI-generated insights. It's built using v0.app (Vercel's AI code generator) and automatically syncs with Vercel deployments.

**Key Features:**
- Audio file upload with drag-and-drop
- Transcript viewing with speaker identification
- AI-powered insights (summaries, action items, key points)
- Interactive chat interface for querying transcripts
- Folder-based organization
- **Full RTL (Right-to-Left) support with Hebrew UI**

## Development Commands

### Core Commands
```bash
# Development server with hot reload
npm run dev

# Production build
npm run build

# Start production server
npm start

# Run ESLint
npm run lint
```

### Adding shadcn/ui Components
This project uses shadcn/ui for UI components. To add new components:

```bash
# Example: adding a new component
npx shadcn@latest add [component-name]

# The component will be added to /components/ui/
# Configuration is in components.json
```

## Architecture

### Tech Stack
- **Framework:** Next.js 16 with App Router (file-based routing)
- **UI:** React 19 with TypeScript
- **Styling:** Tailwind CSS 4.1.9 with OKLCH color space
- **Components:** shadcn/ui (Radix UI primitives + Tailwind)
- **Icons:** Lucide React
- **Forms:** React Hook Form + Zod validation
- **Analytics:** Vercel Analytics

### Project Structure
```
/frontend
├── /app                         # Next.js App Router
│   ├── layout.tsx              # Root layout with Analytics
│   ├── page.tsx                # Home page - LibraryView
│   ├── globals.css             # Global styles with CSS variables
│   ├── /upload/page.tsx        # Upload flow
│   └── /transcript/[id]/page.tsx  # Dynamic transcript viewer
├── /components
│   ├── library-view.tsx        # Main dashboard with transcript library
│   ├── upload-flow.tsx         # Multi-step upload workflow
│   ├── transcript-viewer.tsx   # Transcript detail view with AI chat
│   ├── theme-provider.tsx      # Dark mode provider
│   └── /ui                     # shadcn/ui components
├── /lib
│   └── utils.ts                # cn() utility for className merging
├── /public                      # Static assets
├── components.json              # shadcn/ui configuration
├── next.config.mjs             # Next.js config (linting/TS disabled in builds)
└── tsconfig.json               # TypeScript configuration
```

### Routing
- `/` → LibraryView component (transcript library dashboard)
- `/upload` → UploadFlow component (audio upload interface)
- `/transcript/[id]` → TranscriptViewer component (detailed transcript view)

### Key Architectural Patterns

**Layout Persistence:**
- `AppLayout` component wraps all pages in `app/layout.tsx`
- Header and sidebars persist across routes without re-rendering
- Only main content changes when navigating between pages
- Prevents layout flicker and maintains state across navigation

**Client-Side Rendering:**
- All main components use `"use client"` directive
- State managed with React `useState` hooks
- No global state management library (Redux/Zustand)

**Component Structure:**
```tsx
// Standard pattern used throughout
"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"

interface DataType {
  id: string
  // ...
}

export function ComponentName() {
  const [state, setState] = useState<DataType[]>([])

  return (
    <div className="...">
      {/* JSX */}
    </div>
  )
}
```

**Data Flow:**
- Mock data currently hardcoded in components
- TypeScript interfaces define data shapes (Transcript, TranscriptSegment, ChatMessage)
- No backend API integration yet (ready for fetch/axios implementation)

**Styling Conventions:**
- Tailwind utility classes with `cn()` helper for conditional styling
- Color system uses CSS variables defined in `app/globals.css`
- Primary color: Teal (`oklch(0.55 0.12 180)`)
- Consistent spacing: `px-2/4/6`, `py-2/4/6`
- Border radius: 12px standard
- Dark mode support via next-themes

**Multi-Step Workflows:**
The upload flow demonstrates the multi-step pattern used throughout:
```tsx
type UploadStep = "select" | "uploading" | "processing" | "complete"
const [step, setStep] = useState<UploadStep>("select")
// Conditional rendering based on step
```

## Build Configuration

### Next.js Config (`next.config.mjs`)
```javascript
{
  eslint: { ignoreDuringBuilds: true },      // Fast iteration
  typescript: { ignoreBuildErrors: true },   // Fast iteration
  images: { unoptimized: true }              // Simplified image handling
}
```

**Note:** These settings prioritize rapid development. For production, consider re-enabling type checking and linting in CI/CD.

### TypeScript
- Strict mode enabled
- Path alias: `@/*` maps to project root
- Import shadcn components: `@/components/ui/button`
- Import utilities: `@/lib/utils`

### Tailwind CSS
- v4.1.9 with new PostCSS plugin (`@tailwindcss/postcss`)
- Global styles in `app/globals.css`
- Custom color variables for theming
- Animations via `tailwindcss-animate`

## Component Architecture

### Main Components

**app-layout.tsx** (Persistent Layout Wrapper)
- Wraps all pages to maintain header and sidebars across routes
- Unified header with search, navigation, and sidebar toggles
- Left sidebar: folder navigation ("התמלילים שלי", folders list)
- Right sidebar: AI chat with quick action buttons
- Manages global sidebar state (left/right visibility)
- Prevents re-rendering when navigating between pages

**library-view.tsx** (Home Dashboard)
- Main content area for home page (`/`)
- Displays transcript cards in a list view
- Folder title and drag-drop zone for uploads
- Returns only `<main>` content (no wrappers - layout handled by AppLayout)
- Mock data: 4 sample Hebrew transcripts with speakers
- State: selected folder, chat messages

**upload-flow.tsx** (Upload Workflow)
- Four-step process: select → uploading → processing → complete
- Drag-and-drop file handling with visual feedback
- Simulated upload progress (currently mock, ready for API integration)
- Navigation via Next.js `useRouter`

**transcript-viewer.tsx** (Detail View)
- Main content area for transcript detail page (`/transcript/[id]`)
- Two views: Transcript (speaker segments) + Insights (AI analysis)
- Toggle buttons at bottom center to switch views
- Modal dialog for new transcript upload configuration
- Returns only main content (layout handled by AppLayout)
- Mock data: 10 Hebrew speaker segments with timestamps

### UI Component Library (shadcn/ui)

All UI components are in `/components/ui/` and based on Radix UI primitives:
- **button.tsx** - Multiple variants (default, outline, ghost, destructive, etc.)
- **card.tsx** - Container with header/content/footer sections
- **dialog.tsx** - Modal dialogs for uploads and settings
- **dropdown-menu.tsx** - Context menus (Share, Export, Delete actions)
- **input.tsx** - Form inputs with label integration
- **progress.tsx** - Progress bars for upload tracking
- **badge.tsx** - Status indicators (completed, processing, enhancing)

To customize a component, edit the file directly in `/components/ui/`. All components use the `cn()` utility from `/lib/utils.ts` for className merging.

## Styling System

### Color Variables (globals.css)
The app uses CSS custom properties with OKLCH color space:
```css
--background: oklch(98.5% 0 0);          /* Near-white background */
--foreground: oklch(25% 0.005 240);      /* Near-black text */
--primary: oklch(0.55 0.12 180);         /* Teal primary color */
--muted: oklch(96.5% 0.002 240);         /* Subtle gray */
```

Dark mode automatically inverts these values. To modify colors, edit `app/globals.css`.

### Typography
- **Sans-serif:** Inter (imported from Google Fonts)
- **Monospace:** Geist Mono (JetBrains alternative)
- **Scale:** 11px (smallest) → 22px (headings)
- **Weights:** 400 (regular), 500 (medium), 600 (semibold), 700 (bold)

### Responsive Breakpoints
```css
sm: 640px   /* Mobile landscape / Small tablet */
md: 768px   /* Tablet */
lg: 1024px  /* Desktop */
```

Example usage:
```tsx
<div className="hidden sm:block">  {/* Hidden on mobile */}
<div className="px-4 md:px-6">    {/* Responsive padding */}
```

## Adding Features

### Adding a New Page
1. Create file in `/app/[route]/page.tsx`
2. Export default component:
```tsx
export default function PageName() {
  return <div>Content</div>
}
```
3. Page is automatically routed at `/{route}`

### Adding a New Component
1. Create file in `/components/component-name.tsx`
2. Use the standard client component pattern:
```tsx
"use client"

import { useState } from "react"

export function ComponentName() {
  return <div>Component</div>
}
```
3. Import in pages: `import { ComponentName } from "@/components/component-name"`

### Adding Form Validation
This project uses React Hook Form + Zod:
```tsx
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})

const { register, handleSubmit } = useForm({
  resolver: zodResolver(schema),
})
```

### Backend Integration (When Ready)
Current components use mock data. To integrate with a backend:

1. Create API routes in `/app/api/[route]/route.ts`:
```tsx
export async function POST(request: Request) {
  const body = await request.json()
  // Handle request
  return Response.json({ data: "..." })
}
```

2. Replace mock data with fetch calls:
```tsx
// Current: const mockTranscripts = [...]
// Future:
const [transcripts, setTranscripts] = useState([])

useEffect(() => {
  fetch('/api/transcripts')
    .then(res => res.json())
    .then(data => setTranscripts(data))
}, [])
```

3. Key endpoints to implement:
   - `POST /api/upload` - File upload
   - `GET /api/transcripts` - List transcripts
   - `GET /api/transcripts/[id]` - Single transcript
   - `POST /api/chat` - AI chat queries

## v0.app Integration

This project is auto-synced with v0.app:
- Changes deployed on v0.app automatically push to this repo
- Continue building at: https://v0.app/chat/projects/UnfgwZFzLeU
- Live deployment: https://vercel.com/guynachshons-projects/v0-ai-transcription-web-app

**Important:** If you manually edit files in this repo, they may be overwritten by v0.app deployments. Consider using v0.app as the primary interface for major changes, or disable auto-sync if full manual control is needed.

## Common Patterns

### Conditional Rendering
```tsx
{step === "select" && <SelectView />}
{step === "uploading" && <UploadingView />}
```

### Sidebar Toggles
```tsx
const [isSidebarOpen, setIsSidebarOpen] = useState(true)

// Desktop
<div className={`hidden lg:block ${!isSidebarOpen && 'lg:hidden'}`}>

// Mobile
<div className={`lg:hidden ${isMobileSidebarOpen ? 'block' : 'hidden'}`}>
```

### File Upload Handling
```tsx
const handleDrop = useCallback((e: React.DragEvent) => {
  e.preventDefault()
  const droppedFile = e.dataTransfer.files[0]
  if (droppedFile && droppedFile.type.startsWith("audio/")) {
    setFile(droppedFile)
  }
}, [])
```

### Navigation
```tsx
import { useRouter } from "next/navigation"
import Link from "next/link"

// Programmatic navigation
const router = useRouter()
router.push("/transcript/123")

// Link component
<Link href="/upload">Upload</Link>
```

## Deployment

### Vercel Deployment
The project is configured for Vercel deployment:
- Automatic deployments on git push
- Analytics enabled via `@vercel/analytics`
- Environment variables set in Vercel dashboard

### Environment Variables
When adding backend integration, define environment variables in `.env.local`:
```bash
NEXT_PUBLIC_API_URL=http://localhost:3000/api
# NEXT_PUBLIC_ prefix makes variables available in browser
```

Access in code:
```tsx
const apiUrl = process.env.NEXT_PUBLIC_API_URL
```

## RTL (Right-to-Left) Support

The application has **full RTL support for Hebrew**:

### Implementation Details

**Root Configuration:**
- `app/layout.tsx` sets `lang="he"` and `dir="rtl"` on HTML element
- All text flows right-to-left automatically

**RTL-Aware Styling:**
- Icon flipping using `scale-x-[-1]` for directional icons (arrows, chevrons)
- Margin/padding swaps: `mr-*` ↔ `ml-*`, `pr-*` ↔ `pl-*`
- Border swaps: `border-l` ↔ `border-r` for sidebars
- Position swaps: `left-*` ↔ `right-*` for absolute positioning
- Alignment swaps: `justify-start` ↔ `justify-end`, `align="end"` ↔ `align="start"`
- Chat bubble order reversed (user on right, AI on left in RTL)
- Button order reversed in forms/dialogs

**Global RTL Styles (`app/globals.css`):**
```css
[dir="rtl"] {
  direction: rtl;
  text-align: right;
}

[dir="rtl"] input,
[dir="rtl"] textarea {
  text-align: right;
}

[dir="rtl"] .flex {
  direction: rtl;
}
```

**Hebrew Translations:**
- All UI text translated to Hebrew
- Mock data (transcripts, speakers, dates) in Hebrew
- Folder names, button labels, placeholders all localized

**To Switch Back to English/LTR:**
1. Change `lang="he"` to `lang="en"` in `app/layout.tsx`
2. Change `dir="rtl"` to `dir="ltr"` in `app/layout.tsx`
3. Revert component text translations
4. Adjust component-specific RTL styling (margins, icons, positions)

## Known Limitations

1. **Mock Data:** All data is currently hardcoded in components
2. **No Authentication:** User auth not yet implemented
3. **No Persistence:** No database integration
4. **Simulated Upload:** Upload progress is mocked
5. **Static AI Responses:** Chat messages are placeholder text

These are intentional for rapid prototyping and should be addressed when integrating with backend services.