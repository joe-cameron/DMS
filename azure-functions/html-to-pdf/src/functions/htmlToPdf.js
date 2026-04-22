const { app } = require('@azure/functions');
const JSZip = require('jszip');

app.http('html-to-pdf', {
  methods: ['POST'],
  authLevel: 'function',
  handler: async (request, context) => {
    try {
      const body = await request.json();
      const { template_base64, field_map, options } = body;

      if (!template_base64 || !field_map) {
        return { status: 400, body: 'Missing "template_base64" and/or "field_map"' };
      }

      const opts = {
        clean_highlights: true,
        preserve_signature_blanks: true,
        date_format: 'MMMM d, yyyy',
        ...options
      };

      // Load .docx as ZIP
      const templateBuffer = Buffer.from(template_base64, 'base64');
      const zip = await JSZip.loadAsync(templateBuffer);

      // Process all XML parts that can contain fields
      const xmlParts = [];
      for (const filename of Object.keys(zip.files)) {
        if (filename === 'word/document.xml' ||
            filename.match(/^word\/header\d+\.xml$/) ||
            filename.match(/^word\/footer\d+\.xml$/)) {
          xmlParts.push(filename);
        }
      }

      const warnings = [];
      let fieldsInjected = 0;
      let fieldsSkipped = 0;

      for (const part of xmlParts) {
        let xml = await zip.files[part].async('string');

        for (const field of field_map) {
          const result = injectField(xml, field, opts);
          xml = result.xml;
          if (result.injected) {
            fieldsInjected += result.count;
          } else if (part === 'word/document.xml') {
            // Only warn for missing fields in the main document body
            fieldsSkipped++;
            if (field.tag || field.placeholder) {
              warnings.push(`Field '${field.tag || field.placeholder}' not found in document body`);
            }
          }
        }

        zip.file(part, xml, { createFolders: false });
      }

      // Generate output .docx
      const outputBuffer = await zip.generateAsync({
        type: 'nodebuffer',
        compression: 'DEFLATE',
        compressionOptions: { level: 6 }
      });

      const outputBase64 = outputBuffer.toString('base64');

      return {
        jsonBody: {
          success: true,
          document_base64: outputBase64,
          fields_injected: fieldsInjected,
          fields_skipped: fieldsSkipped,
          warnings
        }
      };

    } catch (err) {
      context.error('OOXML injection failed:', err);
      return {
        status: 500,
        jsonBody: {
          success: false,
          error: err.message
        }
      };
    }
  }
});

/**
 * Inject a single field into the XML using the appropriate strategy.
 * Returns { xml, injected, count }
 */
function injectField(xml, field, opts) {
  switch (field.marker_type) {
    case 'content-control':
      return injectContentControl(xml, field, opts);
    case 'merge-field':
      return injectMergeField(xml, field, opts);
    case 'highlight':
      return injectHighlight(xml, field, opts);
    case 'placeholder':
      return injectPlaceholder(xml, field, opts);
    case 'underline-blank':
      return injectUnderlineBlank(xml, field, opts);
    default:
      // Try all strategies in order
      let result = injectContentControl(xml, field, opts);
      if (result.injected) return result;
      result = injectHighlight(xml, field, opts);
      if (result.injected) return result;
      result = injectMergeField(xml, field, opts);
      if (result.injected) return result;
      result = injectPlaceholder(xml, field, opts);
      if (result.injected) return result;
      return { xml, injected: false, count: 0 };
  }
}

/**
 * Strategy 1: Content Controls (w:sdt)
 * Find by w:tag value, replace w:t text inside w:sdtContent
 */
