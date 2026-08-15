import React from 'react';

const inline = value => String(value).split(/(\*\*[^*]+\*\*)/g).map((part, index) =>
  part.startsWith('**') && part.endsWith('**')
    ? <strong key={index}>{part.slice(2, -2)}</strong>
    : <React.Fragment key={index}>{part}</React.Fragment>);

const cells = line => line.trim().replace(/^\||\|$/g, '').split('|').map(cell => cell.trim());

export default function MedicalReportMarkdown({ markdown = '' }) {
  const lines = String(markdown).replace(/\r\n/g, '\n').split('\n');
  const blocks = [];
  for (let index = 0; index < lines.length;) {
    const line = lines[index].trim();
    if (!line) { index += 1; continue; }
    if (line.startsWith('# ')) {
      blocks.push(<h1 key={index} style={{ paddingBottom: 12, borderBottom: '2px solid var(--clr-primary)' }}>{line.slice(2)}</h1>);
      index += 1; continue;
    }
    if (line.startsWith('## ')) {
      blocks.push(<h2 key={index} style={{ marginTop: 28 }}>{line.slice(3)}</h2>);
      index += 1; continue;
    }
    if (line.startsWith('|')) {
      const tableLines = [];
      while (index < lines.length && lines[index].trim().startsWith('|')) tableLines.push(lines[index++]);
      const header = cells(tableLines[0]);
      const rows = tableLines.slice(2).map(cells);
      blocks.push(<div key={`table-${index}`} className="medical-report-table-wrap" style={{ overflowX: 'auto' }}>
        <table className="medical-report-table" style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed' }}>
          <thead><tr>{header.map((cell, cellIndex) => <th key={cell} style={{ padding: '12px 14px', textAlign: 'left', background: '#f1f5f9', width: ['14%', '38%', '18%', '30%'][cellIndex] }}>{inline(cell)}</th>)}</tr></thead>
          <tbody>{rows.map((row, rowIndex) => <tr key={rowIndex} style={{ borderBottom: '1px solid var(--clr-border)', verticalAlign: 'top' }}>
            {row.map((cell, cellIndex) => <td key={cellIndex} style={{ padding: '14px', lineHeight: 1.55, overflowWrap: 'anywhere' }}>{inline(cell)}</td>)}
          </tr>)}</tbody>
        </table>
      </div>);
      continue;
    }
    if (line.startsWith('- ')) {
      const items = [];
      while (index < lines.length && lines[index].trim().startsWith('- ')) {
        items.push(lines[index++].trim().slice(2));
      }
      blocks.push(<ul key={`list-${index}`} style={{ lineHeight: 1.7, paddingLeft: 22 }}>{items.map((item, itemIndex) => <li key={itemIndex}>{inline(item)}</li>)}</ul>);
      continue;
    }
    const paragraph = [];
    while (index < lines.length && lines[index].trim()
      && !lines[index].trim().startsWith('#')
      && !lines[index].trim().startsWith('|')
      && !lines[index].trim().startsWith('- ')) {
      paragraph.push(lines[index++].trim());
    }
    blocks.push(<p key={`p-${index}`} style={{ lineHeight: 1.7 }}>{inline(paragraph.join(' '))}</p>);
  }
  return <article className="medical-report-markdown" style={{ maxWidth: 1040, margin: '0 auto', color: 'var(--clr-text)' }}>{blocks}</article>;
}
