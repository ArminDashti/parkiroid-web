import { apiClient } from './client'
import type { StreamResponse } from '@/types/api'

export async function fetchStreamUrl(deviceId: string): Promise<StreamResponse> {
  return apiClient.get<StreamResponse>(`/devices/${encodeURIComponent(deviceId)}/stream`)
}
