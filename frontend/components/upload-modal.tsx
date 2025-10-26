"use client"

import { useState, useCallback } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Progress } from "@/components/ui/progress"
import { Upload, FileAudio, X, Sparkles, Check, AlertCircle } from "lucide-react"
import { apiClient } from "@/lib/api-client"
import { useTranscriptPolling } from "@/lib/use-polling"
import type { Folder } from "@/lib/types"
import { useRouter } from "next/navigation"
import React from "react"

type UploadStep = "select" | "uploading" | "processing" | "complete" | "error"

interface UploadModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  folders: Folder[]
  initialFile?: File | null
}

export function UploadModal({ open, onOpenChange, folders, initialFile }: UploadModalProps) {
  const router = useRouter()
  const [step, setStep] = useState<UploadStep>("select")
  const [file, setFile] = useState<File | null>(null)
  const [title, setTitle] = useState("")
  const [folderId, setFolderId] = useState<string>("")
  const [tags, setTags] = useState("")
  const [numSpeakers, setNumSpeakers] = useState("2")
  const [isDragging, setIsDragging] = useState(false)
  const [error, setError] = useState<string>("")
  const [transcriptId, setTranscriptId] = useState<string | null>(null)

  // Poll transcript status while processing
  const { status, progress, error: pollingError } = useTranscriptPolling(
    transcriptId,
    step === "processing"
  )

  // Update step based on polling status
  React.useEffect(() => {
    if (status === "completed" && step === "processing") {
      setStep("complete")
    } else if (status === "failed" && step === "processing") {
      setStep("error")
      setError(pollingError || "התמלול נכשל")
    }
  }, [status, step, pollingError])

  // Handle initial file when modal opens
  React.useEffect(() => {
    if (open && initialFile) {
      setFile(initialFile)
      setTitle(initialFile.name.replace(/\.[^/.]+$/, ""))
    }
  }, [open, initialFile])

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
      setFile(droppedFile)
      setTitle(droppedFile.name.replace(/\.[^/.]+$/, ""))
    }
  }, [])

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0]
    if (selectedFile) {
      setFile(selectedFile)
      setTitle(selectedFile.name.replace(/\.[^/.]+$/, ""))
    }
  }

  const handleUpload = async () => {
    if (!file || !title.trim()) return

    setStep("uploading")
    setError("")

    try {
      // Upload file to API
      const response = await apiClient.uploadTranscript(file, title, {
        folderId: folderId || undefined,
        tags: tags.trim() || undefined,
        enableDiarization: true,
        identifySpeakers: false,
        numSpeakers: numSpeakers ? parseInt(numSpeakers) : undefined,
        language: "he",
      })

      // Start polling for status
      setTranscriptId(response.transcript_id)
      setStep("processing")
    } catch (err) {
      setStep("error")
      setError(err instanceof Error ? err.message : "שגיאה בהעלאת קובץ")
    }
  }

  const handleComplete = () => {
    if (transcriptId) {
      router.push(`/transcript/${transcriptId}`)
      handleClose()
    }
  }

  const handleClose = () => {
    // Reset state
    setStep("select")
    setFile(null)
    setTitle("")
    setFolderId("")
    setTags("")
    setNumSpeakers("2")
    setError("")
    setTranscriptId(null)
    onOpenChange(false)
  }

  const handleReset = () => {
    setStep("select")
    setFile(null)
    setTitle("")
    setError("")
    setTranscriptId(null)
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-[18px] font-semibold">
            {step === "select" && "העלאת קובץ אודיו"}
            {step === "uploading" && "מעלה קובץ"}
            {step === "processing" && "מעבד עם AI"}
            {step === "complete" && "התמלול הושלם!"}
            {step === "error" && "שגיאה בתמלול"}
          </DialogTitle>
        </DialogHeader>

        {step === "select" && (
          <div className="space-y-4">
            {/* Drag and Drop Area */}
            <div
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
              className={`border-2 border-dashed rounded-lg p-8 text-center transition-all ${
                isDragging
                  ? "border-primary bg-primary/5"
                  : file
                    ? "border-primary/60 bg-primary/5"
                    : "border-border/60 hover:border-primary/40 hover:bg-muted/20"
              }`}
            >
              {file ? (
                <div className="space-y-3">
                  <div className="w-12 h-12 mx-auto rounded-lg bg-primary/10 flex items-center justify-center">
                    <FileAudio className="w-6 h-6 text-primary" />
                  </div>
                  <div>
                    <p className="text-[14px] font-semibold text-foreground break-all">{file.name}</p>
                    <p className="text-[12px] text-muted-foreground mt-1">
                      {(file.size / 1024 / 1024).toFixed(2)} MB
                    </p>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setFile(null)}
                    className="text-muted-foreground hover:text-foreground h-8 text-[12px]"
                  >
                    <X className="w-[14px] h-[14px] ml-2" />
                    הסר קובץ
                  </Button>
                </div>
              ) : (
                <div className="space-y-3">
                  <div className="w-12 h-12 mx-auto rounded-lg bg-muted/60 flex items-center justify-center">
                    <Upload className="w-6 h-6 text-muted-foreground" />
                  </div>
                  <div>
                    <p className="text-[14px] font-semibold text-foreground">גרור ושחרר קובץ אודיו</p>
                    <p className="text-[12px] text-muted-foreground">או לחץ לבחירה</p>
                  </div>
                  <input
                    type="file"
                    accept="audio/*"
                    onChange={handleFileSelect}
                    className="hidden"
                    id="file-upload-modal"
                  />
                  <label htmlFor="file-upload-modal">
                    <Button asChild className="cursor-pointer h-9 text-[13px]">
                      <span>בחר קובץ</span>
                    </Button>
                  </label>
                  <p className="text-[11px] text-muted-foreground">תומך ב-MP3, WAV, M4A ועוד</p>
                </div>
              )}
            </div>

            {/* Form Fields */}
            {file && (
              <div className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="title" className="text-[13px]">כותרת *</Label>
                  <Input
                    id="title"
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    placeholder="הזן כותרת לתמליל"
                    className="h-9 text-[13px]"
                    required
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="folder" className="text-[13px]">תיקייה (אופציונלי)</Label>
                  <select
                    id="folder"
                    value={folderId}
                    onChange={(e) => setFolderId(e.target.value)}
                    className="flex h-9 w-full rounded-md border border-border/60 bg-background px-3 py-2 text-[13px] ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                  >
                    <option value="">ללא תיקייה</option>
                    {folders.map((folder) => (
                      <option key={folder.id} value={folder.id}>
                        {folder.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="speakers" className="text-[13px]">מספר דוברים</Label>
                  <Input
                    id="speakers"
                    type="number"
                    min="1"
                    max="20"
                    value={numSpeakers}
                    onChange={(e) => setNumSpeakers(e.target.value)}
                    className="h-9 text-[13px]"
                  />
                  <p className="text-[11px] text-muted-foreground">מספר הדוברים הצפוי בקובץ האודיו</p>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="tags-modal" className="text-[13px]">תגיות (אופציונלי)</Label>
                  <Input
                    id="tags-modal"
                    value={tags}
                    onChange={(e) => setTags(e.target.value)}
                    placeholder="למשל: פגישה, שבועי, מוצר (מופרד בפסיקים)"
                    className="h-9 text-[13px]"
                  />
                </div>

                <Button
                  onClick={handleUpload}
                  className="w-full h-10 text-[13px]"
                  disabled={!title.trim()}
                >
                  <Sparkles className="w-[15px] h-[15px] ml-2" />
                  התחל תמלול
                </Button>
              </div>
            )}
          </div>
        )}

        {step === "uploading" && (
          <div className="space-y-4 text-center py-8">
            <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
              <Upload className="w-7 h-7 text-primary animate-pulse" />
            </div>
            <p className="text-[13px] text-muted-foreground">מעלה את הקובץ...</p>
            <div className="flex items-center justify-center gap-1.5">
              <div className="w-1.5 h-1.5 rounded-full bg-primary animate-bounce" style={{ animationDelay: "0ms" }} />
              <div className="w-1.5 h-1.5 rounded-full bg-primary animate-bounce" style={{ animationDelay: "150ms" }} />
              <div className="w-1.5 h-1.5 rounded-full bg-primary animate-bounce" style={{ animationDelay: "300ms" }} />
            </div>
          </div>
        )}

        {step === "processing" && (
          <div className="space-y-4 text-center py-8">
            <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
              <Sparkles className="w-7 h-7 text-primary animate-pulse" />
            </div>
            <div>
              <p className="text-[15px] font-semibold">מעבד עם AI</p>
              <p className="text-[13px] text-muted-foreground mt-1">ממליל את האודיו ומייצר תובנות</p>
            </div>
            <div className="space-y-2">
              <Progress value={progress} className="h-1.5" />
              <p className="text-[12px] text-muted-foreground font-medium tabular-nums">
                {progress}% הושלם
              </p>
            </div>
          </div>
        )}

        {step === "complete" && (
          <div className="space-y-4 text-center py-8">
            <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
              <Check className="w-7 h-7 text-primary" />
            </div>
            <p className="text-[13px] text-muted-foreground">האודיו תומלל בהצלחה</p>
            <div className="flex gap-2">
              <Button onClick={handleComplete} className="flex-1 h-10 text-[13px]">
                צפה בתמליל
              </Button>
              <Button onClick={handleReset} variant="outline" className="flex-1 h-10 text-[13px]">
                העלה נוסף
              </Button>
            </div>
          </div>
        )}

        {step === "error" && (
          <div className="space-y-4 text-center py-8">
            <div className="w-14 h-14 mx-auto rounded-xl bg-destructive/10 flex items-center justify-center">
              <AlertCircle className="w-7 h-7 text-destructive" />
            </div>
            <p className="text-[13px] text-destructive">{error}</p>
            <div className="flex gap-2">
              <Button onClick={handleReset} className="flex-1 h-10 text-[13px]">
                נסה שוב
              </Button>
              <Button onClick={handleClose} variant="outline" className="flex-1 h-10 text-[13px]">
                סגור
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
