export interface User {
  id: string
  email: string
  name: string
}

export interface AuthResponse {
  token: string
  user: User
}

export interface Device {
  id: string
  name: string
  status: 'online' | 'offline' | 'unknown'
  location?: string
}

export interface MetricReading {
  timestamp: string
  temperatureCelsius: number
  noiseDb: number
}

export interface DeviceMetrics {
  deviceId: string
  deviceName: string
  current: {
    temperatureCelsius: number
    noiseDb: number
    recordedAt: string
  }
  history: MetricReading[]
}

export interface DeviceTelemetry {
  deviceId: string
  batteryPercent: number
  batteryTemperatureCelsius: number
  noiseDb: number
  jolt: number
  signalStrength: number
  networkType: string
  serverPhoneLatencyMs: number
  serverWebLatencyMs: number
  recordedAt: string
}

export interface CaptureResponse {
  imageId: string
  url?: string
  capturedAt: string
}

export interface StreamResponse {
  deviceId: string
  token: string
  url: string
  room: string
  identity: string
  expiresAt: string
}

export interface GalleryImage {
  id: string
  url: string
  thumbnailUrl?: string
  caption?: string
  capturedAt: string
}

export interface AppSettings {
  notificationsEnabled: boolean
  temperatureUnit: 'celsius' | 'fahrenheit'
  noiseAlertThresholdDb: number
  defaultDeviceId?: string
}

export interface ApiErrorBody {
  message?: string
  errors?: Record<string, string[]>
}
