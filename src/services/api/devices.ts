import { apiClient } from './client'
import type { Device } from '@/types/api'

export async function fetchDevices(): Promise<Device[]> {
  return apiClient.get<Device[]>('/devices')
}
