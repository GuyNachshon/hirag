import { TranscriptViewer } from "@/components/transcript-viewer"

export default async function TranscriptPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return <TranscriptViewer transcriptId={id} />
}
