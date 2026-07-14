# Suggestion: code-split LiveKit bundle

**Component:** `CameraPanel.vue`

The LiveKit client adds ~500 kB to the production chunk. Consider lazy-loading `CameraPanel` via dynamic `import()` on dashboard and stream routes to reduce initial bundle size.

**Effort:** Low (1 route-level change per view).
