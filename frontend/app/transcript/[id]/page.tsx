import { TranscriptViewer } from "@/components/transcript-viewer"

export default function TranscriptPage({ params }: { params: { id: string } }) {
  return <TranscriptViewer transcriptId={params.id} />
}
