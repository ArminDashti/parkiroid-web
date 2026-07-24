# Directory tree

```
parkiroid-web/
├── .armin/
│   └── docker-scripts/
│       ├── run-on-docker-local.ps1    # Local Docker deploy (YAML-only)
│       ├── run-on-docker-local.yaml   # Local stack/port/image settings
│       ├── run-on-docker-server.ps1   # Remote SSH deploy (YAML-only)
│       └── run-on-docker-server.yaml  # Remote ssh/volume/build settings
├── .docker/
│   └── stack.manifest.json   # Stack name, ports, network, remote paths
├── .env.example              # API base URL template
├── Dockerfile                # Production multi-stage nginx image
├── README.md                 # Project overview and setup
├── create-image.ps1          # Build Docker image
├── docker-compose.yml        # dogan-webui; IMAGE_TAG/PUBLISH_PORT/DOCKER_NETWORK
├── env.d.ts                  # Vite and PWA client type refs
├── index.html                # SPA shell; PWA meta; Inter font links
├── nginx.conf                # SPA hosting; no-cache for SW/manifest
├── package.json              # Dependencies and npm scripts
├── docs/
│   ├── description.md        # Project overview and stack
│   ├── dir-tree.md           # This file tree
│   ├── endpoints.md          # API endpoint reference
│   ├── modules/
│   │   ├── api-services.md   # Fetch client and API modules
│   │   ├── camera-panel.md   # LiveKit camera panel
│   │   ├── dashboard.md      # Dashboard view notes
│   │   ├── docker-deploy.md  # Docker build and deploy scripts
│   │   └── pwa.md            # PWA manifest and service worker
│   ├── potentional-bugs/
│   │   ├── red.md            # Critical bug notes
│   │   └── yellow.md         # Minor bug / smell notes
│   └── suggestion/
│       ├── suggestion1.md    # Improvement ideas
│       └── suggestion2.md    # Improvement ideas
├── public/
│   ├── apple-touch-icon.png  # iOS home-screen icon (180x180)
│   ├── favicon.svg           # Browser tab icon
│   ├── pwa-192x192.png       # PWA icon 192
│   └── pwa-512x512.png       # PWA icon 512 (also maskable)
├── src/
│   ├── App.vue               # Root Vue component
│   ├── main.ts               # Bootstrap, Pinia, router, SW register
│   ├── assets/
│   │   └── main.css          # Global Tailwind styles; Inter font-sans
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
└── vite.config.ts            # Vite + vite-plugin-pwa configuration
```
