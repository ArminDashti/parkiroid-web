import { apiClient } from './client'
import type { GalleryImage } from '@/types/api'

interface GalleryImageWire {
  id: string
  url: string
  thumbnail_url?: string
  caption?: string
  captured_at: string
}

export async function fetchImages(): Promise<GalleryImage[]> {
  const raw = await apiClient.get<GalleryImageWire[]>('/images')
  return (raw ?? []).map((image) => ({
    id: image.id,
    url: image.url,
    thumbnailUrl: image.thumbnail_url,
    caption: image.caption,
    capturedAt: image.captured_at,
  }))
}
