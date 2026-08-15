import { useEffect, useMemo, useRef, useState } from 'react';
import { Check, Search } from 'lucide-react';

export default function SearchableEntitySelect({
  id,
  options,
  value,
  onChange,
  filterOptions,
  placeholder,
  noMatchesText,
  loading = false,
  error,
  optionLabel = option => option.name,
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const rootRef = useRef(null);
  const searchRef = useRef(null);
  const selected = options.find(option => String(option.id) === String(value));
  const filtered = useMemo(() => filterOptions(options, query), [filterOptions, options, query]);

  useEffect(() => {
    if (open) searchRef.current?.focus();
  }, [open]);

  useEffect(() => {
    const closeOutside = event => {
      if (!rootRef.current?.contains(event.target)) {
        setOpen(false);
        setQuery('');
      }
    };
    document.addEventListener('mousedown', closeOutside);
    return () => document.removeEventListener('mousedown', closeOutside);
  }, []);

  const choose = option => {
    onChange(option.id);
    setOpen(false);
    setQuery('');
  };

  const toggle = () => {
    if (open) setQuery('');
    setOpen(!open);
  };

  const handleOptionKeyDown = event => {
    if (event.key === 'Escape') {
      setOpen(false);
      setQuery('');
      rootRef.current?.querySelector(`#${id}`)?.focus();
      return;
    }
    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
    event.preventDefault();
    const items = [...event.currentTarget.parentElement.querySelectorAll('[role="option"]')];
    const currentIndex = items.indexOf(event.currentTarget);
    const nextIndex = event.key === 'ArrowDown'
      ? Math.min(currentIndex + 1, items.length - 1)
      : Math.max(currentIndex - 1, 0);
    items[nextIndex]?.focus();
  };

  return (
    <div ref={rootRef} style={{ position: 'relative' }}>
      <button
        id={id}
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={toggle}
        disabled={loading || Boolean(error)}
        style={{
          width: '100%',
          padding: '8px 12px',
          border: '1px solid var(--clr-border)',
          borderRadius: 8,
          background: 'var(--clr-card)',
          color: 'var(--clr-text)',
          fontSize: '0.85rem',
          cursor: loading || error ? 'not-allowed' : 'pointer',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          textAlign: 'left',
          opacity: loading || error ? 0.65 : 1,
        }}
      >
        <span>{loading ? 'Loading…' : error || (selected ? optionLabel(selected) : placeholder)}</span>
        <span aria-hidden="true" style={{ fontSize: '0.7rem', color: 'var(--clr-subtext)' }}>▼</span>
      </button>
      {open && (
        <div style={{
          position: 'absolute',
          top: '100%',
          left: 0,
          right: 0,
          zIndex: 999999,
          background: 'var(--clr-card)',
          border: '1px solid var(--clr-border)',
          borderRadius: 8,
          boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
          marginTop: 4,
          padding: 8,
          display: 'flex',
          flexDirection: 'column',
          gap: 6,
          maxHeight: 220,
          overflowY: 'auto',
        }}>
          <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
            <Search size={13} aria-hidden="true" style={{ position: 'absolute', left: 8, color: 'var(--clr-subtext)' }} />
            <input
              ref={searchRef}
              className="form-input"
              aria-label={`Search ${placeholder.toLowerCase()}`}
              value={query}
              onChange={event => setQuery(event.target.value)}
              onKeyDown={event => {
                if (event.key === 'Escape') { setOpen(false); setQuery(''); }
                if (event.key === 'ArrowDown') {
                  event.preventDefault();
                  event.currentTarget.parentElement?.nextElementSibling?.querySelector('button')?.focus();
                }
              }}
              placeholder={`Search ${placeholder.toLowerCase()}…`}
              style={{ width: '100%', paddingLeft: 26, fontSize: '0.78rem', margin: 0, height: 30 }}
            />
          </div>
          <div role="listbox" aria-labelledby={id} style={{ display: 'flex', flexDirection: 'column', gap: 2, overflowY: 'auto', flex: 1 }}>
            {filtered.length === 0 ? (
              <div style={{ padding: '6px 10px', color: 'var(--clr-subtext)', fontSize: '0.82rem' }}>{noMatchesText}</div>
            ) : filtered.map(option => (
              <button
                type="button"
                role="option"
                aria-selected={String(option.id) === String(value)}
                key={option.id}
                onClick={() => choose(option)}
                onKeyDown={handleOptionKeyDown}
                onMouseEnter={event => {
                  if (String(option.id) !== String(value)) event.currentTarget.style.background = 'var(--clr-bg)';
                }}
                onMouseLeave={event => {
                  if (String(option.id) !== String(value)) event.currentTarget.style.background = 'transparent';
                }}
                style={{
                  width: '100%',
                  border: 0,
                  padding: '6px 10px',
                  borderRadius: 6,
                  cursor: 'pointer',
                  fontSize: '0.82rem',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  textAlign: 'left',
                  background: String(option.id) === String(value) ? 'var(--clr-primary-light)' : 'transparent',
                  color: String(option.id) === String(value) ? 'var(--clr-primary-dark)' : 'var(--clr-text)',
                }}
              >
                <span>{optionLabel(option)}</span>
                {String(option.id) === String(value) && <Check size={12} aria-hidden="true" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
