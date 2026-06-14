import { apiClient } from './client'
import type { AppSettings } from '@/types/api'

export async function fetchSettings(): Promise<AppSettings> {
  return apiClient.get<AppSettings>('/settings')
}

export async function updateSettings(settings: Partial<AppSettings>): Promise<AppSettings> {
  return apiClient.patch<AppSettings>('/settings', settings)
}
