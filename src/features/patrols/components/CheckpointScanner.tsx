import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import type { CheckpointScanType } from '@/features/patrols/types/patrol.types';

// The BarcodeDetector Web API isn't in TypeScript's lib.dom.d.ts yet.
interface BarcodeDetectorResult {
  rawValue: string;
}
interface BarcodeDetectorLike {
  detect: (source: HTMLVideoElement) => Promise<BarcodeDetectorResult[]>;
}
declare global {
  interface Window {
    BarcodeDetector?: new (options?: { formats: string[] }) => BarcodeDetectorLike;
  }
}

export interface CheckpointScannerProps {
  onScan: (code: string, method: CheckpointScanType) => void | Promise<void>;
  isSubmitting: boolean;
}

/**
 * Two real, independent input paths to the same `scan_checkpoint(code)`
 * call — never a placeholder. Manual entry always works and is the
 * reliable path on the older, camera-flaky Android phones the brief calls
 * out; the camera path is progressive enhancement only, via the
 * BarcodeDetector Web API where the browser actually supports it (no
 * bundled QR-decoding library was added for this — the brief forbids
 * inventing a dependency choice quietly; this is the zero-dependency,
 * standards-based option).
 */
export function CheckpointScanner({ onScan, isSubmitting }: CheckpointScannerProps) {
  const [manualCode, setManualCode] = useState('');
  const [isCameraOpen, setIsCameraOpen] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const cameraSupported = typeof window !== 'undefined' && 'BarcodeDetector' in window && typeof navigator !== 'undefined' && Boolean(navigator.mediaDevices);

  useEffect(() => {
    if (!isCameraOpen) return;
    let cancelled = false;
    let detectTimer: ReturnType<typeof setInterval> | undefined;

    async function start() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop());
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }

        const DetectorCtor = window.BarcodeDetector;
        if (!DetectorCtor) return;
        const detector = new DetectorCtor({ formats: ['qr_code'] });

        detectTimer = setInterval(() => {
          void (async () => {
            if (!videoRef.current || cancelled) return;
            try {
              const results = await detector.detect(videoRef.current);
              const value = results[0]?.rawValue;
              if (value) {
                setIsCameraOpen(false);
                void onScan(value, 'qr');
              }
            } catch {
              // A single failed detection frame isn't fatal — keep trying until the interval is cleared.
            }
          })();
        }, 600);
      } catch {
        if (!cancelled) setCameraError('Camera access was denied or is unavailable. Use manual entry instead.');
      }
    }

    void start();

    return () => {
      cancelled = true;
      if (detectTimer) clearInterval(detectTimer);
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    };
  }, [isCameraOpen, onScan]);

  return (
    <div className="flex flex-col gap-3">
      {cameraSupported && (
        <div>
          {!isCameraOpen ? (
            <Button
              variant="secondary"
              onClick={() => {
                setCameraError(null);
                setIsCameraOpen(true);
              }}
            >
              Scan with camera
            </Button>
          ) : (
            <div className="flex flex-col gap-2">
              <video ref={videoRef} className="aspect-video w-full rounded-lg bg-black" muted playsInline />
              <Button variant="ghost" onClick={() => setIsCameraOpen(false)}>
                Stop camera
              </Button>
            </div>
          )}
          {cameraError && <p className="mt-1 text-xs text-danger-600">{cameraError}</p>}
        </div>
      )}

      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (!manualCode.trim()) return;
          void onScan(manualCode.trim(), 'manual');
          setManualCode('');
        }}
        className="flex items-end gap-2"
      >
        <TextField
          label="Checkpoint code"
          placeholder="e.g. CP-A"
          value={manualCode}
          onChange={(event) => setManualCode(event.target.value)}
          containerClassName="flex-1"
        />
        <Button type="submit" isLoading={isSubmitting} disabled={!manualCode.trim()}>
          Scan
        </Button>
      </form>
    </div>
  );
}
