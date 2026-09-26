"use client";

// Remounting on viewKey change (rather than diffing) is what makes the CSS
// animation replay on every nav/switch -- a fresh DOM node always restarts
// its animation, an updated one wouldn't. prefers-reduced-motion is already
// handled globally (globals.css collapses all animation-duration to ~0).
export function ViewTransition({
  viewKey,
  children,
}: {
  viewKey: string;
  children: React.ReactNode;
}) {
  return (
    <div key={viewKey} className="animate-[calendar-view-in_200ms_ease-out]">
      {children}
    </div>
  );
}
