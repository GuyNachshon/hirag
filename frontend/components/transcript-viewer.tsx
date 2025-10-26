"use client"

import { useState, useEffect, useRef } from "react"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import {
  ArrowLeft,
  Search,
  Sparkles,
  Clock,
  Users,
  Lightbulb,
  ListTodo,
  MessageSquare,
  ChevronRight,
  Send,
  Paperclip,
  Plus,
  FileText,
  Mail,
  HelpCircle,
  Menu,
  Folder,
  FileAudio,
  ChevronLeft,
  X,
  UploadIcon,
  AudioWaveform,
  Text,
  Loader2,
  AlertCircle,
  GripVertical,
} from "lucide-react"
import * as LucideIcons from "lucide-react"
import Link from "next/link"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { apiClient } from "@/lib/api-client"
import type { TranscriptDetailResponse, TranscriptSegment as APITranscriptSegment, QuickAction } from "@/lib/types"

interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
  isLoading?: boolean
}

// Helper function to format seconds to timestamp
function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`
}

// Helper function to format duration
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

export function TranscriptViewer({ transcriptId }: { transcriptId: string }) {
  const [transcript, setTranscript] = useState<TranscriptDetailResponse | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string>("")
  const [isPlaying, setIsPlaying] = useState(false)
  const [searchQuery, setSearchQuery] = useState("")
  const [activeSegment, setActiveSegment] = useState<string | null>(null)
  const [currentView, setCurrentView] = useState<"transcript" | "insights">("transcript")
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([])
  const [chatInput, setChatInput] = useState("")
  const [isLeftSidebarOpen, setIsLeftSidebarOpen] = useState(true)
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(true)
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)
  const [speakerCount, setSpeakerCount] = useState("2")
  const [tags, setTags] = useState("")
  const [quickActions, setQuickActions] = useState<QuickAction[]>([])
  const [chatSessionId, setChatSessionId] = useState<string | null>(null)
  const [rightPanelWidth, setRightPanelWidth] = useState(400) // Default width in pixels
  const [isResizing, setIsResizing] = useState(false)
  const [isSendingMessage, setIsSendingMessage] = useState(false)

  // Load transcript on mount
  useEffect(() => {
    loadTranscript()
  }, [transcriptId])

  // Create chat session on mount
  useEffect(() => {
    if (transcriptId) {
      createChatSession()
    }
  }, [transcriptId])

  const createChatSession = async () => {
    try {
      const session = await apiClient.createTranscriptionChatSession("transcript", transcriptId)
      setChatSessionId(session.session_id)
    } catch (error) {
      console.error("Failed to create chat session:", error)
    }
  }

  // Load quick actions on mount
  useEffect(() => {
    loadQuickActions()
  }, [])

  const loadTranscript = async () => {
    try {
      setIsLoading(true)
      setError("")
      const data = await apiClient.getTranscript(transcriptId)
      setTranscript(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : "שגיאה בטעינת תמליל")
    } finally {
      setIsLoading(false)
    }
  }

  const loadQuickActions = async () => {
    try {
      const response = await apiClient.getQuickActions("transcript")
      setQuickActions(response.actions)
    } catch (err) {
      console.error("Failed to load quick actions:", err)
      // Don't show error to user, just log it
    }
  }

  const filteredTranscript = transcript?.segments.filter(
    (segment) =>
      segment.text.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (segment.speaker_label && segment.speaker_label.toLowerCase().includes(searchQuery.toLowerCase())),
  ) || []

  const handleSendMessage = async () => {
    if (!chatInput.trim() || !chatSessionId || isSendingMessage) return

    setIsSendingMessage(true)
    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      role: "user",
      content: chatInput,
      timestamp: new Date(),
    }

    // Add user message immediately
    setChatMessages((prev) => [...prev, userMessage])
    const currentInput = chatInput
    setChatInput("")

    // Add loading message
    const loadingMessage: ChatMessage = {
      id: (Date.now() + 1).toString(),
      role: "assistant",
      content: "",
      timestamp: new Date(),
      isLoading: true,
    }
    setChatMessages((prev) => [...prev, loadingMessage])

    try {
      // Send message to API
      const response = await apiClient.sendTranscriptionChatMessage(
        chatSessionId,
        currentInput,
        "transcript",
        transcriptId
      )

      // Replace loading message with actual response
      setChatMessages((prev) =>
        prev.map((msg) =>
          msg.id === loadingMessage.id
            ? { ...msg, content: response.content, isLoading: false }
            : msg
        )
      )
    } catch (error) {
      console.error("Failed to send message:", error)
      // Replace loading message with error
      setChatMessages((prev) =>
        prev.map((msg) =>
          msg.id === loadingMessage.id
            ? { ...msg, content: "מצטער, נתקלתי בשגיאה. אנא נסה שוב.", isLoading: false }
            : msg
        )
      )
    } finally {
      setIsSendingMessage(false)
    }
  }

  const handleQuickAction = (prompt: string) => {
    setChatInput(prompt)
    setTimeout(() => {
      handleSendMessage()
    }, 0)
  }

  const folders = [
    { name: "All Transcripts", count: 24, icon: FileAudio },
    { name: "Weekly Sync", count: 8, icon: Folder },
    { name: "HR", count: 5, icon: Folder },
    { name: "CTO Progress", count: 4, icon: Folder },
    { name: "Sales", count: 7, icon: Folder },
  ]

  const FoldersSidebar = () => (
    <div className="flex flex-col h-full">
      {/* My Transcriptions Header */}
      <div className="px-3 pt-3 pb-4">
        <Link href="/">
          <button
            className="flex items-center gap-2 w-full px-3 py-2 rounded-lg transition-all text-muted-foreground hover:bg-muted/60 hover:text-foreground"
          >
            <FileAudio className="w-[16px] h-[16px]" />
            <h2 className="text-[13px] font-semibold">My Transcriptions</h2>
          </button>
        </Link>
      </div>

      {/* Folders Section */}
      <div className="px-3 pb-0.5">
        <div className="flex items-center justify-between px-3 py-2">
          <h3 className="text-[12px] font-semibold text-muted-foreground uppercase tracking-wide">Folders</h3>
          <Button variant="ghost" size="icon" className="h-6 w-6">
            <Plus className="w-[14px] h-[14px]" />
          </Button>
        </div>
      </div>

      <nav className="flex-1 px-3 space-y-0.5 overflow-auto">
        {folders.map((folder) => {
          const Icon = folder.icon
          return (
            <Link href="/" key={folder.name}>
              <button
                className="w-full flex items-center justify-between px-3 py-2 rounded-lg transition-all duration-150 hover:bg-muted/60 text-foreground/80 hover:text-foreground"
              >
                <div className="flex items-center gap-2.5">
                  <Icon className="w-[15px] h-[15px]" />
                  <span className="text-[13px] font-medium">{folder.name}</span>
                </div>
                <span className="text-[11px] font-medium tabular-nums text-muted-foreground">{folder.count}</span>
              </button>
            </Link>
          )
        })}
      </nav>
    </div>
  )

  const ChatSidebar = () => {
    // Helper to get icon component by name
    const getIconComponent = (iconName: string) => {
      const IconComponent = (LucideIcons as any)[iconName]
      return IconComponent || LucideIcons.Circle
    }

    return (
    <div className="flex flex-col h-full" suppressHydrationWarning>
      <div className="px-5 py-4 border-b border-border/60 space-y-2">
        {quickActions.map((action) => {
          const IconComponent = getIconComponent(action.icon)
          return (
            <Button
              key={action.id}
              variant="outline"
              size="sm"
              className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
              onClick={() => handleQuickAction(action.prompt_template)}
            >
              <IconComponent className="w-[14px] h-[14px] ml-2 text-primary" />
              {action.label}
            </Button>
          )
        })}
      </div>

      <div className="flex-1 overflow-auto px-5 py-4 space-y-4">
        {chatMessages.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <p className="text-[13px] text-muted-foreground text-center">שאל שאלות על התמליל הזה</p>
          </div>
        ) : (
          chatMessages.map((message) => (
            <div key={message.id} className={`flex gap-3 ${message.role === "user" ? "justify-start" : "justify-end"}`}>
              {message.role === "user" && (
                <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[11px] font-semibold text-primary">את/ה</span>
                </div>
              )}
              <div
                className={`max-w-[85%] rounded-xl px-3.5 py-2.5 ${
                  message.role === "user"
                    ? "bg-primary text-primary-foreground"
                    : "bg-muted/60 text-foreground border border-border/40"
                }`}
              >
                {message.isLoading ? (
                  <div className="flex items-center gap-2">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span className="text-[13px] text-muted-foreground">מייצר תשובה...</span>
                  </div>
                ) : message.role === "assistant" ? (
                  <div className="prose prose-sm max-w-none dark:prose-invert prose-p:my-2 prose-ul:my-2 prose-ol:my-2 prose-li:my-0.5">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{message.content}</ReactMarkdown>
                  </div>
                ) : (
                  <p className="text-[13px] leading-relaxed">{message.content}</p>
                )}
              </div>
              {message.role === "assistant" && !message.isLoading && (
                <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Sparkles className="w-[13px] h-[13px] text-primary" />
                </div>
              )}
            </div>
          ))
        )}
      </div>

      <div className="border-t border-border/60 p-4">
        <div className="flex gap-2">
          <Button
            size="icon"
            className="h-9 w-9 flex-shrink-0"
            onClick={handleSendMessage}
            disabled={!chatInput.trim()}
          >
            <Send className="w-[14px] h-[14px] scale-x-[-1]" />
          </Button>
          <div className="flex-1 relative">
            <Input
              placeholder="שאל על התמליל הזה"
              value={chatInput}
              onChange={(e) => setChatInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault()
                  handleSendMessage()
                }
              }}
              className="h-9 text-[13px] pl-9 bg-muted/40 border-border/60 placeholder:text-muted-foreground/60 focus-visible:bg-background transition-colors"
            />
            <Button variant="ghost" size="icon" className="absolute left-1 top-1/2 -translate-y-1/2 h-7 w-7">
              <Paperclip className="w-[14px] h-[14px] text-muted-foreground" />
            </Button>
          </div>
        </div>
      </div>
    </div>
    )
  }

  const InsightsView = () => (
    <div className="max-w-4xl space-y-4">
      <Card className="p-5 border-border/60 hover:border-border transition-colors">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary/8 flex items-center justify-center flex-shrink-0">
            <MessageSquare className="w-[16px] h-[16px] text-primary" />
          </div>
          <div>
            <h3 className="text-[14px] font-semibold text-foreground mb-2">סיכום</h3>
            <p className="text-[13px] text-muted-foreground leading-relaxed">{mockInsights.summary}</p>
          </div>
        </div>
      </Card>

      <Card className="p-5 border-border/60 hover:border-border transition-colors">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary/8 flex items-center justify-center flex-shrink-0">
            <Lightbulb className="w-[16px] h-[16px] text-primary" />
          </div>
          <div className="flex-1">
            <h3 className="text-[14px] font-semibold text-foreground mb-3">נקודות מפתח</h3>
            <ul className="space-y-2.5">
              {mockInsights.keyPoints.map((point, index) => (
                <li key={index} className="flex gap-2.5 text-[13px] text-muted-foreground">
                  <span className="leading-relaxed">{point}</span>
                  <ChevronRight className="w-3.5 h-3.5 text-primary flex-shrink-0 mt-0.5 scale-x-[-1]" />
                </li>
              ))}
            </ul>
          </div>
        </div>
      </Card>

      <Card className="p-5 border-border/60 hover:border-border transition-colors">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary/8 flex items-center justify-center flex-shrink-0">
            <ListTodo className="w-[16px] h-[16px] text-primary" />
          </div>
          <div className="flex-1">
            <h3 className="text-[14px] font-semibold text-foreground mb-3">פעולות מעקב</h3>
            <div className="space-y-3">
              {mockInsights.actionItems.map((item, index) => (
                <div key={index} className="flex items-start gap-3 p-3 rounded-lg bg-muted/30">
                  <div className="flex-1 min-w-0">
                    <p className="text-[13px] font-medium text-foreground mb-2 leading-relaxed">{item.task}</p>
                    <div className="flex items-center gap-1.5">
                      <Badge variant="outline" className="text-[11px] h-5 px-2 font-medium">
                        {item.assignee}
                      </Badge>
                      <Badge
                        variant={item.priority === "high" ? "default" : "secondary"}
                        className="text-[11px] h-5 px-2 font-medium"
                      >
                        {item.priority === "high" ? "גבוה" : "בינוני"}
                      </Badge>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-5 border-border/60 hover:border-border transition-colors">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary/8 flex items-center justify-center flex-shrink-0">
            <Users className="w-[16px] h-[16px] text-primary" />
          </div>
          <div className="flex-1">
            <h3 className="text-[14px] font-semibold text-foreground mb-3">משתתפים</h3>
            <div className="flex flex-wrap gap-2">
              {mockInsights.participants.map((participant) => (
                <Badge key={participant} variant="secondary" className="text-[12px] h-6 px-3 font-medium">
                  {participant}
                </Badge>
              ))}
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-5 border-border/60 hover:border-border transition-colors">
        <div className="flex items-start gap-3">
          <div className="w-9 h-9 rounded-lg bg-primary/8 flex items-center justify-center flex-shrink-0">
            <FileText className="w-[16px] h-[16px] text-primary" />
          </div>
          <div className="flex-1">
            <h3 className="text-[14px] font-semibold text-foreground mb-3">נושאים שנדונו</h3>
            <div className="flex flex-wrap gap-2">
              {mockInsights.topics.map((topic, index) => (
                <Badge key={index} variant="outline" className="text-[12px] h-6 px-3 font-medium">
                  {topic}
                </Badge>
              ))}
            </div>
          </div>
        </div>
      </Card>
    </div>
  )

  // Loading state
  if (isLoading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    )
  }

  // Error state
  if (error || !transcript) {
    return (
      <div className="flex-1 flex items-center justify-center p-6">
        <Card className="p-8 max-w-md text-center">
          <AlertCircle className="w-12 h-12 mx-auto text-destructive mb-4" />
          <h2 className="text-[18px] font-semibold text-foreground mb-2">שגיאה בטעינת תמליל</h2>
          <p className="text-[13px] text-muted-foreground mb-4">{error || "תמליל לא נמצא"}</p>
          <Link href="/">
            <Button>חזור לדף הבית</Button>
          </Link>
        </Card>
      </div>
    )
  }

  const uniqueSpeakers = Array.from(new Set(transcript.segments.map((s) => s.speaker_label).filter(Boolean)))

  return (
      <div className="flex-1 flex flex-col min-w-0 relative overflow-hidden">
        <div className="flex-1 overflow-auto px-6 py-6">
          {currentView === "transcript" ? (
            <div className="max-w-4xl">
              <div className="mb-6">
                <h1 className="text-[22px] font-semibold text-foreground mb-2 tracking-tight">
                  {transcript.title}
                </h1>
                <div className="flex flex-wrap items-center gap-2 text-[12px] text-muted-foreground">
                  <span className="flex items-center gap-1.5 font-medium tabular-nums">
                    <Clock className="w-3 h-3" />
                    {formatDuration(transcript.duration)}
                  </span>
                  <span>{formatRelativeTime(transcript.created_at)}</span>
                  {uniqueSpeakers.length > 0 && (
                    <>
                      <span className="text-muted-foreground/60">•</span>
                      <div className="flex items-center gap-1.5">
                        <Users className="w-3 h-3" />
                        <span className="text-[12px] font-medium">
                          {uniqueSpeakers.join(", ")}
                        </span>
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

              <div className="space-y-1">
                {filteredTranscript.map((segment) => {
                  const speakerLabel = segment.speaker_label || "דובר"
                  const speakerInitials = speakerLabel.split(" ").map((n) => n[0]).join("")

                  return (
                    <div
                      key={segment.id}
                      className={`flex gap-3 px-4 py-3 rounded-lg transition-all duration-150 cursor-pointer ${
                        activeSegment === segment.id ? "bg-primary/5 shadow-sm" : "hover:bg-muted/40"
                      }`}
                      onClick={() => setActiveSegment(segment.id)}
                    >
                      <div className="flex-shrink-0">
                        <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center">
                          <span className="text-[11px] font-semibold text-primary">
                            {speakerInitials}
                          </span>
                        </div>
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-[13px] font-semibold text-foreground truncate">{speakerLabel}</span>
                          <span className="text-[11px] text-muted-foreground font-mono flex-shrink-0 tabular-nums">
                            {formatTimestamp(segment.start)}
                          </span>
                        </div>
                        <p className="text-[14px] text-foreground/90 leading-relaxed">{segment.text}</p>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          ) : (
            <div className="max-w-4xl">
              <h2 className="text-[22px] font-semibold text-foreground mb-6 tracking-tight">תובנות AI</h2>
              <InsightsView />
            </div>
          )}
        </div>

        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-10">
          <TooltipProvider>
            <div className="flex items-center gap-3">
              {/* New Transcript Button */}
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-12 w-12 rounded-full shadow-lg border border-border/60 bg-card hover:bg-muted/60 hover:scale-105 transition-all"
                    onClick={() => setIsUploadModalOpen(true)}
                  >
                    <AudioWaveform className="w-[20px] h-[20px]" strokeWidth={2.5} />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  <p>תמליל חדש</p>
                </TooltipContent>
              </Tooltip>

              {/* View Toggle Buttons */}
              <div className="flex items-center gap-0 bg-card border border-border/60 rounded-full shadow-lg p-1">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon"
                      className={`h-10 w-10 rounded-full transition-all ${
                        currentView === "transcript"
                          ? "bg-primary text-primary-foreground hover:bg-primary/90"
                          : "hover:bg-muted/40"
                      }`}
                      onClick={() => setCurrentView("transcript")}
                    >
                      <Text className="w-[18px] h-[18px]" strokeWidth={2.5} />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>תמליל</p>
                  </TooltipContent>
                </Tooltip>

                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon"
                      className={`h-10 w-10 rounded-full transition-all ${
                        currentView === "insights"
                          ? "bg-primary text-primary-foreground hover:bg-primary/90"
                          : "hover:bg-muted/40"
                      }`}
                      onClick={() => setCurrentView("insights")}
                    >
                      <Sparkles className="w-[18px] h-[18px]" strokeWidth={2.5} />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>תובנות AI</p>
                  </TooltipContent>
                </Tooltip>
              </div>
            </div>
          </TooltipProvider>
        </div>
      <Dialog open={isUploadModalOpen} onOpenChange={setIsUploadModalOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="text-[18px]">העלאת תמליל</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="speakers" className="text-[13px] font-medium">
                מספר דוברים
              </Label>
              <Input
                id="speakers"
                type="number"
                min="1"
                max="10"
                value={speakerCount}
                onChange={(e) => setSpeakerCount(e.target.value)}
                className="h-9 text-[13px]"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="tags" className="text-[13px] font-medium">
                תגיות (מופרדות בפסיק)
              </Label>
              <Input
                id="tags"
                placeholder="פגישה, מוצר, שבועי"
                value={tags}
                onChange={(e) => setTags(e.target.value)}
                className="h-9 text-[13px]"
              />
            </div>
            <div className="flex justify-start gap-2 pt-2">
              <Button size="sm" className="h-9 text-[13px]">
                התחל תמלול
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setIsUploadModalOpen(false)}
                className="h-9 text-[13px]"
              >
                ביטול
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