function injectContentControl(xml, field, opts) {
  const tag = field.tag;
  if (!tag) return { xml, injected: false, count: 0 };

  // Match the entire sdt block containing this tag
  const tagPattern = new RegExp(
    `(<w:sdt>\\s*<w:sdtPr>[\\s\\S]*?<w:tag\\s+w:val="${escapeRegex(tag)}"\\s*/>` +
    `[\\s\\S]*?<w:sdtContent>)([\\s\\S]*?)(</w:sdtContent>\\s*</w:sdt>)`,
    'g'
  );

  let count = 0;
  const value = formatValue(field.value, field.format_hint, opts);

  const newXml = xml.replace(tagPattern, (match, before, content, after) => {
    count++;
    // Extract the first run's formatting (w:rPr) to preserve it
    const rPrMatch = content.match(/<w:rPr>([\s\S]*?)<\/w:rPr>/);
    let rPrInner = rPrMatch ? rPrMatch[1] : '';
    // Add bold to all injected values so filled-in data stands out
    if (!/<w:b[\s/>]/.test(rPrInner)) rPrInner = '<w:b/>' + rPrInner;
    const rPr = `<w:rPr>${rPrInner}</w:rPr>`;

    // Detect block-level SDT (sdtContent contains w:p) vs inline
    // Block-level MUST wrap run in <w:p> per OOXML spec 17.5.2.34
    const isBlockLevel = /<w:p[\s>]/.test(content);

    // Preserve paragraph properties (alignment, spacing, etc.)
    const pPrMatch = content.match(/<w:pPr>([\s\S]*?)<\/w:pPr>/);
    const pPr = pPrMatch ? `<w:pPr>${pPrMatch[1]}</w:pPr>` : '';

    const run = `<w:r>${rPr}<w:t xml:space="preserve">${escapeXml(value)}</w:t></w:r>`;
    const newContent = isBlockLevel ? `<w:p>${pPr}${run}</w:p>` : run;
    return before + newContent + after;
  });

  return { xml: newXml, injected: count > 0, count };
}

/**
 * Strategy 2: Merge Fields (MERGEFIELD)
 * Replace the entire field complex with a simple text run
 */
function injectMergeField(xml, field, opts) {
  const tag = field.tag;
  if (!tag) return { xml, injected: false, count: 0 };

  // Match MERGEFIELD complex: begin fldChar → instrText → separate fldChar → result → end fldChar
  // This can span multiple w:r elements within a paragraph
  const pattern = new RegExp(
    `<w:r[^>]*>\\s*<w:fldChar\\s+w:fldCharType="begin"[^/]*/>[\\s\\S]*?` +
    `MERGEFIELD\\s+${escapeRegex(tag)}[\\s\\S]*?` +
    `<w:fldChar\\s+w:fldCharType="end"[^/]*/>[\\s\\S]*?</w:r>`,
    'g'
  );

  let count = 0;
  const value = formatValue(field.value, field.format_hint, opts);

  const newXml = xml.replace(pattern, () => {
    count++;
    return `<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">${escapeXml(value)}</w:t></w:r>`;
  });

  return { xml: newXml, injected: count > 0, count };
}

/**
 * Strategy 3: Yellow Highlights
 * Find consecutive highlighted runs matching placeholder text, replace with value
 */
