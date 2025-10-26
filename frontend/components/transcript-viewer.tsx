"use client"

import type React from "react"

import { useState } from "react"
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
} from "lucide-react"
import Link from "next/link"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"

interface TranscriptSegment {
  id: string
  speaker: string
  timestamp: string
  text: string
  startTime: number
}

interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
}

const mockTranscript: TranscriptSegment[] = [
  {
    id: "1",
    speaker: "שרה כהן",
    timestamp: "00:00",
    text: "בוקר טוב לכולם! תודה שהצטרפתם לסנכרון המוצר של היום. בואו נתחיל בסבב מהיר של עדכונים מכל צוות.",
    startTime: 0,
  },
  {
    id: "2",
    speaker: "מייק רודריגז",
    timestamp: "00:15",
    text: "היי צוות! הצד ההנדסי עשה התקדמות נהדרת בלוח המחוונים החדש. השלמנו את רכיבי ויזואליזציית הנתונים והם מוכנים לבדיקת QA.",
    startTime: 15,
  },
  {
    id: "3",
    speaker: "שרה כהן",
    timestamp: "00:32",
    text: "אלו חדשות מצוינות, מייק. איך נראה הביצועים עם מערכי הנתונים הגדולים יותר?",
    startTime: 32,
  },
  {
    id: "4",
    speaker: "מייק רודריגז",
    timestamp: "00:38",
    text: "הביצועים מוצקים. אנחנו רואים זמני טעינה מתחת ל-2 שניות אפילו עם 10,000+ נקודות נתונים. הצוות עשה עבודה נהדרת באופטימיזציה של העיבוד.",
    startTime: 38,
  },
  {
    id: "5",
    speaker: "אמה ווטסון",
    timestamp: "00:52",
    text: "מנקודת מבט של עיצוב, סיימנו את הפריסות הרספונסיביות למובייל. אני אשתף את קבצי ה-Figma ב-Slack אחרי השיחה הזו.",
    startTime: 52,
  },
  {
    id: "6",
    speaker: "שרה כהן",
    timestamp: "01:05",
    text: "מושלם. בואו נוודא שנקבע מפגש סקירת עיצוב השבוע. מה לגבי המשוב מקבוצת הבטא?",
    startTime: 65,
  },
  {
    id: "7",
    speaker: "אמה ווטסון",
    timestamp: "01:15",
    text: "המשוב היה חיובי באופן מכריע. המשתמשים אוהבים את אפשרויות הסינון החדשות. הדאגה היחידה הייתה סביב ניגוד הצבעים במצב כהה, שכבר טיפלנו בו.",
    startTime: 75,
  },
  {
    id: "8",
    speaker: "מייק רודריגז",
    timestamp: "01:30",
    text: "אני רוצה לסמן דאגה טכנית אחת - אנחנו צריכים לדון בהגבלת קצב ה-API לפני ההשקה. המגבלות הנוכחיות עשויות לא להתמודד עם עומס המשתמשים החזוי שלנו.",
    startTime: 90,
  },
  {
    id: "9",
    speaker: "שרה כהן",
    timestamp: "01:45",
    text: "תפיסה טובה. בואו נוסיף את זה לפעולות שלנו. אתה יכול להכין מספרים על העומס הצפוי והמגבלות המומלצות לפגישה הבאה שלנו?",
    startTime: 105,
  },
  {
    id: "10",
    speaker: "מייק רודריגז",
    timestamp: "01:55",
    text: "בהחלט. יהיה לי ניתוח מפורט מוכן עד יום רביעי.",
    startTime: 115,
  },
]

