import { apiClient } from './client'
import type { AppSettings } from '@/types/api'

interface AppSettingsWire {
  notifications_enabled: boolean
  temperature_unit: 'celsius' | 'fahrenheit'
  noise_alert_threshold_db: number
  default_device_id?: string
}

function mapSettings(raw: AppSettingsWire): AppSettings {
  return {
    notificationsEnabled: raw.notifications_enabled,
    temperatureUnit: raw.temperature_unit,
    noiseAlertThresholdDb: raw.noise_alert_threshold_db,
    defaultDeviceId: raw.default_device_id,
  }
}

function toWire(settings: Partial<AppSettings>): Record<string, unknown> {
  const body: Record<string, unknown> = {}
  if (settings.notificationsEnabled !== undefined) {
    body.notifications_enabled = settings.notificationsEnabled
  }
  if (settings.temperatureUnit !== undefined) {
    body.temperature_unit = settings.temperatureUnit
  }
  if (settings.noiseAlertThresholdDb !== undefined) {
    body.noise_alert_threshold_db = settings.noiseAlertThresholdDb
  }
  if (settings.defaultDeviceId !== undefined) {
    body.default_device_id = settings.defaultDeviceId
  }
  return body
}

export async function fetchSettings(): Promise<AppSettings> {
  const raw = await apiClient.get<AppSettingsWire>('/settings')
  return mapSettings(raw)
}

export async function updateSettings(settings: Partial<AppSettings>): Promise<AppSettings> {
  const raw = await apiClient.patch<AppSettingsWire>('/settings', toWire(settings))
  return mapSettings(raw)
}
