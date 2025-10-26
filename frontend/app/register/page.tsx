"use client"

import { useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card } from '@/components/ui/card'
import Link from 'next/link'
import { FileAudio, AlertCircle, CheckCircle2 } from 'lucide-react'

export default function RegisterPage() {
  const { register } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState('')
  const [isLoading, setIsLoading] = useState(false)

  const validateForm = (): boolean => {
    if (username.length < 3) {
      setError('שם המשתמש חייב להכיל לפחות 3 תווים')
      return false
    }

    if (password.length < 6) {
      setError('הסיסמה חייבת להכיל לפחות 6 תווים')
      return false
    }

    if (password !== confirmPassword) {
      setError('הסיסמאות אינן תואמות')
      return false
    }

    return true
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')

    if (!validateForm()) {
      return
    }

    setIsLoading(true)

    try {
      await register(username, password)
      // Redirect handled by auth context
    } catch (err) {
      setError(err instanceof Error ? err.message : 'שגיאה ברישום')
    } finally {
      setIsLoading(false)
    }
  }

  // Password strength indicator
  const getPasswordStrength = () => {
    if (password.length === 0) return null
    if (password.length < 6) return { level: 'weak', text: 'חלשה', color: 'bg-destructive' }
    if (password.length < 10) return { level: 'medium', text: 'בינונית', color: 'bg-yellow-500' }
    return { level: 'strong', text: 'חזקה', color: 'bg-green-500' }
  }

  const passwordStrength = getPasswordStrength()

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md p-8 border-border/60">
        {/* Logo/Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="w-16 h-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <FileAudio className="w-8 h-8 text-primary" />
          </div>
          <h1 className="text-[24px] font-bold text-foreground">הרשמה</h1>
          <p className="text-[13px] text-muted-foreground mt-1">
            צור חשבון חדש במערכת התמלול
          </p>
        </div>

        {/* Error Message */}
        {error && (
          <div className="mb-6 p-3 rounded-lg bg-destructive/10 border border-destructive/30 flex items-start gap-2">
            <AlertCircle className="w-4 h-4 text-destructive flex-shrink-0 mt-0.5" />
            <p className="text-[13px] text-destructive">{error}</p>
          </div>
        )}

        {/* Register Form */}
        <form onSubmit={handleSubmit} className="space-y-4" suppressHydrationWarning>
          <div className="space-y-2" suppressHydrationWarning>
            <Label htmlFor="username" className="text-[13px] font-medium">
              שם משתמש
            </Label>
            <Input
              id="username"
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="בחר שם משתמש (לפחות 3 תווים)"
              className="h-10 text-[14px] border-border/60"
              required
              disabled={isLoading}
              autoFocus
              minLength={3}
              maxLength={50}
            />
            {username.length > 0 && username.length >= 3 && (
              <div className="flex items-center gap-1 text-green-600">
                <CheckCircle2 className="w-3 h-3" />
                <span className="text-[11px]">שם משתמש תקין</span>
              </div>
            )}
          </div>

          <div className="space-y-2" suppressHydrationWarning>
            <Label htmlFor="password" className="text-[13px] font-medium">
              סיסמה
            </Label>
            <Input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="בחר סיסמה (לפחות 6 תווים)"
              className="h-10 text-[14px] border-border/60"
              required
              disabled={isLoading}
              minLength={6}
            />
            {passwordStrength && (
              <div className="flex items-center gap-2">
                <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden">
                  <div
                    className={`h-full ${passwordStrength.color} transition-all`}
                    style={{
                      width:
                        passwordStrength.level === 'weak'
                          ? '33%'
                          : passwordStrength.level === 'medium'
                            ? '66%'
                            : '100%',
                    }}
                  />
                </div>
                <span className="text-[11px] text-muted-foreground">
                  {passwordStrength.text}
                </span>
              </div>
            )}
          </div>

          <div className="space-y-2" suppressHydrationWarning>
            <Label htmlFor="confirmPassword" className="text-[13px] font-medium">
              אימות סיסמה
            </Label>
            <Input
              id="confirmPassword"
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              placeholder="הזן את הסיסמה שוב"
              className="h-10 text-[14px] border-border/60"
              required
              disabled={isLoading}
            />
            {confirmPassword.length > 0 && (
              password === confirmPassword ? (
                <div className="flex items-center gap-1 text-green-600">
                  <CheckCircle2 className="w-3 h-3" />
                  <span className="text-[11px]">הסיסמאות תואמות</span>
                </div>
              ) : (
                <div className="flex items-center gap-1 text-destructive">
                  <AlertCircle className="w-3 h-3" />
                  <span className="text-[11px]">הסיסמאות אינן תואמות</span>
                </div>
              )
            )}
          </div>

          <Button
            type="submit"
            className="w-full h-10 text-[14px] font-medium"
            disabled={isLoading}
          >
            {isLoading ? (
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin"></div>
                <span>נרשם...</span>
              </div>
            ) : (
              'הירשם'
            )}
          </Button>
        </form>

        {/* Login Link */}
        <div className="mt-6 text-center">
          <p className="text-[13px] text-muted-foreground">
            כבר יש לך חשבון?{' '}
            <Link
              href="/login"
              className="text-primary hover:underline font-medium"
            >
              התחבר כאן
            </Link>
          </p>
        </div>
      </Card>
    </div>
  )
}
