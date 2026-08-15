import React, { useState } from 'react';
import { ChevronDown, ChevronUp, ClipboardList } from 'lucide-react';

export default function PreviousConsultationNoteCurtain({ previousNote }) {
  const [expanded, setExpanded] = useState(true);
  const note = previousNote?.sessionNote?.trim();

  return (
    <section
      className={`previous-note-curtain ${expanded ? 'is-expanded' : 'is-collapsed'}`}
      aria-label="Previous Consultation Note"
    >
      <div className="previous-note-curtain__panel" aria-hidden={!expanded}>
        <div className="previous-note-curtain__content">
          <div className="previous-note-curtain__heading">
            <span className="previous-note-curtain__icon"><ClipboardList size={17} /></span>
            <div>
              <h2>Previous Consultation Note</h2>
              {previousNote?.date && (
                <time dateTime={previousNote.date}>
                  {new Date(previousNote.date).toLocaleString()}
                </time>
              )}
            </div>
          </div>
          <div className={`previous-note-curtain__note ${note ? '' : 'is-empty'}`}>
            {note || 'No notes from the previous consultation.'}
          </div>
        </div>
      </div>
      <button
        type="button"
        className="previous-note-curtain__handle"
        onClick={() => setExpanded(value => !value)}
        aria-expanded={expanded}
        aria-label={expanded ? 'Collapse previous consultation note' : 'Expand previous consultation note'}
      >
        {expanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
        <span>{expanded ? 'Hide previous note' : 'Previous note'}</span>
      </button>
    </section>
  );
}
