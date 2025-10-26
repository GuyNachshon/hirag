"use client"

import { useState } from 'react'
import { useAuth } from '@/lib/auth-context'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card } from '@/components/ui/card'
import Link from 'next/link'
import { FileAudio, AlertCircle } from 'lucide-react'

export default function LoginPage() {
  const { login } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [isLoading, setIsLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setIsLoading(true)

    try {
      await login(username, password)
      // Redirect handled by auth context
    } catch (err) {
      setError(err instanceof Error ? err.message : 'שגיאה בהתחברות')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md p-8 border-border/60">
        {/* Logo/Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="w-16 h-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <FileAudio className="w-8 h-8 text-primary" />
          </div>
          <h1 className="text-[24px] font-bold text-foreground">התחברות</h1>
          <p className="text-[13px] text-muted-foreground mt-1">
            מערכת תמלול חכמה
          </p>
        </div>

        {/* Error Message */}
        {error && (
          <div className="mb-6 p-3 rounded-lg bg-destructive/10 border border-destructive/30 flex items-start gap-2">
            <AlertCircle className="w-4 h-4 text-destructive flex-shrink-0 mt-0.5" />
            <p className="text-[13px] text-destructive">{error}</p>
          </div>
        )}

        {/* Login Form */}
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
              placeholder="הזן שם משתמש"
              className="h-10 text-[14px] border-border/60"
              required
              disabled={isLoading}
              autoFocus
            />
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
              placeholder="הזן סיסמה"
              className="h-10 text-[14px] border-border/60"
              required
              disabled={isLoading}
            />
          </div>

          <Button
            type="submit"
            className="w-full h-10 text-[14px] font-medium"
            disabled={isLoading}
          >
            {isLoading ? (
              <div className="flex items-center gap-2">
                <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin"></div>
                <span>מתחבר...</span>
              </div>
            ) : (
              'התחבר'
            )}
          </Button>
        </form>

        {/* Register Link */}
        <div className="mt-6 text-center">
          <p className="text-[13px] text-muted-foreground">
            עדיין אין לך חשבון?{' '}
            <Link
              href="/register"
              className="text-primary hover:underline font-medium"
            >
              הירשם כאן
            </Link>
          </p>
        </div>
      </Card>
    </div>
  )
}
