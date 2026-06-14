import { ApiError } from './errors'
import type { ApiErrorBody } from '@/types/api'

type TokenProvider = () => string | null

interface RequestOptions extends Omit<RequestInit, 'body'> {
  body?: unknown
  auth?: boolean
}

const DEFAULT_BASE_URL = 'http://localhost:8080/api'

class ApiClient {
  private readonly baseUrl: string
  private tokenProvider: TokenProvider = () => null

  constructor(baseUrl = import.meta.env.VITE_API_BASE_URL || DEFAULT_BASE_URL) {
    this.baseUrl = baseUrl.replace(/\/$/, '')
  }

  setTokenProvider(provider: TokenProvider): void {
    this.tokenProvider = provider
  }

  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const { body, auth = true, headers, ...rest } = options

    const requestHeaders = new Headers(headers)
    requestHeaders.set('Accept', 'application/json')

    if (body !== undefined) {
      requestHeaders.set('Content-Type', 'application/json')
    }

    if (auth) {
      const token = this.tokenProvider()
      if (token) {
        requestHeaders.set('Authorization', `Bearer ${token}`)
      }
    }

    let response: Response

    try {
      response = await fetch(`${this.baseUrl}${path}`, {
        ...rest,
        headers: requestHeaders,
        body: body !== undefined ? JSON.stringify(body) : undefined,
      })
    } catch {
      throw new ApiError('Unable to reach the server. Check your connection or API URL.', 0)
    }

    if (response.status === 204) {
      return undefined as T
    }

    const contentType = response.headers.get('content-type') ?? ''
    const isJson = contentType.includes('application/json')
    const payload = isJson ? await response.json().catch(() => null) : await response.text()

    if (!response.ok) {
      const errorBody = payload as ApiErrorBody | null
      const message =
        errorBody?.message ??
        (typeof payload === 'string' && payload.length > 0 ? payload : response.statusText) ??
        'Request failed.'

      throw new ApiError(message, response.status, payload)
    }

    return payload as T
  }

  get<T>(path: string, options?: Omit<RequestOptions, 'method' | 'body'>): Promise<T> {
    return this.request<T>(path, { ...options, method: 'GET' })
  }

  post<T>(
    path: string,
    body?: unknown,
    options?: Omit<RequestOptions, 'method' | 'body'>,
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body })
  }

  patch<T>(
    path: string,
    body?: unknown,
    options?: Omit<RequestOptions, 'method' | 'body'>,
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'PATCH', body })
  }
}

export const apiClient = new ApiClient()
