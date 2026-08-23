import React from 'react';

const inline = value => String(value).split(/(\*\*[^*]+\*\*)/g).map((part, index) =>
  part.startsWith('**') && part.endsWith('**')
    ? <strong key={index}>{part.slice(2, -2)}</strong>
    : <React.Fragment key={index}>{part}</React.Fragment>);

const cells = line =>
  line.trim().replace(/^\||\|$/g, '').split('|').map(cell => cell.trim());

const normalizeHeader = value => String(value || '').trim().toLowerCase();

const isClinicalFindingsTable = header => {
  const normalized = header.map(normalizeHeader);
  return normalized.length === 4
    && normalized.includes('fdi tooth number')
    && normalized.includes('clinical description')
    && normalized.includes('icd-10 code')
    && normalized.includes('diagnosis');
};

const minimumColumnWidth = header => {
  const value = normalizeHeader(header);

  if (value.includes('instruction')) return 240;
  if (value.includes('medication') || value.includes('brand')) return 190;
  if (value.includes('generic')) return 180;
  if (value.includes('dosage form') || value === 'form') return 140;
  if (value.includes('frequency')) return 140;
  if (value.includes('duration')) return 125;
  if (value.includes('strength')) return 120;
  if (value === 'dose' || value.includes('dose')) return 120;
  if (value.includes('route')) return 105;

  return 135;
};

export default function MedicalReportMarkdown({ markdown = '' }) {
  const lines = String(markdown).replace(/\r\n/g, '\n').split('\n');
  const blocks = [];

  for (let index = 0; index < lines.length;) {
    const line = lines[index].trim();

    if (!line) {
      index += 1;
      continue;
    }

    if (line.startsWith('# ')) {
      blocks.push(
        <h1
          key={index}
          style={{
            paddingBottom: 12,
            borderBottom: '2px solid var(--clr-primary)',
          }}
        >
          {line.slice(2)}
        </h1>,
      );
      index += 1;
      continue;
    }

    if (line.startsWith('## ')) {
      blocks.push(
        <h2 key={index} style={{ marginTop: 28 }}>
          {line.slice(3)}
        </h2>,
      );
      index += 1;
      continue;
    }

    if (line.startsWith('|')) {
      const tableLines = [];

      while (
        index < lines.length
        && lines[index].trim().startsWith('|')
      ) {
        tableLines.push(lines[index++]);
      }

      const header = cells(tableLines[0]);
      const rows = tableLines.slice(2).map(cells);
      const clinicalFindingsTable = isClinicalFindingsTable(header);

      const adaptiveMinimumWidth = header.reduce(
        (total, column) => total + minimumColumnWidth(column),
        0,
      );

      blocks.push(
        <div
          key={`table-${index}`}
          className="medical-report-table-wrap"
          style={{
            width: '100%',
            overflowX: 'auto',
            margin: '14px 0 20px',
            border: '1px solid var(--clr-border)',
            borderRadius: 12,
          }}
        >
          <table
            className="medical-report-table"
            style={{
              width: '100%',
              minWidth: clinicalFindingsTable
                ? 720
                : Math.max(720, adaptiveMinimumWidth),
              borderCollapse: 'collapse',
              tableLayout: clinicalFindingsTable ? 'fixed' : 'auto',
              background: 'white',
            }}
          >
            <thead>
              <tr>
                {header.map((cell, cellIndex) => (
                  <th
                    key={`${cell}-${cellIndex}`}
                    style={{
                      padding: '12px 14px',
                      textAlign: 'left',
                      background: '#f1f5f9',
                      borderBottom: '1px solid var(--clr-border)',
                      fontSize: '.78rem',
                      lineHeight: 1.35,
                      whiteSpace: 'nowrap',
                      verticalAlign: 'bottom',
                      width: clinicalFindingsTable
                        ? ['14%', '38%', '18%', '30%'][cellIndex]
                        : undefined,
                      minWidth: clinicalFindingsTable
                        ? undefined
                        : minimumColumnWidth(cell),
                    }}
                  >
                    {inline(cell)}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              {rows.map((row, rowIndex) => (
                <tr
                  key={rowIndex}
                  style={{
                    borderBottom: rowIndex === rows.length - 1
                      ? 'none'
                      : '1px solid var(--clr-border)',
                    verticalAlign: 'top',
                  }}
                >
                  {header.map((_, cellIndex) => (
                    <td
                      key={cellIndex}
                      style={{
                        padding: '13px 14px',
                        lineHeight: 1.55,
                        overflowWrap: 'break-word',
                        wordBreak: 'normal',
                        verticalAlign: 'top',
                      }}
                    >
                      {inline(row[cellIndex] || '')}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>,
      );

      continue;
    }

    if (line.startsWith('- ')) {
      const items = [];

      while (
        index < lines.length
        && lines[index].trim().startsWith('- ')
      ) {
        items.push(lines[index++].trim().slice(2));
      }

      blocks.push(
        <ul
          key={`list-${index}`}
          style={{ lineHeight: 1.7, paddingLeft: 22 }}
        >
          {items.map((item, itemIndex) => (
            <li key={itemIndex}>{inline(item)}</li>
          ))}
        </ul>,
      );

      continue;
    }

    const paragraph = [];

    while (
      index < lines.length
      && lines[index].trim()
      && !lines[index].trim().startsWith('#')
      && !lines[index].trim().startsWith('|')
      && !lines[index].trim().startsWith('- ')
    ) {
      paragraph.push(lines[index++].trim());
    }

    blocks.push(
      <p key={`p-${index}`} style={{ lineHeight: 1.7 }}>
        {inline(paragraph.join(' '))}
      </p>,
    );
  }

  return (
    <article
      className="medical-report-markdown"
      style={{
        maxWidth: 1040,
        margin: '0 auto',
        color: 'var(--clr-text)',
      }}
    >
      {blocks}
    </article>
  );
}
