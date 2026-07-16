import { apiClient } from './client'
import type { DeviceMetrics, MetricReading } from '@/types/api'

interface MetricReadingWire {
  timestamp: string
  temperature_celsius: number
  noise_db: number
}

interface DeviceMetricsWire {
  device_id: string
  device_name: string
  current: {
    temperature_celsius: number
    noise_db: number
    recorded_at: string
  }
  history: MetricReadingWire[]
}

function mapReading(reading: MetricReadingWire): MetricReading {
  return {
    timestamp: reading.timestamp,
    temperatureCelsius: reading.temperature_celsius,
    noiseDb: reading.noise_db,
  }
}

export async function fetchDeviceMetrics(deviceId: string): Promise<DeviceMetrics> {
  const raw = await apiClient.get<DeviceMetricsWire>(
    `/devices/${encodeURIComponent(deviceId)}/metrics`,
  )

  return {
    deviceId: raw.device_id,
    deviceName: raw.device_name,
    current: {
      temperatureCelsius: raw.current.temperature_celsius,
      noiseDb: raw.current.noise_db,
      recordedAt: raw.current.recorded_at,
    },
    history: (raw.history ?? []).map(mapReading),
  }
}
