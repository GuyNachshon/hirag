"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  Search,
  Plus,
  Menu,
  ArrowLeft,
  MessageSquare,
  FileAudio,
  Folder,
  PanelLeft,
  PanelRightOpen,
  ListTodo,
  Mail,
  HelpCircle,
  Send,
  Paperclip,
  Sparkles,
} from "lucide-react"
import Link from "next/link"

interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
}

const folders = [
  { name: "Weekly Sync", count: 8, icon: Folder },
  { name: "HR", count: 5, icon: Folder },
  { name: "CTO Progress", count: 4, icon: Folder },
  { name: "Sales", count: 7, icon: Folder },
]

interface AppLayoutProps {
  children: React.ReactNode
}

export function AppLayout({ children }: AppLayoutProps) {
  const [selectedFolder, setSelectedFolder] = useState("My Transcriptions")
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
          "I can help you search through all your transcripts. Based on your library, you have 24 transcripts across different folders including Weekly Sync, HR, CTO Progress, and Sales meetings.",
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

  return (
    <div className="flex flex-col h-screen bg-background">
      {/* Unified Header */}
      <header className="border-b border-border/60 bg-card px-4 py-3 flex items-center gap-3 flex-shrink-0">
        <Button
          variant="ghost"
          size="icon"
          className="h-9 w-9"
          onClick={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
        >
          <PanelRightOpen className="w-[18px] h-[18px]" />
        </Button>

        <Link href="/">
          <Button variant="ghost" size="icon" className="h-9 w-9">
            <ArrowLeft className="w-[18px] h-[18px] scale-x-[-1]" />
          </Button>
        </Link>

        <div className="flex-1 flex items-center justify-center max-w-2xl mx-auto">
          <div className="relative w-full">
            <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-[16px] h-[16px] text-muted-foreground" />
            <Input
              placeholder="חיפוש תמלילים..."
              className="pr-10 h-9 bg-muted/40 border-border/60 text-[13px] placeholder:text-muted-foreground/60 focus-visible:bg-background transition-colors w-full"
            />
          </div>
        </div>

        <Link href="/upload">
          <Button size="sm" className="h-9 text-[13px] font-medium shadow-sm">
            <Plus className="w-[14px] h-[14px] ml-2" />
            תמליל חדש
          </Button>
        </Link>

        <Button
          variant="ghost"
          size="icon"
          className="h-9 w-9"
          onClick={() => setIsLeftSidebarOpen(!isLeftSidebarOpen)}
        >
          <PanelLeft className="w-[18px] h-[18px]" />
        </Button>
      </header>

      {/* Content Area with Panels */}
      <div className="flex flex-1 overflow-hidden">
        {isLeftSidebarOpen && (
          <aside className="w-64 border-l border-border/60 bg-sidebar flex flex-col">
            {/* My Transcriptions Header */}
            <div className="px-3 pt-3 pb-4">
              <button
                onClick={() => setSelectedFolder("התמלילים שלי")}
                className={`flex items-center gap-2 w-full px-3 py-2 rounded-lg transition-all ${
                  selectedFolder === "התמלילים שלי"
                    ? "bg-primary/10 text-primary"
                    : "text-muted-foreground hover:bg-muted/60 hover:text-foreground"
                }`}
              >
                <FileAudio className="w-[16px] h-[16px]" />
                <h2 className="text-[13px] font-semibold">התמלילים שלי</h2>
              </button>
            </div>

            {/* Folders Section */}
            <div className="px-3 pb-0.5">
              <div className="flex items-center justify-between px-3 py-2">
                <h3 className="text-[12px] font-semibold text-muted-foreground uppercase tracking-wide">תיקיות</h3>
                <Button variant="ghost" size="icon" className="h-6 w-6">
                  <Plus className="w-[14px] h-[14px]" />
                </Button>
              </div>
            </div>

            <nav className="flex-1 px-3 space-y-0.5 overflow-auto">
              {folders.map((folder) => {
                const Icon = folder.icon
                const isSelected = selectedFolder === folder.name
                return (
                  <button
                    key={folder.name}
                    onClick={() => setSelectedFolder(folder.name)}
                    className={`w-full flex items-center justify-between px-3 py-2 rounded-lg transition-all duration-150 ${
                      isSelected
                        ? "bg-primary text-primary-foreground shadow-sm"
                        : "hover:bg-muted/60 text-foreground/80 hover:text-foreground"
                    }`}
                  >
                    <span
                      className={`text-[11px] font-medium tabular-nums ${isSelected ? "text-primary-foreground/70" : "text-muted-foreground"}`}
                    >
                      {folder.count}
                    </span>
                    <div className="flex items-center gap-2.5">
                      <span className="text-[13px] font-medium">{folder.name}</span>
                      <Icon className="w-[15px] h-[15px]" />
                    </div>
                  </button>
                )
              })}
            </nav>
          </aside>
        )}

        {/* Main Content */}
        {children}

        {isRightSidebarOpen && (
          <aside className="w-96 border-r border-border/60 bg-sidebar flex-col overflow-hidden hidden lg:flex">
            <div className="flex flex-col h-full" suppressHydrationWarning>
              <div className="px-5 py-4 border-b border-border/60 space-y-2">
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
                  onClick={() => handleQuickAction("מצא את כל התמלילים עם פעולות לביצוע")}
                >
                  <ListTodo className="w-[14px] h-[14px] ml-2 text-primary" />
                  מצא פעולות לביצוע
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
                  onClick={() => handleQuickAction("סכם את כל הפגישות האחרונות")}
                >
                  <Mail className="w-[14px] h-[14px] ml-2 text-primary" />
                  סכם פגישות
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
                  onClick={() => handleQuickAction("חפש נושאים ספציפיים בתמלילים")}
                >
                  <HelpCircle className="w-[14px] h-[14px] ml-2 text-primary" />
                  חפש נושאים
                </Button>
              </div>

              <div className="flex-1 overflow-auto px-5 py-4 space-y-4">
                {chatMessages.length === 0 ? (
                  <div className="flex items-center justify-center h-full">
                    <p className="text-[13px] text-muted-foreground text-center">שאל שאלות על התמלילים שלך</p>
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
                        <p className="text-[13px] leading-relaxed">{message.content}</p>
                      </div>
                      {message.role === "assistant" && (
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
                      placeholder="שוחח עם כל התמלילים"
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
          </aside>
        )}
      </div>
    </div>
  )
}