function injectHighlight(xml, field, opts) {
  const placeholder = field.placeholder;
  if (!placeholder) return { xml, injected: false, count: 0 };

  const normalizedPlaceholder = placeholder.trim().replace(/\s+/g, ' ').toLowerCase();
  let count = 0;
  const value = formatValue(field.value, field.format_hint, opts);

  // Process paragraph by paragraph
  const newXml = xml.replace(/<w:p[\s>][\s\S]*?<\/w:p>/g, (paragraph) => {
    // Find highlighted run sequences
    const runs = [];
    const runRegex = /<w:r[\s>][\s\S]*?<\/w:r>/g;
    let runMatch;
    let lastIndex = 0;
    const segments = []; // mix of text and run objects

    while ((runMatch = runRegex.exec(paragraph)) !== null) {
      // Save text between runs
      if (runMatch.index > lastIndex) {
        segments.push({ type: 'raw', text: paragraph.substring(lastIndex, runMatch.index) });
      }

      const runXml = runMatch[0];
      const isHighlighted = /w:highlight\s+w:val="yellow"/.test(runXml);
      const textMatch = runXml.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/);
      const text = textMatch ? textMatch[1] : '';
      const rPrMatch = runXml.match(/<w:rPr>([\s\S]*?)<\/w:rPr>/);
      const rPr = rPrMatch ? rPrMatch[1] : '';

      segments.push({
        type: 'run',
        xml: runXml,
        highlighted: isHighlighted,
        text,
        rPr,
        index: runMatch.index
      });

      lastIndex = runMatch.index + runMatch[0].length;
    }

    // Save trailing text
    if (lastIndex < paragraph.length) {
      segments.push({ type: 'raw', text: paragraph.substring(lastIndex) });
    }

    // Find consecutive highlighted runs and check if their text matches placeholder
    let i = 0;
    const newSegments = [];
    while (i < segments.length) {
      if (segments[i].type === 'run' && segments[i].highlighted) {
        // Accumulate consecutive highlighted runs
        let accText = '';
        let startIdx = i;
        let firstRPr = segments[i].rPr;

        while (i < segments.length && segments[i].type === 'run' && segments[i].highlighted) {
          accText += segments[i].text;
          i++;
        }

        const normalizedAcc = accText.trim().replace(/\s+/g, ' ').toLowerCase();

        if (normalizedAcc === normalizedPlaceholder) {
          count++;
          // Build replacement run - remove highlight, keep other formatting
          let cleanRPr = firstRPr.replace(/<w:highlight[^/]*\/>/g, '');
          if (!opts.clean_highlights) {
            cleanRPr = firstRPr; // keep highlight
          }
          // Add bold to all injected values
          if (cleanRPr && !/<w:b[\s/>]/.test(cleanRPr)) cleanRPr = '<w:b/>' + cleanRPr;
          else if (!cleanRPr) cleanRPr = '<w:b/>';
          const rPrTag = `<w:rPr>${cleanRPr}</w:rPr>`;
          newSegments.push({
            type: 'raw',
            text: `<w:r>${rPrTag}<w:t xml:space="preserve">${escapeXml(value)}</w:t></w:r>`
          });
        } else {
          // Not a match — keep original runs
          for (let j = startIdx; j < i; j++) {
            newSegments.push(segments[j]);
          }
        }
      } else {
        newSegments.push(segments[i]);
        i++;
      }
    }

    if (count > 0) {
      return newSegments.map(s => s.type === 'raw' ? s.text : s.xml).join('');
    }
    return paragraph;
  });

  return { xml: newXml, injected: count > 0, count };
}

/**
 * Strategy 4: Bracket/Brace/Angle Placeholders
 * Simple text replacement in w:t elements
 */
function injectPlaceholder(xml, field, opts) {
  const placeholder = field.placeholder;
  if (!placeholder) return { xml, injected: false, count: 0 };

  let count = 0;
  const value = formatValue(field.value, field.format_hint, opts);

  // Replace in w:t elements
  const newXml = xml.replace(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g, (match, text) => {
    if (text.includes(placeholder)) {
      count++;
      const newText = text.replace(placeholder, escapeXml(value));
      return match.replace(text, newText);
    }
    return match;
  });

  return { xml: newXml, injected: count > 0, count };
}

/**
 * Strategy 5: Underline Blanks (signature lines)
 */
function injectUnderlineBlank(xml, field, opts) {
  const placeholder = field.placeholder;
  if (!placeholder) return { xml, injected: false, count: 0 };

  if (opts.preserve_signature_blanks && !field.value) {
    return { xml, injected: true, count: 1 }; // Leave as-is
  }

  let count = 0;
  const value = field.value || '';

  const newXml = xml.replace(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g, (match, text) => {
    if (text.includes(placeholder)) {
      count++;
      if (value) {
        return match.replace(text, escapeXml(value));
      }
      return match; // Leave blanks
    }
    return match;
  });

  return { xml: newXml, injected: count > 0, count };
}

/**
 * Format a value based on format_hint
 */
function formatValue(value, hint, opts) {
  if (value === null || value === undefined) return '';
  const str = String(value);
  if (!str) return '';

  switch (hint) {
    case 'date': {
      try {
        const d = new Date(str);
        if (isNaN(d.getTime())) return str;
        const months = ['January','February','March','April','May','June',
                        'July','August','September','October','November','December'];
        return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
      } catch { return str; }
    }
    case 'currency': {
      const num = parseFloat(str.replace(/[,$]/g, ''));
      if (isNaN(num)) return str;
      return '$' + num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    default:
      return str;
  }
}

function escapeXml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
  // Single quotes don't need escaping in <w:t> text content
  // and &apos; is not recognized by some OOXML parsers
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
