import { apiClient } from './client'
import type { CaptureResponse } from '@/types/api'

export async function captureDeviceFrame(deviceId: string): Promise<CaptureResponse> {
  const response = await apiClient.post<{
    image_id: string
    url?: string
    captured_at: string
  }>(`/devices/${encodeURIComponent(deviceId)}/capture`)

  return {
    imageId: response.image_id,
    url: response.url,
    capturedAt: response.captured_at,
  }
}