const mockInsights = {
  summary:
    "סנכרון צוות המוצר שדן בהתקדמות פיתוח לוח המחוונים, השלמת עיצוב מובייל, משוב חיובי מבטא, וחששות הגבלת קצב API לפני ההשקה.",
  keyPoints: [
    "רכיבי ויזואליזציית נתונים של לוח המחוונים הושלמו ומוכנים ל-QA",
    "ביצועים מותאמים - זמני טעינה מתחת ל-2 שניות עם 10K+ נקודות נתונים",
    "פריסות רספונסיביות למובייל הושלמו, קבצי Figma ישותפו",
    "משוב משתמשי בטא חיובי מאוד, בעיית ניגוד במצב כהה נפתרה",
    "הגבלת קצב API דורשת סקירה לפני ההשקה כדי להתמודד עם עומס משתמשים חזוי",
  ],
  actionItems: [
    {
      task: "קבע מפגש סקירת עיצוב השבוע",
      assignee: "שרה כהן",
      priority: "high",
    },
    {
      task: "שתף קבצי Figma לפריסות מובייל ב-Slack",
      assignee: "אמה ווטסון",
      priority: "medium",
    },
    {
      task: "הכן ניתוח הגבלת קצב API עד יום רביעי",
      assignee: "מייק רודריגז",
      priority: "high",
    },
  ],
  participants: ["שרה כהן", "מייק רודריגז", "אמה ווטסון"],
  topics: ["פיתוח לוח מחוונים", "עיצוב מובייל", "משוב בטא", "תשתית API"],
  sentiment: "positive",
}

export function TranscriptViewer({ transcriptId }: { transcriptId: string }) {
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

  const filteredTranscript = mockTranscript.filter(
    (segment) =>
      segment.text.toLowerCase().includes(searchQuery.toLowerCase()) ||
      segment.speaker.toLowerCase().includes(searchQuery.toLowerCase()),
  )

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
          "בהתבסס על התמליל, אני יכול לעזור לך עם זה. הצוות דן בהתקדמות פיתוח לוח המחוונים, כאשר מייק רודריגז דיווח שרכיבי ויזואליזציית הנתונים הושלמו והביצועים מותאמים למתחת ל-2 שניות עבור 10K+ נקודות נתונים.",
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

  const ChatSidebar = () => (
    <div className="flex flex-col h-full" suppressHydrationWarning>
      <div className="px-5 py-4 border-b border-border/60 space-y-2">
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
          onClick={() => handleQuickAction("רשום את כל פעולות המעקב מהתמליל הזה")}
        >
          <ListTodo className="w-[14px] h-[14px] ml-2 text-primary" />
          רשום פעולות מעקב
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
          onClick={() => handleQuickAction("כתוב מייל מעקב על סמך השיחה הזו")}
        >
          <Mail className="w-[14px] h-[14px] ml-2 text-primary" />
          כתוב מייל מעקב
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start h-9 text-[13px] font-medium border-border/60 bg-transparent hover:bg-muted/60 hover:text-foreground"
          onClick={() => handleQuickAction("רשום את כל השאלות והתשובות מהתמליל הזה")}
        >
          <HelpCircle className="w-[14px] h-[14px] ml-2 text-primary" />
          רשום שאלות ותשובות
        </Button>
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

  return (
      <div className="flex-1 flex flex-col min-w-0 relative overflow-hidden">
        <div className="flex-1 overflow-auto px-6 py-6">
          {currentView === "transcript" ? (
            <div className="max-w-4xl">
              <div className="mb-6">
                <h1 className="text-[22px] font-semibold text-foreground mb-2 tracking-tight">
                  סנכרון שבועי - צוות המוצר
                </h1>
                <div className="flex flex-wrap items-center gap-2 text-[12px] text-muted-foreground">
                  <span className="flex items-center gap-1.5 font-medium tabular-nums">
                    <Clock className="w-3 h-3" />
                    45:32
                  </span>
                  <span>לפני שעתיים</span>
                  <span className="text-muted-foreground/60">•</span>
                  <div className="flex items-center gap-1.5">
                    <Users className="w-3 h-3" />
                    <span className="text-[12px] font-medium">
                      {Array.from(new Set(mockTranscript.map((s) => s.speaker))).join(", ")}
                    </span>
                  </div>
                </div>
                <div className="flex items-center gap-2 mt-2">
                  <Badge variant="outline" className="text-[11px] h-5 px-2 font-medium border-primary/30 text-primary">
                    סנכרון שבועי
                  </Badge>
                </div>
              </div>

              <div className="space-y-1">
                {filteredTranscript.map((segment) => (
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
                          {segment.speaker
                            .split(" ")
                            .map((n) => n[0])
                            .join("")}
                        </span>
                      </div>
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-[13px] font-semibold text-foreground truncate">{segment.speaker}</span>
                        <span className="text-[11px] text-muted-foreground font-mono flex-shrink-0 tabular-nums">
                          {segment.timestamp}
                        </span>
                      </div>
                      <p className="text-[14px] text-foreground/90 leading-relaxed">{segment.text}</p>
                    </div>
                  </div>
                ))}
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
