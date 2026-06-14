import { apiClient } from './client'
import type { AuthResponse, User } from '@/types/api'

export interface LoginCredentials {
  email: string
  password: string
}

export async function login(credentials: LoginCredentials): Promise<AuthResponse> {
  return apiClient.post<AuthResponse>('/auth/login', credentials, { auth: false })
}

export async function logout(): Promise<void> {
  await apiClient.post<void>('/auth/logout')
}

export async function fetchCurrentUser(): Promise<User> {
  return apiClient.get<User>('/auth/me')
}
