# Directory tree

```
parkiroid-web/
├── .env.example              # API base URL template
├── Dockerfile                # Production container image
├── README.md                 # Project overview and setup
├── create-docker-image       # Docker build helper script
├── nginx.conf                # Static hosting config for container
├── package.json              # Dependencies and npm scripts
├── docs/                     # Project documentation
├── public/                   # Static assets served as-is
├── src/
│   ├── App.vue               # Root Vue component
│   ├── main.ts               # App bootstrap and plugin setup
│   ├── assets/
│   │   └── main.css          # Global Tailwind styles
│   ├── components/
│   │   ├── AppLayout.vue     # Sidebar + header page shell
│   │   ├── CameraPanel.vue   # LiveKit stream with Play/Stop/Capture
│   │   ├── ErrorAlert.vue    # Reusable error banner
│   │   └── NavSidebar.vue    # App navigation links
│   ├── router/
│   │   └── index.ts          # Route definitions and auth guard
│   ├── services/
│   │   └── api/
│   │       ├── auth.ts       # Login/logout/me endpoints
│   │       ├── capture.ts    # POST frame capture
│   │       ├── client.ts     # Shared fetch client with auth
│   │       ├── devices.ts    # Device list endpoint
│   │       ├── errors.ts     # ApiError helper and message parsing
│   │       ├── gallery.ts    # Gallery images endpoint
│   │       ├── metrics.ts    # Temperature/noise metrics endpoint
│   │       ├── settings.ts   # User settings endpoints
│   │       ├── stream.ts     # LiveKit credentials endpoint
│   │       └── telemetry.ts  # Live telemetry snapshot endpoint
│   ├── stores/
│   │   └── auth.ts           # Pinia auth session store
│   ├── types/
│   │   └── api.ts            # Shared TypeScript API types
│   └── views/
│       ├── DashboardView.vue # Unified telemetry + camera dashboard
│       ├── GalleryView.vue   # Captured image gallery
│       ├── LoginView.vue     # Sign-in form
│       ├── MetricsView.vue   # Temperature/noise charts
│       ├── SettingsView.vue  # User preferences form
│       └── StreamView.vue    # Full-page camera stream
└── vite.config.ts            # Vite build configuration
```
