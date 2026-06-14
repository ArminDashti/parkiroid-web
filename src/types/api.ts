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

export interface StreamResponse {
  deviceId: string
  streamUrl: string
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
