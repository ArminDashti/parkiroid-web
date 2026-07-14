import { apiClient } from './client'
import type { DeviceTelemetry } from '@/types/api'

export async function fetchDeviceTelemetry(deviceId: string): Promise<DeviceTelemetry> {
  const response = await apiClient.get<{
    device_id: string
    battery_percent: number
    battery_temperature_celsius: number
    noise_db: number
    jolt: number
    signal_strength: number
    network_type: string
    server_phone_latency_ms: number
    server_web_latency_ms: number
    recorded_at: string
  }>(`/devices/${encodeURIComponent(deviceId)}/telemetry`)

  return {
    deviceId: response.device_id,
    batteryPercent: response.battery_percent,
    batteryTemperatureCelsius: response.battery_temperature_celsius,
    noiseDb: response.noise_db,
    jolt: response.jolt,
    signalStrength: response.signal_strength,
    networkType: response.network_type,
    serverPhoneLatencyMs: response.server_phone_latency_ms,
    serverWebLatencyMs: response.server_web_latency_ms,
    recordedAt: response.recorded_at,
  }
}
