import { apiClient } from './client'
import type { GalleryImage } from '@/types/api'

export async function fetchImages(): Promise<GalleryImage[]> {
  return apiClient.get<GalleryImage[]>('/images')
}
