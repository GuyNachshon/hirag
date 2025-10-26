"use client"

import { useState, useEffect } from "react"
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
  User,
  LogOut,
  Settings,
  Check,
  X,
  Pencil,
  Trash2,
  FolderMerge,
  MoreVertical,
} from "lucide-react"
import * as LucideIcons from "lucide-react"
import Link from "next/link"
import { useAuth } from "@/lib/auth-context"
import { apiClient } from "@/lib/api-client"
import type { Folder as FolderType, QuickAction } from "@/lib/types"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger, DropdownMenuSeparator, DropdownMenuLabel } from "@/components/ui/dropdown-menu"
import { UploadModal } from "./upload-modal"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { UploadProvider } from "@/lib/upload-context"

interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
}

interface AppLayoutProps {
  children: React.ReactNode
}

export function AppLayout({ children }: AppLayoutProps) {
  const { user, logout } = useAuth()
  const [selectedFolder, setSelectedFolder] = useState<string | null>(null) // null = "All Transcripts"
  const [folders, setFolders] = useState<FolderType[]>([])
  const [isLeftSidebarOpen, setIsLeftSidebarOpen] = useState(true)
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(true)
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([])
  const [chatInput, setChatInput] = useState("")
  const [chatSessionId, setChatSessionId] = useState<string | null>(null)
  const [isSendingMessage, setIsSendingMessage] = useState(false)
  const [isCreatingFolder, setIsCreatingFolder] = useState(false)
  const [newFolderName, setNewFolderName] = useState("")
  const [folderError, setFolderError] = useState("")
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)
  const [contextMenuFolder, setContextMenuFolder] = useState<FolderType | null>(null)
  const [isRenameDialogOpen, setIsRenameDialogOpen] = useState(false)
  const [renameValue, setRenameValue] = useState("")
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [deleteMoveToFolder, setDeleteMoveToFolder] = useState<string>("")
  const [quickActions, setQuickActions] = useState<QuickAction[]>([])
  const [uploadFile, setUploadFile] = useState<File | null>(null)

  // Fetch folders on mount
  useEffect(() => {
    const fetchFolders = async () => {
      try {
        const response = await apiClient.listFolders()
        setFolders(response.folders)
      } catch (error) {
        console.error("Failed to fetch folders:", error)
      }
    }

    if (user) {
      fetchFolders()
    }
  }, [user])

  // Load quick actions on mount
  useEffect(() => {
    const loadQuickActions = async () => {
      try {
        console.log("[AppLayout] Loading quick actions for folder context...")
        const response = await apiClient.getQuickActions("folder")
        console.log("[AppLayout] Quick actions loaded:", response)
        setQuickActions(response.actions)
      } catch (err) {
        console.error("[AppLayout] Failed to load quick actions:", err)
      }
    }

    if (user) {
      loadQuickActions()
    }
  }, [user])

  // Create chat session when user or folder changes
  useEffect(() => {
    const createChatSession = async () => {
      if (!user) return

      try {
        // Default to "all transcripts" context (no specific folder)
        // In the future, we can make this smarter to detect transcript view
        const contextId = selectedFolder || "all"
        const contextType = "folder"

        console.log("[AppLayout] Creating chat session:", { contextType, contextId })
        const session = await apiClient.createTranscriptionChatSession(
          contextType,
          contextId,
          "Chat Session"
        )

        console.log("[AppLayout] Chat session created:", session.session_id)
        setChatSessionId(session.session_id)
        setChatMessages([]) // Clear messages when context changes
      } catch (error) {
        console.error("[AppLayout] Failed to create chat session:", error)
      }
    }

    createChatSession()
  }, [user, selectedFolder])

  const handleLogout = () => {
    logout()
  }

  const handleCreateFolder = async () => {
    if (!newFolderName.trim()) {
      setFolderError("שם התיקייה לא יכול להיות ריק")
      return
    }

    try {
      const newFolder = await apiClient.createFolder(newFolderName.trim())
      // Refresh folders list
      const response = await apiClient.listFolders()
      setFolders(response.folders)
      // Select the newly created folder
      setSelectedFolder(newFolder.id)
      // Reset state
      setIsCreatingFolder(false)
      setNewFolderName("")
      setFolderError("")
    } catch (error) {
      setFolderError(error instanceof Error ? error.message : "שגיאה ביצירת תיקייה")
    }
  }

  const handleCancelCreateFolder = () => {
    setIsCreatingFolder(false)
    setNewFolderName("")
    setFolderError("")
  }

  const handleRenameFolder = async () => {
    if (!contextMenuFolder || !renameValue.trim()) return

    try {
      await apiClient.updateFolder(contextMenuFolder.id, renameValue.trim())
      // Refresh folders
      const response = await apiClient.listFolders()
      setFolders(response.folders)
      setIsRenameDialogOpen(false)
      setRenameValue("")
      setContextMenuFolder(null)
    } catch (error) {
      alert(error instanceof Error ? error.message : "שגיאה בשינוי שם תיקייה")
    }
  }

  const handleDeleteFolder = async () => {
    if (!contextMenuFolder) return

    try {
      await apiClient.deleteFolder(
        contextMenuFolder.id,
        deleteMoveToFolder || undefined
      )
      // Refresh folders
      const response = await apiClient.listFolders()
      setFolders(response.folders)
      // Clear selection if deleted folder was selected
      if (selectedFolder === contextMenuFolder.id) {
        setSelectedFolder(null)
      }
      setIsDeleteDialogOpen(false)
      setDeleteMoveToFolder("")
      setContextMenuFolder(null)
    } catch (error) {
      alert(error instanceof Error ? error.message : "שגיאה במחיקת תיקייה")
    }
  }

  const handleSendMessage = async () => {
    if (!chatInput.trim() || !chatSessionId || isSendingMessage) return

    const userMessageContent = chatInput
    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      role: "user",
      content: userMessageContent,
      timestamp: new Date(),
    }

    setChatMessages((prev) => [...prev, userMessage])
    setChatInput("")
    setIsSendingMessage(true)

    try {
      const contextId = selectedFolder || "all"
      const contextType = "folder"

      console.log("[AppLayout] Sending message:", { sessionId: chatSessionId, contextType, contextId })

      const response = await apiClient.sendTranscriptionChatMessage(
        chatSessionId,
        userMessageContent,
        contextType,
        contextId
      )

      console.log("[AppLayout] Received response:", response)

      const aiMessage: ChatMessage = {
        id: response.message_id,
        role: "assistant",
        content: response.content,
        timestamp: new Date(response.timestamp),
      }

      setChatMessages((prev) => [...prev, aiMessage])
    } catch (error) {
      console.error("[AppLayout] Failed to send message:", error)

      // Add error message to chat
      const errorMessage: ChatMessage = {
        id: (Date.now() + 1).toString(),
        role: "assistant",
        content: "מצטער, נתקלתי בשגיאה בעיבוד השאלה. נסה שוב.",
        timestamp: new Date(),
      }

      setChatMessages((prev) => [...prev, errorMessage])
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

  const uploadContextValue = {
    onOpenUpload: (file?: File) => {
      if (file) setUploadFile(file)
      setIsUploadModalOpen(true)
    },
    selectedFolder,
    folders
  }

  return (
    <UploadProvider value={uploadContextValue}>
    <div className="flex flex-col h-screen bg-background">
      {/* Unified Header */}
      <header className="border-b border-border/60 bg-card px-4 py-3 flex items-center gap-3 flex-shrink-0">
        <Button
          variant="ghost"
          size="icon"
          className="h-9 w-9"
          onClick={() => setIsLeftSidebarOpen(!isLeftSidebarOpen)}
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

        <Button
          size="sm"
          className="h-9 text-[13px] font-medium shadow-sm"
          onClick={() => setIsUploadModalOpen(true)}
        >
          <Plus className="w-[14px] h-[14px] ml-2" />
          תמליל חדש
        </Button>

        {/* User Menu */}
        {user && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full group">
                <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center group-hover:bg-primary transition-colors">
                  <User className="w-[14px] h-[14px] text-primary group-hover:text-primary-foreground transition-colors" />
                </div>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="w-48">
              <DropdownMenuLabel className="text-[13px]">
                <div className="flex flex-col">
                  <span className="font-semibold">{user.username}</span>
                  <span className="text-[11px] text-muted-foreground font-normal">משתמש</span>
                </div>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem className="text-[13px]" onClick={handleLogout}>
                <LogOut className="w-[14px] h-[14px] ml-2" />
                התנתק
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}

        <Button
          variant="ghost"
          size="icon"
          className="h-9 w-9"
          onClick={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
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
                onClick={() => setSelectedFolder(null)}
                className={`flex items-center gap-2 w-full px-3 py-2 rounded-lg transition-all ${
                  selectedFolder === null
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
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6"
                  onClick={() => setIsCreatingFolder(true)}
                  disabled={isCreatingFolder}
                >
                  <Plus className="w-[14px] h-[14px]" />
                </Button>
              </div>

              {/* Inline Folder Creation */}
              {isCreatingFolder && (
                <div className="px-3 pb-2">
                  <div className="flex items-center gap-1 bg-muted/40 rounded-lg px-2 py-1.5">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 flex-shrink-0 text-destructive hover:text-destructive hover:bg-destructive/10"
                      onClick={handleCancelCreateFolder}
                    >
                      <X className="w-[14px] h-[14px]" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 flex-shrink-0 text-primary hover:text-primary hover:bg-primary/10"
                      onClick={handleCreateFolder}
                      disabled={!newFolderName.trim()}
                    >
                      <Check className="w-[14px] h-[14px]" />
                    </Button>
                    <Input
                      value={newFolderName}
                      onChange={(e) => {
                        setNewFolderName(e.target.value)
                        setFolderError("")
                      }}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") handleCreateFolder()
                        if (e.key === "Escape") handleCancelCreateFolder()
                      }}
                      placeholder="שם תיקייה"
                      className="h-7 text-[13px] bg-background flex-1"
                      autoFocus
                      maxLength={100}
                    />
                  </div>
                  {folderError && (
                    <p className="text-[11px] text-destructive mt-1 px-2">{folderError}</p>
                  )}
                </div>
              )}
            </div>

            <nav className="flex-1 px-3 space-y-0.5 overflow-auto">
              {folders.map((folder) => {
                const isSelected = selectedFolder === folder.id
                return (
                  <div key={folder.id} className="relative group">
                    <button
                      onClick={() => setSelectedFolder(folder.id)}
                      onContextMenu={(e) => {
                        e.preventDefault()
                        setContextMenuFolder(folder)
                      }}
                      className={`w-full flex items-center justify-between px-3 py-2 rounded-lg transition-all ${
                        isSelected
                          ? "bg-primary/10 text-primary"
                          : "text-muted-foreground hover:bg-muted/60 hover:text-foreground"
                      }`}
                    >
                      <div className="flex items-center gap-2">
                        <Folder className="w-[16px] h-[16px]" />
                        <span className="text-[13px] font-semibold">{folder.name}</span>
                      </div>
                      <div
                        className={`w-6 h-6 flex items-center justify-center rounded text-[11px] font-medium tabular-nums ${
                          isSelected
                            ? "bg-primary/20 text-primary"
                            : "bg-muted text-muted-foreground"
                        }`}
                      >
                        {folder.transcript_count}
                      </div>
                    </button>

                    {/* Context Menu Dropdown */}
                    <DropdownMenu
                      open={contextMenuFolder?.id === folder.id}
                      onOpenChange={(open) => !open && setContextMenuFolder(null)}
                    >
                      <DropdownMenuTrigger asChild>
                        <div />
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="start" className="w-48">
                        <DropdownMenuItem
                          className="text-[13px]"
                          onClick={() => {
                            setRenameValue(folder.name)
                            setIsRenameDialogOpen(true)
                          }}
                        >
                          <Pencil className="w-[14px] h-[14px] ml-2" />
                          שנה שם
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          className="text-destructive text-[13px]"
                          onClick={() => setIsDeleteDialogOpen(true)}
                        >
                          <Trash2 className="w-[14px] h-[14px] ml-2" />
                          מחק תיקייה
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </div>
                )
              })}
            </nav>
          </aside>
        )}

        {/* Main Content */}
        {children}

        {isRightSidebarOpen && (
          <aside className="w-96 border-r border-border/60 bg-sidebar flex-col overflow-hidden hidden lg:flex" suppressHydrationWarning>
            <div className="flex flex-col h-full">
              <div className="px-5 py-4 border-b border-border/60 space-y-2">
                {quickActions.map((action) => {
                  const IconComponent = (LucideIcons as any)[action.icon] || LucideIcons.Circle
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
                  <Button
                    size="icon"
                    className="h-9 w-9 flex-shrink-0"
                    onClick={handleSendMessage}
                    disabled={!chatInput.trim() || isSendingMessage || !chatSessionId}
                  >
                    <Send className="w-[14px] h-[14px] scale-x-[-1]" />
                  </Button>
                </div>
              </div>
            </div>
          </aside>
        )}
      </div>

      {/* Upload Modal */}
      <UploadModal
        open={isUploadModalOpen}
        onOpenChange={(open) => {
          setIsUploadModalOpen(open)
          if (!open) setUploadFile(null) // Clear file when modal closes
        }}
        folders={folders}
        initialFile={uploadFile}
      />

      {/* Rename Folder Dialog */}
      <Dialog open={isRenameDialogOpen} onOpenChange={setIsRenameDialogOpen}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle className="text-[18px]">שנה שם תיקייה</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="rename-folder" className="text-[13px]">שם תיקייה</Label>
              <Input
                id="rename-folder"
                value={renameValue}
                onChange={(e) => setRenameValue(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleRenameFolder()
                }}
                placeholder="הזן שם חדש"
                className="h-9 text-[13px]"
                autoFocus
              />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button
              variant="outline"
              onClick={() => {
                setIsRenameDialogOpen(false)
                setRenameValue("")
              }}
              className="h-9 text-[13px]"
            >
              ביטול
            </Button>
            <Button
              onClick={handleRenameFolder}
              disabled={!renameValue.trim()}
              className="h-9 text-[13px]"
            >
              שמור
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete Folder Dialog */}
      <Dialog open={isDeleteDialogOpen} onOpenChange={setIsDeleteDialogOpen}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle className="text-[18px]">מחק תיקייה</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <p className="text-[13px] text-muted-foreground">
              האם אתה בטוח שברצונך למחוק את התיקייה "{contextMenuFolder?.name}"?
            </p>
            {contextMenuFolder && contextMenuFolder.transcript_count > 0 && (
              <div className="space-y-2">
                <Label htmlFor="move-to-folder" className="text-[13px]">
                  העבר {contextMenuFolder.transcript_count} תמלילים אל:
                </Label>
                <select
                  id="move-to-folder"
                  value={deleteMoveToFolder}
                  onChange={(e) => setDeleteMoveToFolder(e.target.value)}
                  className="flex h-9 w-full rounded-md border border-border/60 bg-background px-3 py-2 text-[13px] ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                >
                  <option value="">ללא תיקייה (הסר שיוך)</option>
                  {folders
                    .filter((f) => f.id !== contextMenuFolder.id)
                    .map((folder) => (
                      <option key={folder.id} value={folder.id}>
                        {folder.name}
                      </option>
                    ))}
                </select>
              </div>
            )}
          </div>
          <DialogFooter className="gap-2">
            <Button
              variant="outline"
              onClick={() => {
                setIsDeleteDialogOpen(false)
                setDeleteMoveToFolder("")
              }}
              className="h-9 text-[13px]"
            >
              ביטול
            </Button>
            <Button
              variant="destructive"
              onClick={handleDeleteFolder}
              className="h-9 text-[13px]"
            >
              מחק
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
    </UploadProvider>
  )
}
