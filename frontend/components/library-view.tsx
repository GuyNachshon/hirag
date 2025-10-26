"use client"

import { useState } from "react"
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
} from "lucide-react"
import Link from "next/link"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"

interface Transcript {
  id: string
  title: string
  duration: string
  date: string
  status: "completed" | "enhancing" | "processing"
  folder: string
  speakers: string[]
}

const mockTranscripts: Transcript[] = [
  {
    id: "1",
    title: "סנכרון שבועי - צוות המוצר",
    duration: "45:32",
    date: "לפני שעתיים",
    status: "completed",
    folder: "סנכרון שבועי",
    speakers: ["שרה כהן", "מייק רודריגז", "אמה ווטסון"],
  },
  {
    id: "2",
    title: "הדרכת משאבי אנוש",
    duration: "28:15",
    date: "אתמול",
    status: "completed",
    folder: "משאבי אנוש",
    speakers: ["ג'ניפר לי", "דיוויד פארק"],
  },
  {
    id: "3",
    title: "עדכון התקדמות CTO - רבעון 1",
    duration: "1:12:45",
    date: "לפני יומיים",
    status: "enhancing",
    folder: "התקדמות CTO",
    speakers: ["ג'רמי קים", "דן פוסטר", "מאיה פטל"],
  },
  {
    id: "4",
    title: "שיחת גילוי לקוח - Acme Corp",
    duration: "35:20",
    date: "לפני 3 ימים",
    status: "completed",
    folder: "מכירות",
    speakers: ["אלכס טרנר", "כריס ג'ונסון"],
  },
]

const folders = [
  { name: "סנכרון שבועי", count: 8, icon: Folder },
  { name: "משאבי אנוש", count: 5, icon: Folder },
  { name: "התקדמות CTO", count: 4, icon: Folder },
  { name: "מכירות", count: 7, icon: Folder },
]

interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
}

export function LibraryView() {
  const [selectedFolder, setSelectedFolder] = useState("התמלילים שלי")
  const [isMobileSidebarOpen, setIsMobileSidebarOpen] = useState(false)
  const [isLeftSidebarOpen, setIsLeftSidebarOpen] = useState(true)
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(true)
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([])
  const [chatInput, setChatInput] = useState("")

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

  const ChatSidebar = () => (
    <div className="flex flex-col h-full" suppressHydrationWarning>

      <div className="px-5 py-4 border-b border-border/60 space-y-2">
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
          onClick={() => handleQuickAction("Find all transcripts with action items")}
        >
          <ListTodo className="w-[14px] h-[14px] mr-2 text-primary" />
          Find action items
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
          onClick={() => handleQuickAction("Summarize all recent meetings")}
        >
          <Mail className="w-[14px] h-[14px] mr-2 text-primary" />
          Summarize meetings
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
          onClick={() => handleQuickAction("Search for specific topics across transcripts")}
        >
          <HelpCircle className="w-[14px] h-[14px] mr-2 text-primary" />
          Search topics
        </Button>
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

  return (
    <main className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <div className="flex-1 overflow-auto px-6 py-6">
          {/* Folder Title */}
          <div className="mb-6">
            <h1 className="text-[24px] font-bold text-foreground mb-2">{selectedFolder}</h1>
          </div>

          {/* Drop Zone */}
          <div className="mb-6">
            <div className="border-2 border-dashed border-border/60 rounded-lg p-4 text-center hover:border-primary/50 hover:bg-muted/20 transition-all cursor-pointer">
              <p className="text-[13px] text-foreground">
                <span className="font-medium text-primary">גרור ושחרר</span> קובץ אודיו לתמלול.{" "}
                <span className="font-medium text-primary cursor-pointer hover:underline">לחץ לעיון</span>
              </p>
            </div>
          </div>

          {/* Transcripts List */}
          <div className="space-y-2">
            {mockTranscripts.map((transcript) => (
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
                          {transcript.duration}
                        </span>
                        <span className="hidden sm:inline">{transcript.date}</span>
                        <span className="text-muted-foreground/60">•</span>
                        <div className="flex items-center gap-1.5">
                          <Users className="w-3 h-3" />
                          <span className="text-[12px] font-medium">{transcript.speakers.join(", ")}</span>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 mt-2">
                        <Badge variant="outline" className="text-[11px] h-5 px-2 font-medium border-primary/30 text-primary">
                          {transcript.folder}
                        </Badge>
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 w-full sm:w-auto justify-end">
                    {transcript.status === "enhancing" && (
                      <Badge className="bg-accent text-accent-foreground text-[11px] h-6 px-2.5 font-medium">
                        <Sparkles className="w-3 h-3 ml-1" />
                        משפר...
                      </Badge>
                    )}
                    {transcript.status === "completed" && (
                      <Link href={`/transcript/${transcript.id}`}>
                        <Button variant="ghost" size="sm" className="h-8 text-[13px] font-medium">
                          <ChevronRight className="w-4 h-4 sm:mr-1 scale-x-[-1]" />
                          <span className="hidden sm:inline">פתח</span>
                        </Button>
                      </Link>
                    )}

                    <DropdownMenu>
                      <DropdownMenuTrigger asChild suppressHydrationWarning>
                        <Button variant="ghost" size="icon" className="flex-shrink-0 h-8 w-8">
                          <MoreVertical className="w-4 h-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="start" className="w-44">
                        <DropdownMenuItem className="text-[13px]">שתף</DropdownMenuItem>
                        <DropdownMenuItem className="text-[13px]">ייצא</DropdownMenuItem>
                        <DropdownMenuItem className="text-[13px]">העבר לתיקייה</DropdownMenuItem>
                        <DropdownMenuItem className="text-destructive text-[13px]">מחק</DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        </div>
      </main>
  )
}
