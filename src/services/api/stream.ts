import { apiClient } from './client'
import type { StreamResponse } from '@/types/api'

export async function fetchStreamCredentials(deviceId: string): Promise<StreamResponse> {
  const response = await apiClient.get<{
    device_id: string
    token: string
    url: string
    room: string
    identity: string
    expires_at: string
  }>(`/devices/${encodeURIComponent(deviceId)}/stream`)

  return {
    deviceId: response.device_id,
    token: response.token,
    url: response.url,
    room: response.room,
    identity: response.identity,
    expiresAt: response.expires_at,
  }
}
