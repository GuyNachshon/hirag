"use client"

import type React from "react"

import { useState, useCallback } from "react"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Progress } from "@/components/ui/progress"
import { Upload, FileAudio, X, ArrowLeft, Sparkles, Check } from "lucide-react"
import Link from "next/link"
import { useRouter } from "next/navigation"

type UploadStep = "select" | "uploading" | "processing" | "complete"

export function UploadFlow() {
  const router = useRouter()
  const [step, setStep] = useState<UploadStep>("select")
  const [file, setFile] = useState<File | null>(null)
  const [title, setTitle] = useState("")
  const [folder, setFolder] = useState("")
  const [uploadProgress, setUploadProgress] = useState(0)
  const [isDragging, setIsDragging] = useState(false)

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
    if (!file) return

    setStep("uploading")

    // Simulate upload progress
    const interval = setInterval(() => {
      setUploadProgress((prev) => {
        if (prev >= 100) {
          clearInterval(interval)
          setStep("processing")
          // Simulate processing time
          setTimeout(() => {
            setStep("complete")
          }, 3000)
          return 100
        }
        return prev + 10
      })
    }, 300)
  }

  const handleComplete = () => {
    router.push("/")
  }

  return (
    <div className="min-h-screen bg-background flex flex-col">
      {/* Header */}
      <header className="border-b border-border/60 bg-card px-6 py-4">
        <div className="flex items-center gap-3">
          <Link href="/">
            <Button variant="ghost" size="icon" className="h-8 w-8">
              <ArrowLeft className="w-[18px] h-[18px]" />
            </Button>
          </Link>
          <div>
            <h1 className="text-[18px] font-semibold text-foreground tracking-tight">Upload Audio</h1>
            <p className="text-[12px] text-muted-foreground hidden sm:block">
              Transform your audio into searchable transcripts
            </p>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 flex items-center justify-center p-6">
        <div className="w-full max-w-2xl">
          {step === "select" && (
            <Card className="p-8 border-border/60">
              <div className="space-y-6">
                {/* Drag and Drop Area */}
                <div
                  onDragOver={handleDragOver}
                  onDragLeave={handleDragLeave}
                  onDrop={handleDrop}
                  className={`border-2 border-dashed rounded-xl p-12 text-center transition-all duration-200 ${
                    isDragging
                      ? "border-primary bg-primary/5 scale-[0.99]"
                      : file
                        ? "border-primary/60 bg-primary/5"
                        : "border-border/60 hover:border-primary/40 hover:bg-muted/20"
                  }`}
                >
                  {file ? (
                    <div className="space-y-4">
                      <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
                        <FileAudio className="w-7 h-7 text-primary" />
                      </div>
                      <div>
                        <p className="text-[15px] font-semibold text-foreground break-all px-4">{file.name}</p>
                        <p className="text-[13px] text-muted-foreground mt-1">
                          {(file.size / 1024 / 1024).toFixed(2)} MB
                        </p>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setFile(null)}
                        className="text-muted-foreground hover:text-foreground h-8 text-[13px]"
                      >
                        <X className="w-[15px] h-[15px] mr-2" />
                        Remove file
                      </Button>
                    </div>
                  ) : (
                    <div className="space-y-4">
                      <div className="w-14 h-14 mx-auto rounded-xl bg-muted/60 flex items-center justify-center">
                        <Upload className="w-7 h-7 text-muted-foreground" />
                      </div>
                      <div>
                        <p className="text-[15px] font-semibold text-foreground mb-1">
                          <span className="hidden sm:inline">Drag and drop your audio file</span>
                          <span className="sm:hidden">Upload your audio file</span>
                        </p>
                        <p className="text-[13px] text-muted-foreground hidden sm:block">or click to browse</p>
                      </div>
                      <input
                        type="file"
                        accept="audio/*"
                        onChange={handleFileSelect}
                        className="hidden"
                        id="file-upload"
                      />
                      <label htmlFor="file-upload">
                        <Button asChild className="cursor-pointer h-9 text-[13px] font-medium shadow-sm">
                          <span>Choose File</span>
                        </Button>
                      </label>
                      <p className="text-[11px] text-muted-foreground">Supports MP3, WAV, M4A, and more</p>
                    </div>
                  )}
                </div>

                {/* File Details */}
                {file && (
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <Label htmlFor="title" className="text-[13px] font-medium">
                        Title
                      </Label>
                      <Input
                        id="title"
                        value={title}
                        onChange={(e) => setTitle(e.target.value)}
                        placeholder="Enter transcript title"
                        className="h-9 text-[13px] border-border/60"
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="folder" className="text-[13px] font-medium">
                        Folder (optional)
                      </Label>
                      <Input
                        id="folder"
                        value={folder}
                        onChange={(e) => setFolder(e.target.value)}
                        placeholder="e.g., Weekly Sync, Sales Calls"
                        className="h-9 text-[13px] border-border/60"
                      />
                    </div>

                    <Button onClick={handleUpload} className="w-full h-10 text-[13px] font-medium shadow-sm">
                      <Sparkles className="w-[15px] h-[15px] mr-2" />
                      Start Transcription
                    </Button>
                  </div>
                )}
              </div>
            </Card>
          )}

          {step === "uploading" && (
            <Card className="p-8 border-border/60">
              <div className="space-y-6 text-center">
                <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
                  <Upload className="w-7 h-7 text-primary animate-pulse" />
                </div>
                <div>
                  <h2 className="text-[18px] font-semibold text-foreground mb-1">Uploading your file</h2>
                  <p className="text-[13px] text-muted-foreground">Please wait while we upload your audio file</p>
                </div>
                <div className="space-y-2">
                  <Progress value={uploadProgress} className="h-1.5" />
                  <p className="text-[12px] text-muted-foreground font-medium tabular-nums">
                    {uploadProgress}% complete
                  </p>
                </div>
              </div>
            </Card>
          )}

          {step === "processing" && (
            <Card className="p-8 border-border/60">
              <div className="space-y-6 text-center">
                <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
                  <Sparkles className="w-7 h-7 text-primary animate-pulse" />
                </div>
                <div>
                  <h2 className="text-[18px] font-semibold text-foreground mb-1">Processing with AI</h2>
                  <p className="text-[13px] text-muted-foreground">
                    We're transcribing your audio and generating insights
                  </p>
                </div>
                <div className="flex items-center justify-center gap-1.5">
                  <div
                    className="w-1.5 h-1.5 rounded-full bg-primary animate-bounce"
                    style={{ animationDelay: "0ms" }}
                  />
                  <div
                    className="w-1.5 h-1.5 rounded-full bg-primary animate-bounce"
                    style={{ animationDelay: "150ms" }}
                  />
                  <div
                    className="w-1.5 h-1.5 rounded-full bg-primary animate-bounce"
                    style={{ animationDelay: "300ms" }}
                  />
                </div>
              </div>
            </Card>
          )}

          {step === "complete" && (
            <Card className="p-8 border-border/60">
              <div className="space-y-6 text-center">
                <div className="w-14 h-14 mx-auto rounded-xl bg-primary/10 flex items-center justify-center">
                  <Check className="w-7 h-7 text-primary" />
                </div>
                <div>
                  <h2 className="text-[18px] font-semibold text-foreground mb-1">Transcription Complete!</h2>
                  <p className="text-[13px] text-muted-foreground">Your audio has been successfully transcribed</p>
                </div>
                <div className="flex flex-col sm:flex-row gap-2.5">
                  <Button onClick={handleComplete} className="flex-1 h-10 text-[13px] font-medium shadow-sm">
                    View Transcript
                  </Button>
                  <Button
                    onClick={() => {
                      setStep("select")
                      setFile(null)
                      setTitle("")
                      setFolder("")
                      setUploadProgress(0)
                    }}
                    variant="outline"
                    className="flex-1 h-10 text-[13px] font-medium border-border/60"
                  >
                    Upload Another
                  </Button>
                </div>
              </div>
            </Card>
          )}
        </div>
      </main>
    </div>
  )
}
