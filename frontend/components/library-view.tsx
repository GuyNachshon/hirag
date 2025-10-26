"use client"

import { useState, useEffect, useCallback, useRef } from "react"
import { useUpload } from "@/lib/upload-context"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Search,
  Upload,
  Folder,
  FileAudio,
  MoreVertical,
  ChevronRight,
  Clock,
  Sparkles,
  Menu,
  X,
  ChevronLeft,
  MessageSquare,
  Send,
  Paperclip,
  ListTodo,
  Mail,
  HelpCircle,
  Plus,
  PanelLeft,
  ArrowLeft,
  PanelRightOpen,
  Users,
  AlertCircle,
  Loader2,
} from "lucide-react"
import * as LucideIcons from "lucide-react"
import Link from "next/link"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { apiClient } from "@/lib/api-client"
import type { TranscriptListItem, FolderResponse, TranscriptStatus, QuickAction } from "@/lib/types"
import { useRouter } from "next/navigation"

interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
}

// Helper function to format duration from seconds
function formatDuration(seconds?: number): string {
  if (!seconds) return "0:00"
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}:${secs.toString().padStart(2, "0")}`
}

// Helper function to format relative time
function formatRelativeTime(dateString: string): string {
  const date = new Date(dateString)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMins < 60) return `לפני ${diffMins} דקות`
  if (diffHours < 24) return `לפני ${diffHours} שעות`
  if (diffDays === 1) return "אתמול"
  if (diffDays < 7) return `לפני ${diffDays} ימים`
  return date.toLocaleDateString("he-IL")
}

// Helper function to map API status to display status
function getDisplayStatus(status: TranscriptStatus): "completed" | "processing" | "enhancing" {
  switch (status) {
    case "completed":
      return "completed"
    case "processing":
    case "pending":
      return "processing"
    case "failed":
      return "completed" // Show as completed but with error styling
    default:
      return "processing"
  }
}

interface LibraryViewProps {
  // Props are now optional since we get them from context
  selectedFolder?: string | null
  folders?: FolderResponse[]
  onOpenUpload?: (file?: File) => void
}

export function LibraryView(props: LibraryViewProps) {
  const router = useRouter()

  // Get upload context (this will provide onOpenUpload, selectedFolder, folders)
  const { onOpenUpload, selectedFolder, folders } = useUpload()

  const [transcripts, setTranscripts] = useState<TranscriptListItem[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string>("")
  const [searchQuery, setSearchQuery] = useState("")
  const [isMobileSidebarOpen, setIsMobileSidebarOpen] = useState(false)
  const [isLeftSidebarOpen, setIsLeftSidebarOpen] = useState(true)
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(true)
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([])
  const [chatInput, setChatInput] = useState("")
  const [quickActions, setQuickActions] = useState<QuickAction[]>([])
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // Load transcripts when folder selection or search changes
  useEffect(() => {
    loadData()
  }, [selectedFolder, searchQuery])

  // Load quick actions on mount
  useEffect(() => {
    loadQuickActions()
  }, [])

  const loadData = async () => {
    try {
      setIsLoading(true)
      setError("")

      // Load transcripts
      const response = await apiClient.listTranscripts({
        folderId: selectedFolder || undefined,
      })

      setTranscripts(response.transcripts)
    } catch (err) {
      setError(err instanceof Error ? err.message : "שגיאה בטעינת נתונים")
    } finally {
      setIsLoading(false)
    }
  }

  const loadQuickActions = async () => {
    try {
      const response = await apiClient.getQuickActions("folder")
      setQuickActions(response.actions)
    } catch (err) {
      console.error("[LibraryView] Failed to load quick actions:", err)
      // Don't show error to user, just log it
    }
  }

  const handleDeleteTranscript = async (id: string) => {
    if (!confirm("האם אתה בטוח שברצונך למחוק תמליל זה?")) return

    try {
      await apiClient.deleteTranscript(id)
      // Reload data after deletion
      await loadData()
    } catch (err) {
      alert(err instanceof Error ? err.message : "שגיאה במחיקת תמליל")
    }
  }

  const handleSendMessage = () => {
    if (!chatInput.trim()) return

    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      role: "user",
      content: chatInput,
      timestamp: new Date(),
    }

    setChatMessages((prev) => [...prev, userMessage])
    setChatInput("")

    setTimeout(() => {
      const aiMessage: ChatMessage = {
        id: (Date.now() + 1).toString(),
        role: "assistant",
        content:
          "אני יכול לעזור לך לחפש בכל התמלילים שלך. בהתבסס על הספרייה שלך, יש לך 24 תמלילים בתיקיות שונות כולל סנכרון שבועי, משאבי אנוש, התקדמות CTO ופגישות מכירות.",
        timestamp: new Date(),
      }
      setChatMessages((prev) => [...prev, aiMessage])
    }, 1000)
  }

  const handleQuickAction = (prompt: string) => {
    setChatInput(prompt)
    setTimeout(() => {
      handleSendMessage()
    }, 0)
  }

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)

    const droppedFile = e.dataTransfer.files[0]
    if (droppedFile && droppedFile.type.startsWith("audio/")) {
      // Open upload modal with the dropped file
      onOpenUpload?.(droppedFile)
    }
  }, [onOpenUpload])

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0]
    if (selectedFile && selectedFile.type.startsWith("audio/")) {
      onOpenUpload?.(selectedFile)
    }
    // Reset input so the same file can be selected again
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
  }

  const handleDropZoneClick = () => {
    // Trigger the hidden file input
    fileInputRef.current?.click()
  }

  const ChatSidebar = () => {
    // Helper to get icon component by name
    const getIconComponent = (iconName: string) => {
      const IconComponent = (LucideIcons as any)[iconName]
      return IconComponent || LucideIcons.Circle
    }

    console.log("[LibraryView] Rendering ChatSidebar with quickActions:", quickActions)

    return (
    <div className="flex flex-col h-full" suppressHydrationWarning>

      <div className="px-5 py-4 border-b border-border/60 space-y-2">
        {quickActions.length === 0 && <p className="text-xs text-muted-foreground">טוען פעולות מהירות...</p>}
        {quickActions.map((action) => {
          const IconComponent = getIconComponent(action.icon)
          console.log("[LibraryView] Rendering action:", action.id, action.label)
          return (
            <Button
              key={action.id}
              variant="outline"
              size="sm"
              className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
              onClick={() => handleQuickAction(action.prompt_template)}
            >
              <IconComponent className="w-[14px] h-[14px] mr-2 text-primary" />
              {action.label}
            </Button>
          )
        })}
      </div>

      <div className="flex-1 overflow-auto px-5 py-4 space-y-4">
        {chatMessages.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <p className="text-[13px] text-muted-foreground text-center">Ask questions about your transcripts</p>
          </div>
        ) : (
          chatMessages.map((message) => (
            <div key={message.id} className={`flex gap-3 ${message.role === "user" ? "justify-end" : "justify-start"}`}>
              {message.role === "assistant" && (
                <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Sparkles className="w-[13px] h-[13px] text-primary" />
                </div>
              )}
              <div
                className={`max-w-[85%] rounded-xl px-3.5 py-2.5 ${
                  message.role === "user"
                    ? "bg-primary text-primary-foreground"
                    : "bg-muted/60 text-foreground border border-border/40"
                }`}
              >
                <p className="text-[13px] leading-relaxed">{message.content}</p>
              </div>
              {message.role === "user" && (
                <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[11px] font-semibold text-primary">You</span>
                </div>
              )}
            </div>
          ))
        )}
      </div>

      <div className="border-t border-border/60 p-4">
        <div className="flex gap-2">
          <div className="flex-1 relative">
            <Input
              placeholder="Chat with All Transcripts"
              value={chatInput}
              onChange={(e) => setChatInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault()
                  handleSendMessage()
                }
              }}
              className="h-9 text-[13px] pr-9 bg-muted/40 border-border/60 placeholder:text-muted-foreground/60 focus-visible:bg-background transition-colors"
            />
            <Button variant="ghost" size="icon" className="absolute right-1 top-1/2 -translate-y-1/2 h-7 w-7">
              <Paperclip className="w-[14px] h-[14px] text-muted-foreground" />
            </Button>
          </div>
          <Button
            size="icon"
            className="h-9 w-9 flex-shrink-0"
            onClick={handleSendMessage}
            disabled={!chatInput.trim()}
          >
            <Send className="w-[14px] h-[14px]" />
          </Button>
        </div>
      </div>
    </div>
    )
  }

  // Get selected folder name
  const selectedFolderName = selectedFolder
    ? folders.find((f) => f.id === selectedFolder)?.name || "תיקייה"
    : "התמלילים שלי"

  return (
    <main className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <div className="flex-1 overflow-auto px-6 py-6">
          {/* Folder Title */}
          <div className="mb-6">
            <h1 className="text-[24px] font-bold text-foreground mb-2">{selectedFolderName}</h1>
          </div>

          {/* Drop Zone */}
          <div className="mb-6">
            <input
              ref={fileInputRef}
              type="file"
              accept="audio/*"
              onChange={handleFileSelect}
              className="hidden"
            />
            <div
              className={`border-2 border-dashed rounded-lg p-4 text-center transition-all cursor-pointer ${
                isDragging
                  ? "border-primary bg-primary/5"
                  : "border-border/60 hover:border-primary/50 hover:bg-muted/20"
              }`}
              onClick={handleDropZoneClick}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
            >
              <p className="text-[13px] text-foreground">
                <span className="font-medium text-primary">גרור ושחרר</span> קובץ אודיו לתמלול.{" "}
                <span className="font-medium text-primary cursor-pointer hover:underline">לחץ לעיון</span>
              </p>
            </div>
          </div>

          {/* Error Message */}
          {error && (
            <div className="mb-6 p-3 rounded-lg bg-destructive/10 border border-destructive/30 flex items-start gap-2">
              <AlertCircle className="w-4 h-4 text-destructive flex-shrink-0 mt-0.5" />
              <p className="text-[13px] text-destructive">{error}</p>
            </div>
          )}

          {/* Loading State */}
          {isLoading && (
            <div className="flex items-center justify-center py-12">
              <Loader2 className="w-8 h-8 animate-spin text-primary" />
            </div>
          )}

          {/* Empty State */}
          {!isLoading && transcripts.length === 0 && (
            <div className="text-center py-12">
              <FileAudio className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
              <p className="text-[14px] text-muted-foreground">
                {searchQuery ? "לא נמצאו תמלילים" : "עדיין אין תמלילים"}
              </p>
              {!searchQuery && (
                <Button className="mt-4" onClick={handleDropZoneClick}>
                  <Upload className="w-4 h-4 ml-2" />
                  העלה קובץ ראשון
                </Button>
              )}
            </div>
          )}

          {/* Transcripts List */}
          {!isLoading && transcripts.length > 0 && (
            <div className="space-y-2">
              {transcripts.map((transcript) => {
                const displayStatus = getDisplayStatus(transcript.status)
                return (
                <Card
                  key={transcript.id}
                  className="px-5 py-4 hover:shadow-md hover:border-border transition-all duration-200 cursor-pointer group border-border/60"
                >
                  <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                    <div className="flex items-center gap-3.5 flex-1 min-w-0 w-full sm:w-auto">
                      <div className="w-10 h-10 rounded-lg bg-primary/8 flex items-center justify-center flex-shrink-0 group-hover:bg-primary/12 transition-colors">
                        <FileAudio className="w-[18px] h-[18px] text-primary" />
                      </div>

                      <div className="flex-1 min-w-0">
                        <Link href={`/transcript/${transcript.id}`}>
                          <h3 className="text-[14px] font-semibold text-foreground group-hover:text-primary transition-colors mb-1 truncate">
                            {transcript.title}
                          </h3>
                        </Link>
                        <div className="flex flex-wrap items-center gap-2 text-[12px] text-muted-foreground">
                          <span className="flex items-center gap-1.5 font-medium tabular-nums">
                            <Clock className="w-3 h-3" />
                            {formatDuration(transcript.duration)}
                          </span>
                          <span className="hidden sm:inline">{formatRelativeTime(transcript.created_at)}</span>
                          {transcript.speakers.length > 0 && (
                            <>
                              <span className="text-muted-foreground/60">•</span>
                              <div className="flex items-center gap-1.5">
                                <Users className="w-3 h-3" />
                                <span className="text-[12px] font-medium">{transcript.speakers.join(", ")}</span>
                              </div>
                            </>
                          )}
                        </div>
                        <div className="flex items-center gap-2 mt-2">
                          {transcript.folder_name && (
                            <Badge variant="outline" className="text-[11px] h-5 px-2 font-medium border-primary/30 text-primary">
                              {transcript.folder_name}
                            </Badge>
                          )}
                          {transcript.tags.map((tag) => (
                            <Badge key={tag} variant="outline" className="text-[11px] h-5 px-2 font-medium">
                              {tag}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 w-full sm:w-auto justify-end">
                      {displayStatus === "processing" && (
                        <Badge className="bg-accent text-accent-foreground text-[11px] h-6 px-2.5 font-medium">
                          <Loader2 className="w-3 h-3 ml-1 animate-spin" />
                          מעבד...
                        </Badge>
                      )}
                      {displayStatus === "completed" && (
                        <Link href={`/transcript/${transcript.id}`}>
                          <Button variant="ghost" size="sm" className="h-8 text-[13px] font-medium">
                            <span className="hidden sm:inline">פתח</span>
                            <ChevronRight className="w-4 h-4 sm:mr-1 scale-x-[-1]" />
                          </Button>
                        </Link>
                      )}
                      {transcript.status === "failed" && (
                        <Badge variant="destructive" className="text-[11px] h-6 px-2.5 font-medium">
                          <AlertCircle className="w-3 h-3 ml-1" />
                          נכשל
                        </Badge>
                      )}

                      <DropdownMenu>
                        <DropdownMenuTrigger asChild suppressHydrationWarning>
                          <Button variant="ghost" size="icon" className="flex-shrink-0 h-8 w-8">
                            <MoreVertical className="w-4 h-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="start" className="w-44">
                          <DropdownMenuItem
                            className="text-destructive text-[13px]"
                            onClick={() => handleDeleteTranscript(transcript.id)}
                          >
                            מחק
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  </div>
                </Card>
              )
            })}
            </div>
          )}
        </div>
      </main>
  )
}
