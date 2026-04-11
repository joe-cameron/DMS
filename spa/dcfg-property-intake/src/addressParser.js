/**
 * Parse UpKeep's single-string address into components.
 * Format: "123 Main St, Denver, CO 80202, USA"
 * Returns: { street, city, state, zip }
 */
export function parseUpKeepAddress(raw) {
  if (!raw) return { street: '', city: '', state: '', zip: '' };

  const parts = raw.split(',').map(s => s.trim());

  if (parts.length >= 3) {
    const street = parts[0];
    const city = parts[1];
    // "CO 80202" or "CO 80202" pattern — state + zip in one segment
    const stateZip = parts[2].replace(/USA$/i, '').trim();
    const szMatch = stateZip.match(/^([A-Z]{2})\s*(\d{5}(-\d{4})?)$/);
    if (szMatch) {
      return { street, city, state: szMatch[1], zip: szMatch[2] };
    }
    // Fallback: state only, zip might be in next segment
    return { street, city, state: stateZip, zip: parts[3]?.replace(/USA$/i, '').trim() || '' };
  }

  if (parts.length === 2) {
    return { street: parts[0], city: parts[1], state: '', zip: '' };
  }

  return { street: raw, city: '', state: '', zip: '' };
}
