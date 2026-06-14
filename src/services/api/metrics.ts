import { apiClient } from './client'
import type { DeviceMetrics } from '@/types/api'

export async function fetchDeviceMetrics(deviceId: string): Promise<DeviceMetrics> {
  return apiClient.get<DeviceMetrics>(`/devices/${encodeURIComponent(deviceId)}/metrics`)
}
